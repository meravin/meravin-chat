import Foundation

/// The three conversation entry points: two private chats and the group.
/// Raw values are the wire `channel` field and must match the relay exactly.
enum ChatChannel: String, Codable, CaseIterable, Identifiable, Sendable {
    case aiA = "ai_a"
    case aiB = "ai_b"
    case group

    var id: String { rawValue }
}

enum ChatSender: String, Codable, Sendable {
    case user
    case aiA = "ai_a"
    case aiB = "ai_b"

    var isAgent: Bool { self != .user }
}

struct ChatMessage: Identifiable, Codable, Equatable, Sendable {
    /// Local-only. The relay never sends it; the cache keeps it so a bubble
    /// still reads "sending" after a cold launch with the outbox unflushed.
    enum Delivery: String, Codable, Sendable {
        case sending
        case sent
    }

    let id: UUID
    let channel: ChatChannel
    let sender: ChatSender
    var text: String
    /// Server write time, milliseconds since epoch. The server's clock wins so
    /// a phone with a skewed clock can't reorder history.
    var time: Int64
    var replyTo: UUID?
    var hop: Int
    var delivery: Delivery

    var date: Date { Date(timeIntervalSince1970: TimeInterval(time) / 1000) }

    init(
        id: UUID = UUID(),
        channel: ChatChannel,
        sender: ChatSender,
        text: String,
        time: Int64 = Int64(Date().timeIntervalSince1970 * 1000),
        replyTo: UUID? = nil,
        hop: Int = 0,
        delivery: Delivery = .sent
    ) {
        self.id = id
        self.channel = channel
        self.sender = sender
        self.text = text
        self.time = time
        self.replyTo = replyTo
        self.hop = hop
        self.delivery = delivery
    }

    private enum CodingKeys: String, CodingKey {
        case id, channel, sender, text, time, replyTo, hop, delivery
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let rawID = try c.decode(String.self, forKey: .id)
        guard let uuid = UUID(uuidString: rawID) else {
            throw DecodingError.dataCorruptedError(
                forKey: .id, in: c, debugDescription: "id is not a UUID: \(rawID)")
        }
        id = uuid
        channel = try c.decode(ChatChannel.self, forKey: .channel)
        sender = try c.decode(ChatSender.self, forKey: .sender)
        text = try c.decode(String.self, forKey: .text)
        time = try c.decodeIfPresent(Int64.self, forKey: .time) ?? 0
        replyTo = (try c.decodeIfPresent(String.self, forKey: .replyTo)).flatMap(UUID.init(uuidString:))
        hop = try c.decodeIfPresent(Int.self, forKey: .hop) ?? 0
        // Anything the server hands us has, by definition, been delivered.
        delivery = try c.decodeIfPresent(Delivery.self, forKey: .delivery) ?? .sent
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id.uuidString.lowercased(), forKey: .id)
        try c.encode(channel, forKey: .channel)
        try c.encode(sender, forKey: .sender)
        try c.encode(text, forKey: .text)
        try c.encode(time, forKey: .time)
        try c.encodeIfPresent(replyTo?.uuidString.lowercased(), forKey: .replyTo)
        try c.encode(hop, forKey: .hop)
        try c.encode(delivery, forKey: .delivery)
    }
}

// MARK: - Wire frames

/// What the client sends. `sender` is omitted: the relay rejects any client
/// claiming to be an AI, so there is nothing useful to put here.
struct OutboundMessage: Codable, Sendable {
    var type = "message"
    let id: UUID
    let channel: ChatChannel
    let text: String

    private enum CodingKeys: String, CodingKey { case type, id, channel, text }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(type, forKey: .type)
        try c.encode(id.uuidString.lowercased(), forKey: .id)
        try c.encode(channel, forKey: .channel)
        try c.encode(text, forKey: .text)
    }
}

/// The four server → client events, as one decodable enum.
enum ServerEvent: Sendable {
    /// `cursor` addresses the page before this one, or nil at the beginning of
    /// history — which is what lets a reconnecting client keep paging.
    case history(channel: ChatChannel, messages: [ChatMessage], cursor: String?)
    case ack(channel: ChatChannel, id: UUID, time: Int64)
    case delta(channel: ChatChannel, message: ChatMessage)
    case status(channel: ChatChannel, agent: ChatSender, state: AgentState, detail: String?)
    case failure(code: String, message: String)

    enum AgentState: String, Codable, Sendable {
        case thinking, idle, error
    }
}

extension ServerEvent: Decodable {
    private enum CodingKeys: String, CodingKey {
        case type, channel, messages, id, time, message, agent, state, detail, code, cursor
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let type = try c.decode(String.self, forKey: .type)

        switch type {
        case "history":
            self = .history(
                channel: try c.decode(ChatChannel.self, forKey: .channel),
                messages: try c.decode([ChatMessage].self, forKey: .messages),
                cursor: try c.decodeIfPresent(String.self, forKey: .cursor))

        case "ack":
            let raw = try c.decode(String.self, forKey: .id)
            guard let uuid = UUID(uuidString: raw) else {
                throw DecodingError.dataCorruptedError(
                    forKey: .id, in: c, debugDescription: "ack id is not a UUID")
            }
            self = .ack(
                channel: try c.decode(ChatChannel.self, forKey: .channel),
                id: uuid,
                time: try c.decode(Int64.self, forKey: .time))

        case "delta":
            self = .delta(
                channel: try c.decode(ChatChannel.self, forKey: .channel),
                message: try c.decode(ChatMessage.self, forKey: .message))

        case "status":
            self = .status(
                channel: try c.decode(ChatChannel.self, forKey: .channel),
                agent: try c.decode(ChatSender.self, forKey: .agent),
                state: try c.decode(AgentState.self, forKey: .state),
                detail: try c.decodeIfPresent(String.self, forKey: .detail))

        case "error":
            self = .failure(
                code: try c.decode(String.self, forKey: .code),
                message: try c.decodeIfPresent(String.self, forKey: .message) ?? "")

        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type, in: c, debugDescription: "unknown event: \(type)")
        }
    }
}
