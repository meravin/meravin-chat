import Foundation

/// The request/response half of the relay: Home, diary, todos, health.
/// Chat is pushed, so it lives on the WebSocket instead.
@MainActor
final class APIClient {
    struct APIError: LocalizedError {
        let status: Int
        let code: String
        var errorDescription: String? { "\(code) (\(status))" }
    }

    private let config: RelayConfig
    private let session: URLSession
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    init(config: RelayConfig, session: URLSession = .shared) {
        self.config = config
        self.session = session
    }

    // MARK: - Home & profile

    func home() async throws -> HomePayload {
        try await get("/api/home")
    }

    func profile() async throws -> Profile {
        try await get("/api/profile", unwrap: \Envelope.Profile.profile)
    }

    func updateProfile(_ profile: Profile) async throws -> Profile {
        try await send("PATCH", "/api/profile", body: profile, unwrap: \Envelope.Profile.profile)
    }

    func refreshWhisper() async throws -> HomePayload.Whisper? {
        try await send("POST", "/api/whisper/refresh", body: Empty(), unwrap: \Envelope.Whisper.whisper)
    }

    // MARK: - Messages (the pull side; live chat arrives on the socket)

    struct Page: Sendable {
        let messages: [ChatMessage]
        let hasMore: Bool
    }

    /// `before` is the server time of the oldest message already on screen.
    func messages(in channel: ChatChannel, before: Int64?, limit: Int = 30) async throws -> Page {
        struct Envelope: Decodable {
            let messages: [ChatMessage]
            let hasMore: Bool
        }
        var path = "/api/messages?channel=\(channel.rawValue)&limit=\(limit)"
        if let before { path += "&before=\(before)" }
        let raw: Envelope = try await get(path)
        return Page(messages: raw.messages, hasMore: raw.hasMore)
    }

    // MARK: - Search

    struct SearchResults: Decodable, Sendable {
        struct Message: Decodable, Identifiable, Sendable {
            let id: String
            let channel: ChatChannel
            let sender: ChatSender
            let text: String
            let time: Int64
        }
        struct Entry: Decodable, Identifiable, Sendable {
            let id: String
            let author: DiaryAuthor
            let date: String
            let mood: String?
            let excerpt: String
        }
        let query: String
        let messages: [Message]
        let diary: [Entry]

        var isEmpty: Bool { messages.isEmpty && diary.isEmpty }
    }

    func search(_ query: String) async throws -> SearchResults {
        let escaped = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        return try await get("/api/search?q=\(escaped)")
    }

    // MARK: - Export & erase

    /// Downloads the whole archive and returns a file the share sheet can hand off.
    func exportBundle() async throws -> URL {
        let data = try await request("GET", "/api/export", body: Optional<Empty>.none)
        let name = "yourchat-\(DateOnly.today).json"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        try data.write(to: url, options: .atomic)
        return url
    }

    /// The relay takes its own safety backup before deleting anything.
    @discardableResult
    func eraseEverything() async throws -> [String: Int] {
        struct Payload: Encodable { let confirm = "ERASE" }
        struct Envelope: Decodable { let erased: [String: Int] }
        return try await send("DELETE", "/api/data", body: Payload(), unwrap: \Envelope.erased)
    }

    // MARK: - Diary

    /// Proposes todos from one entry. Creates nothing — the caller confirms.
    func extractTodos(fromDiary id: String) async throws -> (candidates: [String], source: String) {
        struct Envelope: Decodable {
            let candidates: [String]
            let source: String
        }
        let data = try await request("POST", "/api/diary/\(id)/todos", body: Empty())
        let raw = try decoder.decode(Envelope.self, from: data)
        return (raw.candidates, raw.source)
    }

    func diary(author: DiaryAuthor, limit: Int = 60) async throws -> [DiaryEntry] {
        try await get("/api/diary?author=\(author.rawValue)&limit=\(limit)",
                      unwrap: \Envelope.Diary.entries)
    }

    /// `["2026-07-26": 1]` — the dots under the days in the month grid.
    func diaryMarks(author: DiaryAuthor, month: String) async throws -> [String: Int] {
        try await get("/api/diary/marks?author=\(author.rawValue)&month=\(month)",
                      unwrap: \Envelope.Marks.marks)
    }

    func createDiary(author: DiaryAuthor, date: String, mood: String?, body: String) async throws -> DiaryEntry {
        struct Payload: Encodable {
            let author: String, date: String, mood: String?, body: String
        }
        return try await send(
            "POST", "/api/diary",
            body: Payload(author: author.rawValue, date: date, mood: mood, body: body),
            unwrap: \Envelope.DiaryOne.entry)
    }

