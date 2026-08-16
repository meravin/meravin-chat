import Foundation

/// The Diary tab shows two diaries side by side, switched by the segmented
/// control at the top: the user's own, and the AI's.
enum DiaryAuthor: String, Codable, CaseIterable, Identifiable, Sendable {
    case user
    case aiA = "ai_a"

    var id: String { rawValue }
}

struct DiaryEntry: Identifiable, Codable, Equatable, Sendable {
    let id: String
    let author: DiaryAuthor
    /// Calendar day as `YYYY-MM-DD` — the key the month grid's dots group by.
    var date: String
    var mood: String?
    var body: String
    var createdAt: Int64
    var updatedAt: Int64

    var day: Date? { DateOnly.parse(date) }
}

struct TodoItem: Identifiable, Codable, Equatable, Sendable {
    enum State: String, Codable, Sendable {
        case pending
        case done
    }

    let id: String
    let owner: DiaryAuthor
    var title: String
    /// Where it came from — "23:49 添加" for a quick add, "7月25日记的" when
    /// lifted out of a diary entry.
    var source: String?
    var state: State
    /// Set by the long-press "设为日程" action.
    var dueAt: Int64?
    var createdAt: Int64
    var completedAt: Int64?

    var isDone: Bool { state == .done }
    var isScheduled: Bool { dueAt != nil }
}

/// `YYYY-MM-DD` conversions, done once so every screen agrees on what "today" is.
enum DateOnly {
    static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static func string(from date: Date) -> String { formatter.string(from: date) }
    static func parse(_ string: String) -> Date? { formatter.date(from: string) }
    static var today: String { string(from: Date()) }

    /// `YYYY-MM`, used to ask the relay for a month's worth of calendar dots.
    static func month(from date: Date) -> String { String(string(from: date).prefix(7)) }
}
