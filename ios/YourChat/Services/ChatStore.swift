import Foundation

/// Disk persistence for the two files that matter more than bubble styling:
///
/// - `chat-cache.json` — history stays readable with no network.
/// - `outbox.json`     — messages the server has not acked yet. Without it,
///   locking the screen or switching networks mid-send produces a bubble that
///   looks delivered but never reached the relay.
///
/// An actor so writes never block a scroll.
actor ChatStore {
    private let directory: URL
    private let cacheURL: URL
    private let outboxURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(directory: URL? = nil) {
        let base = directory ?? FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("YourChat", isDirectory: true)
        self.directory = base
        cacheURL = base.appendingPathComponent("chat-cache.json")
        outboxURL = base.appendingPathComponent("outbox.json")
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
    }

    // MARK: - history cache

    func loadCache() -> [ChatChannel: [ChatMessage]] {
        guard let data = try? Data(contentsOf: cacheURL),
              let raw = try? decoder.decode([String: [ChatMessage]].self, from: data)
        else { return [:] }

        var out: [ChatChannel: [ChatMessage]] = [:]
        for (key, value) in raw {
            if let channel = ChatChannel(rawValue: key) { out[channel] = value }
        }
        return out
    }

    func saveCache(_ messages: [ChatChannel: [ChatMessage]]) {
        // Cap what we keep on disk: the relay holds the full history and pages
        // it back on demand, so a local file never needs to grow without bound.
        var raw: [String: [ChatMessage]] = [:]
        for (channel, list) in messages {
            raw[channel.rawValue] = Array(list.suffix(200))
        }
        guard let data = try? encoder.encode(raw) else { return }
        try? data.write(to: cacheURL, options: .atomic)
    }

    // MARK: - outbox

    func loadOutbox() -> [ChatMessage] {
        guard let data = try? Data(contentsOf: outboxURL),
              let list = try? decoder.decode([ChatMessage].self, from: data)
        else { return [] }
        return list
    }

    func saveOutbox(_ messages: [ChatMessage]) {
        guard let data = try? encoder.encode(messages) else { return }
        try? data.write(to: outboxURL, options: .atomic)
    }
}
