import Foundation

extension String {
    /// The space Chinese typography wants between Latin text and a Han
    /// character, and does not want between two Han characters.
    var cjkGap: String {
        guard let last = unicodeScalars.last else { return "" }
        let han = (0x3400...0x9FFF).contains(Int(last.value))
            || (0xF900...0xFAFF).contains(Int(last.value))
        return han ? "" : " "
    }
}

/// One `GET /api/home` fills the entire Home tab, so the screen never renders
/// half-populated while three separate requests land.
struct HomePayload: Codable, Equatable, Sendable {
    struct Weather: Codable, Equatable, Sendable {
        var summary: String
        var code: Int
        var temp: Int
        var low: Int
        var high: Int
        var precipProbability: Int?
        /// "带伞" / "路滑" — nil when nothing is worth mentioning.
        var advice: String?

        /// "阴 27° 28~34° · 降雨 76%，带伞"
        var line: String {
            var parts = ["\(summary) \(temp)°", "\(low)~\(high)°"]
            if let p = precipProbability { parts.append("降雨 \(p)%") }
            var text = parts.joined(separator: " ")
            if let advice { text += "，\(advice)" }
            return text
        }
    }

    struct Whisper: Codable, Equatable, Sendable {
        var date: String
        var text: String
        var author: String
        var createdAt: Int64
    }

    struct Us: Codable, Equatable, Sendable {
        var day: Int?
        /// `YYYY-MM-DD` the relationship started.
        var since: String
        var partner: String
        var userName: String

        /// "敏敏和 Claude，从 2026.6.22 到每一天" — and "Leon 和 Claude…" when
        /// the name is Latin, which needs the space that a CJK name does not.
        var caption: String {
            let pretty = since.split(separator: "-").enumerated()
                .map { $0.offset == 0 ? String($0.element) : String(Int($0.element) ?? 0) }
                .joined(separator: ".")
            return "\(userName)\(userName.cjkGap)和 \(partner)，从 \(pretty) 到每一天"
        }
    }

    struct Countdown: Codable, Equatable, Sendable {
        var date: String
        var daysUntil: Int
    }

    struct Anniversary: Codable, Equatable, Identifiable, Sendable {
        var key: String
        var label: String
        var date: String
        var daysUntil: Int

        var id: String { key }

        /// "Jan 6" — the small caption under the label.
        var shortDate: String {
            guard let parsed = DateOnly.parse(date) else { return date }
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.dateFormat = "MMM d"
            return f.string(from: parsed)
        }
    }

    var date: String
    /// "Sunday, July 26"
    var headerDate: String
    /// "Good evening"
    var greeting: String
    var userName: String
    var weather: Weather?
    var whisper: Whisper?
    var us: Us?
    var monthly: Countdown?
    var anniversaries: [Anniversary]
    var health: HealthPayload?
    /// Milliseconds; drives the "sync · 11:57 PM" stamp in the header.
    var syncedAt: Int64?

    static let placeholder = HomePayload(
        date: DateOnly.today,
        headerDate: "",
        greeting: "Hello",
        userName: "",
        anniversaries: [])
}

/// Names and dates live on the relay so nothing personal is compiled into the app.
struct Profile: Codable, Equatable, Sendable {
    var userName: String = ""
    var aiAName: String = "Claude"
    var aiBName: String = "Codex"
    var groupName: String = "我们仨"
    var togetherSince: String = ""
    var birthday: String = ""
    var anniversary: String = ""
    /// Written in script on the launch screen. Empty falls back to `userName`.
    var signature: String = ""
    /// The line under the dedication. Blank by default and hidden when blank —
    /// that sentence belongs to whoever owns the app, not to a default.
    var epigraph: String = ""

    /// What the launch screen signs.
    var signatureText: String {
        let name = signature.isEmpty ? userName : signature
        return name.isEmpty ? "you" : name
    }

    func displayName(for sender: ChatSender) -> String {
        switch sender {
        case .user: userName
        case .aiA: aiAName
        case .aiB: aiBName
        }
    }

    func title(for channel: ChatChannel) -> String {
        switch channel {
        case .aiA: aiAName
        case .aiB: aiBName
        case .group: groupName
        }
    }
}
