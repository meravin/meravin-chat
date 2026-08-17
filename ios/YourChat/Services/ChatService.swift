import Foundation
import Observation

/// Owns the single WebSocket and the three channels' message lists.
///
/// The order that matters: show the bubble locally, then send. The relay
/// persists before it acks, so a message that got through is never lost — and
/// one that didn't is still in the outbox to retry with the same UUID, which
/// the relay dedupes.
@MainActor
@Observable
final class ChatService {
    enum ConnectionState: Equatable, Sendable {
        case idle
        case connecting
        case online
        case offline(String?)

        var isOnline: Bool { self == .online }

        var label: String {
            switch self {
            case .idle: "未连接"
            case .connecting: "连接中"
            case .online: "在线"
            case .offline: "离线"
            }
        }
    }

    struct AgentStatus: Equatable, Sendable {
        var state: ServerEvent.AgentState = .idle
        var detail: String?
    }

    // MARK: - Observable state

    private(set) var messages: [ChatChannel: [ChatMessage]] = [:]
    private(set) var connection: ConnectionState = .idle
    /// Per channel, per agent — drives the typing indicator and the
    /// "AI 暂时不可用" line instead of a spinner that never stops.
    private(set) var agentStatus: [ChatChannel: [ChatSender: AgentStatus]] = [:]
    /// Unsent text per channel; the Chats list shows a 草稿 marker for these.
    var drafts: [ChatChannel: String] = [:]

    // MARK: - Private

    private let config: RelayConfig
    private let store: ChatStore
    private let session: URLSession

    private var task: URLSessionWebSocketTask?
    private var receiveLoop: Task<Void, Never>?
    private var reconnectTask: Task<Void, Never>?
    private var reconnectAttempt = 0
    /// Sent, not yet acked. Keyed by id so an ack is an O(1) removal.
    private var outbox: [UUID: ChatMessage] = [:]
    private var didLoadFromDisk = false

    /// Paging state for scrolling up. `false` means we've reached the beginning
    /// and must stop asking. Reset by every `history` snapshot, which replaces
    /// the list — otherwise a channel paged to its start would keep claiming
    /// there is nothing older after a reconnect truncated it back to one page.
    private(set) var hasMoreHistory: [ChatChannel: Bool] = [:]
    private(set) var isLoadingOlder: Set<ChatChannel> = []
    /// Opaque cursor for the page before the oldest message we hold.
    private var historyCursor: [ChatChannel: String] = [:]
    /// Set when the relay rejects a frame. Distinct from `connection`: the
    /// socket is fine, one message wasn't.
    private(set) var lastRejection: String?
    private let api: APIClient

    init(config: RelayConfig, api: APIClient? = nil, store: ChatStore = ChatStore()) {
        self.config = config
        self.api = api ?? APIClient(config: config)
        self.store = store

        let configuration = URLSessionConfiguration.default
        configuration.waitsForConnectivity = true
        configuration.timeoutIntervalForRequest = 30
        session = URLSession(configuration: configuration)
    }

    // MARK: - Lifecycle

    func start() async {
        if !didLoadFromDisk {
            didLoadFromDisk = true
            messages = await store.loadCache()
            for message in await store.loadOutbox() {
                outbox[message.id] = message
                insert(message, into: message.channel)
            }
        }
        connect()
    }

    func connect() {
        guard config.isConfigured else {
            connection = .offline("还没有配置消息桥地址和令牌")
            return
        }
        guard task == nil else { return }

        connection = .connecting
        var request = URLRequest(url: config.webSocketURL)
        // A native client can set headers, so it never needs the ticket dance
        // the browser path uses.
        config.authorize(&request)

        let socket = session.webSocketTask(with: request)
        task = socket
        socket.resume()

        receiveLoop = Task { [weak self] in
            await self?.receiveMessages(on: socket)
        }
    }

