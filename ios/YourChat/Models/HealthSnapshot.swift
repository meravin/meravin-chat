import Foundation

/// Mirrors exactly what the relay stores after sanitising an upload. Adding a
/// field here means adding it in `relay/api/health.mjs` too, or it is dropped.
struct HealthPayload: Codable, Equatable, Sendable {
    struct HeartRate: Codable, Equatable, Sendable {
        var current: Int?
        var min: Int?
        var max: Int?
        /// Sampled beats for the sparkline, oldest first.
        var series: [Double]?
    }

    struct SleepStage: Codable, Equatable, Sendable {
        var stage: String
        var minutes: Double
    }

    struct Sleep: Codable, Equatable, Sendable {
        var minutes: Int?
        /// ISO-8601 instants, so the card can print "12:07 PM – 4:09 PM".
        var start: String?
        var end: String?
        var stages: [SleepStage]?

        var hours: Int { (minutes ?? 0) / 60 }
        var remainder: Int { (minutes ?? 0) % 60 }
    }

    struct Cycle: Codable, Equatable, Sendable {
        var day: Int?
        var length: Int?
        /// `YYYY-MM-DD` of the next expected period.
        var nextExpected: String?
    }

    struct Body: Codable, Equatable, Sendable {
        var oxygen: Double?
        var hrv: Double?
        var temperature: Double?
        var weightKg: Double?
    }

    var steps: Int?
    var distanceKm: Double?
    /// Seven bars, Monday-first, for the Steps card.
    var stepsByWeekday: [Double]?
    var heartRate: HeartRate?
    var sleep: Sleep?
    var cycle: Cycle?
    var body: Body?

    var isEmpty: Bool {
        steps == nil && heartRate == nil && sleep == nil && cycle == nil && body == nil
    }
}

struct HealthSnapshot: Codable, Equatable, Sendable {
    let date: String
    let payload: HealthPayload
    let syncedAt: Int64
}