    func updateDiary(id: String, mood: String?, body: String?) async throws -> DiaryEntry {
        struct Payload: Encodable { let mood: String?, body: String? }
        return try await send("PATCH", "/api/diary/\(id)", body: Payload(mood: mood, body: body),
                              unwrap: \Envelope.DiaryOne.entry)
    }

    func deleteDiary(id: String) async throws {
        _ = try await request("DELETE", "/api/diary/\(id)", body: Optional<Empty>.none)
    }

    // MARK: - Todos

    func todos(owner: DiaryAuthor) async throws -> [TodoItem] {
        try await get("/api/todos?owner=\(owner.rawValue)", unwrap: \Envelope.Todos.items)
    }

    func createTodo(owner: DiaryAuthor, title: String, source: String?) async throws -> TodoItem {
        struct Payload: Encodable { let owner: String, title: String, source: String? }
        return try await send("POST", "/api/todos",
                              body: Payload(owner: owner.rawValue, title: title, source: source),
                              unwrap: \Envelope.TodoOne.item)
    }

    func updateTodo(id: String, state: TodoItem.State? = nil, dueAt: Int64? = nil,
                    clearDue: Bool = false) async throws -> TodoItem {
        struct Payload: Encodable {
            let state: String?
            let dueAt: Int64?
            /// Present-but-null clears the schedule; absent leaves it alone.
            let includeDue: Bool

            enum CodingKeys: String, CodingKey { case state, dueAt }
            func encode(to encoder: Encoder) throws {
                var c = encoder.container(keyedBy: CodingKeys.self)
                try c.encodeIfPresent(state, forKey: .state)
                if includeDue { try c.encode(dueAt, forKey: .dueAt) }
            }
        }
        return try await send(
            "PATCH", "/api/todos/\(id)",
            body: Payload(state: state?.rawValue, dueAt: dueAt, includeDue: dueAt != nil || clearDue),
            unwrap: \Envelope.TodoOne.item)
    }

    func deleteTodo(id: String) async throws {
        _ = try await request("DELETE", "/api/todos/\(id)", body: Optional<Empty>.none)
    }

    // MARK: - Health

    @discardableResult
    func uploadHealth(date: String, payload: HealthPayload) async throws -> HealthSnapshot {
        struct Payload: Encodable { let date: String, payload: HealthPayload }
        return try await send("POST", "/api/health", body: Payload(date: date, payload: payload),
                              unwrap: \Envelope.Health.snapshot)
    }

    // MARK: - Transport

    private struct Empty: Codable {}

    private enum Envelope {
        struct Profile: Decodable { let profile: YourChat.Profile }
        struct Diary: Decodable { let entries: [DiaryEntry] }
        struct DiaryOne: Decodable { let entry: DiaryEntry }
        struct Marks: Decodable { let marks: [String: Int] }
        struct Todos: Decodable { let items: [TodoItem] }
        struct TodoOne: Decodable { let item: TodoItem }
        struct Health: Decodable { let snapshot: HealthSnapshot }
        struct Whisper: Decodable { let whisper: HomePayload.Whisper? }
        struct Failure: Decodable { let error: String }
    }

    private func get<T: Decodable>(_ path: String) async throws -> T {
        let data = try await request("GET", path, body: Optional<Empty>.none)
        return try decoder.decode(T.self, from: data)
    }

    private func get<E: Decodable, T>(_ path: String, unwrap: KeyPath<E, T>) async throws -> T {
        let data = try await request("GET", path, body: Optional<Empty>.none)
        return try decoder.decode(E.self, from: data)[keyPath: unwrap]
    }

    private func send<B: Encodable, E: Decodable, T>(
        _ method: String, _ path: String, body: B, unwrap: KeyPath<E, T>
    ) async throws -> T {
        let data = try await request(method, path, body: body)
        return try decoder.decode(E.self, from: data)[keyPath: unwrap]
    }

    private func request<B: Encodable>(_ method: String, _ path: String, body: B?) async throws -> Data {
        // Built by string: `path` already carries its own query, and
        // appendingPathComponent would percent-escape the `?` and `&`.
        guard let url = URL(string: config.apiBaseURL.absoluteString + path) else {
            throw APIError(status: 0, code: "bad_url")
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        config.authorize(&request)

        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try encoder.encode(body)
        }

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw APIError(status: 0, code: "no_response")
        }
        guard (200..<300).contains(http.statusCode) else {
            let code = (try? decoder.decode(Envelope.Failure.self, from: data).error) ?? "http_error"
            throw APIError(status: http.statusCode, code: code)
        }
        return data
    }
}