    func disconnect() {
        reconnectTask?.cancel()
        reconnectTask = nil
        receiveLoop?.cancel()
        receiveLoop = nil
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        connection = .idle
    }

    /// Called when the app returns to the foreground: reconnect and re-fetch.
    func refresh() {
        guard case .online = connection else {
            disconnect()
            connect()
            return
        }
    }

    // MARK: - Sending

    func send(_ rawText: String, to channel: ChatChannel) {
        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        // The UUID is generated here and reused on every retry — that is what
        // lets the relay recognise a resend instead of storing a duplicate.
        let message = ChatMessage(
            channel: channel,
            sender: .user,
            text: text,
            delivery: .sending)

        insert(message, into: channel)   // 1. bubble appears immediately
        outbox[message.id] = message
        drafts[channel] = nil
        lastRejection = nil              // a new attempt clears the last complaint
        persist()

        transmit(message)                // 2. then it goes on the wire
    }

    // MARK: - Paging

    /// Loads the page before the oldest message on screen. Called when the top
    /// of the transcript scrolls into view; a no-op once the start is reached.
    func loadOlder(in channel: ChatChannel) async {
        guard hasMoreHistory[channel] != false else { return }
        guard !isLoadingOlder.contains(channel) else { return }
        guard let cursor = historyCursor[channel] else { return }

        isLoadingOlder.insert(channel)
        defer { isLoadingOlder.remove(channel) }

        do {
            let page = try await api.messages(in: channel, cursor: cursor)
            historyCursor[channel] = page.nextCursor
            hasMoreHistory[channel] = page.hasMore

            // Prepend only what we don't already have — a page can overlap the
            // one above it when a reconnect re-seeded the list.
            let known = Set((messages[channel] ?? []).map(\.id))
            let fresh = page.messages.filter { !known.contains($0.id) }
            guard !fresh.isEmpty else { return }

            messages[channel] = (fresh + (messages[channel] ?? [])).sorted { $0.time < $1.time }
            persist()
        } catch {
            // Leave the cursor and `hasMoreHistory` alone so a later scroll retries.
        }
    }

    /// Re-sends everything still unacked. Safe by construction: same UUIDs.
    private func flushOutbox() {
        for message in outbox.values.sorted(by: { $0.time < $1.time }) {
            transmit(message)
        }
    }

    private func transmit(_ message: ChatMessage) {
        guard let task else { return }
        let frame = OutboundMessage(id: message.id, channel: message.channel, text: message.text)
        guard let data = try? JSONEncoder().encode(frame),
              let json = String(data: data, encoding: .utf8)
        else { return }

        task.send(.string(json)) { [weak self] error in
            guard error != nil else { return }
            // Leave it in the outbox; the reconnect path will retry it.
            Task { @MainActor in self?.handleDisconnect(reason: error?.localizedDescription) }
        }
    }

    // MARK: - Receiving

    private func receiveMessages(on socket: URLSessionWebSocketTask) async {
        while !Task.isCancelled {
            do {
                let frame = try await socket.receive()
                if connection != .online {
                    connection = .online
                    reconnectAttempt = 0
                    flushOutbox()
                }
                switch frame {
                case .string(let text):
                    handle(text)
                case .data(let data):
                    handle(String(decoding: data, as: UTF8.self))
                @unknown default:
                    break
                }
            } catch {
                guard !Task.isCancelled else { return }
                handleDisconnect(reason: error.localizedDescription)
                return
            }
        }
    }

    private func handle(_ text: String) {
        guard let data = text.data(using: .utf8),
              let event = try? JSONDecoder().decode(ServerEvent.self, from: data)
        else { return }

        switch event {
        case .history(let channel, let incoming, let cursor):
            merge(history: incoming, into: channel)
            // The snapshot replaced the list, so paging state has to follow it.
            historyCursor[channel] = cursor
            hasMoreHistory[channel] = cursor != nil
            persist()

        case .ack(_, let id, let time):
            outbox[id] = nil
            markDelivered(id: id, time: time)
            persist()

        case .delta(let channel, let message):
            insert(message, into: channel)
            persist()

        case .status(let channel, let agent, let state, let detail):
            agentStatus[channel, default: [:]][agent] = AgentStatus(state: state, detail: detail)

        case .failure(let code, let message):
            // A rejected frame is a bad message, not a dead socket — reporting
            // it as `offline` would leave the app claiming no connection while
            // the socket happily carries the next message.
            lastRejection = message.isEmpty ? code : "\(code): \(message)"
        }
    }

    private func handleDisconnect(reason: String?) {
        task?.cancel(with: .abnormalClosure, reason: nil)
        task = nil
        receiveLoop?.cancel()
        receiveLoop = nil
        connection = .offline(reason)
        scheduleReconnect()
    }

    private func scheduleReconnect() {
        guard reconnectTask == nil else { return }
        reconnectAttempt += 1
        // 1s, 2s, 4s … capped at 30s so a long offline stretch doesn't spin.
        let delay = min(pow(2.0, Double(reconnectAttempt - 1)), 30)

        reconnectTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self else { return }
                self.reconnectTask = nil
                self.connect()
            }
        }
    }

    // MARK: - Merging

    /// A full page from the server replaces what we cached, but anything still
    /// in the outbox is re-appended so an unsent bubble never disappears.
    private func merge(history: [ChatMessage], into channel: ChatChannel) {
        var list = history
        let known = Set(list.map(\.id))
        for pending in outbox.values where pending.channel == channel && !known.contains(pending.id) {
            list.append(pending)
        }
        messages[channel] = list.sorted { $0.time < $1.time }
    }

    /// Merge by id: our own optimistic bubble is updated in place, and only a
    /// genuinely new message is appended. Without this the user's own message
    /// appears twice — once locally, once when the relay echoes it back.
    private func insert(_ message: ChatMessage, into channel: ChatChannel) {
        var list = messages[channel] ?? []
        if let index = list.firstIndex(where: { $0.id == message.id }) {
            let wasSending = list[index].delivery == .sending
            list[index].text = message.text
            list[index].hop = message.hop
            list[index].replyTo = message.replyTo
            if message.time > 0 { list[index].time = message.time }
            // An echo of our own message confirms delivery.
            list[index].delivery = wasSending && message.time > 0 ? .sent : list[index].delivery
        } else {
            list.append(message)
            list.sort { $0.time < $1.time }
        }
        messages[channel] = list
    }

    private func markDelivered(id: UUID, time: Int64) {
        for channel in ChatChannel.allCases {
            guard let index = messages[channel]?.firstIndex(where: { $0.id == id }) else { continue }
            messages[channel]?[index].delivery = .sent
            messages[channel]?[index].time = time
            messages[channel]?.sort { $0.time < $1.time }
            return
        }
    }

    private func persist() {
        let snapshot = messages
        let pending = Array(outbox.values)
        Task { [store] in
            await store.saveCache(snapshot)
            await store.saveOutbox(pending)
        }
    }

    // MARK: - Reads for the UI

    func messages(in channel: ChatChannel) -> [ChatMessage] { messages[channel] ?? [] }

    func lastMessage(in channel: ChatChannel) -> ChatMessage? { messages[channel]?.last }

    func status(in channel: ChatChannel) -> [ChatSender: AgentStatus] { agentStatus[channel] ?? [:] }

    /// True while any agent on this channel is mid-reply.
    func isThinking(in channel: ChatChannel) -> Bool {
        status(in: channel).values.contains { $0.state == .thinking }
    }

    /// The first agent error on this channel, if any.
    func errorDetail(in channel: ChatChannel) -> String? {
        status(in: channel).values.first { $0.state == .error }?.detail
    }

    var unsentCount: Int { outbox.count }
}
