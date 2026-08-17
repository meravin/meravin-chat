import Foundation
import HealthKit
import Observation

/// Reads the day's HealthKit numbers and uploads a snapshot to the relay.
/// That upload is what the "sync · 11:57 PM" stamp on Home reports, and it is
/// how both AIs get to know how the day actually went.
///
/// Every read is individually optional: one denied type must not empty the
/// whole card stack.
@MainActor
@Observable
final class HealthService {
    enum Availability: Equatable, Sendable {
        case unknown
        case unavailable
        case denied
        case ready
    }

    private(set) var availability: Availability = .unknown
    private(set) var snapshot: HealthPayload?
    private(set) var lastSync: Date?
    private(set) var lastError: String?

    private let store = HKHealthStore()
    private let api: APIClient

    init(api: APIClient) {
        self.api = api
    }

    // MARK: - Types

    private var readTypes: Set<HKObjectType> {
        var types: Set<HKObjectType> = [
            HKQuantityType(.stepCount),
            HKQuantityType(.distanceWalkingRunning),
            HKQuantityType(.heartRate),
            HKQuantityType(.heartRateVariabilitySDNN),
            HKQuantityType(.oxygenSaturation),
            HKQuantityType(.bodyMass),
            HKQuantityType(.bodyTemperature),
            HKCategoryType(.sleepAnalysis),
        ]
        types.insert(HKCategoryType(.menstrualFlow))
        return types
    }

    /// Only one write: the "今天来了" button logs a period start.
    private var shareTypes: Set<HKSampleType> { [HKCategoryType(.menstrualFlow)] }

    // MARK: - Authorization

    func requestAuthorization() async {
        guard HKHealthStore.isHealthDataAvailable() else {
            availability = .unavailable
            return
        }
        do {
            try await store.requestAuthorization(toShare: shareTypes, read: readTypes)
            availability = .ready
        } catch {
            availability = .denied
            lastError = error.localizedDescription
        }
    }

    // MARK: - Read + upload

    /// Reads today's numbers and pushes them to the relay. Safe to call on
    /// every foreground — it is cheap and idempotent (keyed by date).
    @discardableResult
    func syncToday() async -> HealthPayload? {
        guard HKHealthStore.isHealthDataAvailable() else {
            availability = .unavailable
            return nil
        }

        let payload = await readToday()
        snapshot = payload
        guard !payload.isEmpty else { return payload }

        do {
            let saved = try await api.uploadHealth(date: DateOnly.today, payload: payload)
            lastSync = Date(timeIntervalSince1970: TimeInterval(saved.syncedAt) / 1000)
            lastError = nil
        } catch {
            // Home still renders from what we read locally.
            lastError = error.localizedDescription
        }
        return payload
    }

    private func readToday() async -> HealthPayload {
        var payload = HealthPayload()
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: Date())
        let today = HKQuery.predicateForSamples(withStart: startOfDay, end: Date())

        payload.steps = (await sum(.stepCount, unit: .count(), predicate: today)).map { Int($0) }
        payload.distanceKm = await sum(.distanceWalkingRunning, unit: .meterUnit(with: .kilo), predicate: today)
        payload.stepsByWeekday = await weeklySteps(calendar: calendar)
        payload.heartRate = await heartRate(predicate: today)
        payload.sleep = await sleep(calendar: calendar)
        payload.cycle = await cycle(calendar: calendar)
        payload.body = await body(predicate: today)
        return payload
    }

    // MARK: - Individual reads

    private func sum(
        _ identifier: HKQuantityTypeIdentifier, unit: HKUnit, predicate: NSPredicate
    ) async -> Double? {
        let descriptor = HKStatisticsQueryDescriptor(
            predicate: .quantitySample(type: HKQuantityType(identifier), predicate: predicate),
            options: .cumulativeSum)
        guard let result = try? await descriptor.result(for: store),
              let quantity = result.sumQuantity()
        else { return nil }
        return quantity.doubleValue(for: unit)
    }

    private func mostRecent(
        _ identifier: HKQuantityTypeIdentifier, unit: HKUnit, predicate: NSPredicate
    ) async -> Double? {
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: HKQuantityType(identifier), predicate: predicate)],
            sortDescriptors: [SortDescriptor(\.endDate, order: .reverse)],
            limit: 1)
        guard let samples = try? await descriptor.result(for: store), let sample = samples.first
        else { return nil }
        return sample.quantity.doubleValue(for: unit)
    }

    /// Seven bars for the Steps card, oldest day first.
    private func weeklySteps(calendar: Calendar) async -> [Double]? {
        let end = calendar.startOfDay(for: Date())
        guard let start = calendar.date(byAdding: .day, value: -6, to: end) else { return nil }

        let descriptor = HKStatisticsCollectionQueryDescriptor(
            predicate: .quantitySample(
                type: HKQuantityType(.stepCount),
                predicate: HKQuery.predicateForSamples(withStart: start, end: Date())),
            options: .cumulativeSum,
            anchorDate: start,
            intervalComponents: DateComponents(day: 1))

        guard let collection = try? await descriptor.result(for: store) else { return nil }

        var values: [Double] = []
        collection.enumerateStatistics(from: start, to: Date()) { statistics, _ in
            values.append(statistics.sumQuantity()?.doubleValue(for: .count()) ?? 0)
        }
        return values.isEmpty ? nil : values
    }

    private func heartRate(predicate: NSPredicate) async -> HealthPayload.HeartRate? {
        let unit = HKUnit.count().unitDivided(by: .minute())
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: HKQuantityType(.heartRate), predicate: predicate)],
            sortDescriptors: [SortDescriptor(\.startDate)])

        guard let samples = try? await descriptor.result(for: store), !samples.isEmpty else { return nil }
        let values = samples.map { $0.quantity.doubleValue(for: unit) }

        return HealthPayload.HeartRate(
            current: values.last.map { Int($0.rounded()) },
            min: values.min().map { Int($0.rounded()) },
            max: values.max().map { Int($0.rounded()) },
            // Thin the series: the sparkline only needs shape, not every beat.
            series: stride(from: 0, to: values.count, by: max(1, values.count / 120)).map { values[$0] })
    }

    private func sleep(calendar: Calendar) async -> HealthPayload.Sleep? {
        // Last night's window: noon yesterday through now catches naps too.
        guard let start = calendar.date(byAdding: .hour, value: -24, to: Date()) else { return nil }
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.categorySample(
                type: HKCategoryType(.sleepAnalysis),
                predicate: HKQuery.predicateForSamples(withStart: start, end: Date()))],
            sortDescriptors: [SortDescriptor(\.startDate)])

        guard let samples = try? await descriptor.result(for: store), !samples.isEmpty else { return nil }

        let asleep = samples.filter {
            HKCategoryValueSleepAnalysis(rawValue: $0.value).map(HKCategoryValueSleepAnalysis.allAsleepValues.contains) ?? false
        }
        guard !asleep.isEmpty else { return nil }

        let minutes = asleep.reduce(0.0) { $0 + $1.endDate.timeIntervalSince($1.startDate) } / 60
        let iso = ISO8601DateFormatter()

        var stages: [HealthPayload.SleepStage] = []
        for sample in asleep {
            let label = HKCategoryValueSleepAnalysis(rawValue: sample.value)?.stageLabel ?? "asleep"
            let length = sample.endDate.timeIntervalSince(sample.startDate) / 60
            if let index = stages.firstIndex(where: { $0.stage == label }) {
                stages[index].minutes += length
            } else {
                stages.append(HealthPayload.SleepStage(stage: label, minutes: length))
            }
        }

        return HealthPayload.Sleep(
            minutes: Int(minutes.rounded()),
            start: asleep.first.map { iso.string(from: $0.startDate) },
            end: asleep.last.map { iso.string(from: $0.endDate) },
            stages: stages)
    }

    private func cycle(calendar: Calendar) async -> HealthPayload.Cycle? {
        guard let start = calendar.date(byAdding: .day, value: -120, to: Date()) else { return nil }
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.categorySample(
                type: HKCategoryType(.menstrualFlow),
                predicate: HKQuery.predicateForSamples(withStart: start, end: Date()))],
            sortDescriptors: [SortDescriptor(\.startDate, order: .reverse)])

        guard let samples = try? await descriptor.result(for: store), !samples.isEmpty else { return nil }

        // Prefer an explicit cycle-start marker; otherwise fall back to the
        // oldest sample in the most recent run of consecutive days.
        let starts = samples.filter { $0.metadata?[HKMetadataKeyMenstrualCycleStart] as? Bool == true }
        guard let latestStart = starts.first ?? samples.last else { return nil }

        let day = calendar.dateComponents(
            [.day], from: calendar.startOfDay(for: latestStart.startDate),
            to: calendar.startOfDay(for: Date())).day.map { $0 + 1 }

        // Average observed cycle length, defaulting to 28 until there's data.
        var length = 28
        if starts.count >= 2 {
            let gaps = zip(starts, starts.dropFirst()).compactMap {
                calendar.dateComponents([.day], from: $1.startDate, to: $0.startDate).day
            }.filter { $0 > 10 && $0 < 60 }
            if !gaps.isEmpty { length = gaps.reduce(0, +) / gaps.count }
        }

        let next = calendar.date(byAdding: .day, value: length, to: latestStart.startDate)
        return HealthPayload.Cycle(
            day: day,
            length: length,
            nextExpected: next.map(DateOnly.string(from:)))
    }

    private func body(predicate: NSPredicate) async -> HealthPayload.Body? {
        let recent = HKQuery.predicateForSamples(
            withStart: Calendar.current.date(byAdding: .day, value: -30, to: Date()), end: Date())

        let oxygen = await mostRecent(.oxygenSaturation, unit: .percent(), predicate: predicate)
        let hrv = await mostRecent(.heartRateVariabilitySDNN, unit: .secondUnit(with: .milli), predicate: predicate)
        let temperature = await mostRecent(.bodyTemperature, unit: .degreeCelsius(), predicate: recent)
        let weight = await mostRecent(.bodyMass, unit: .gramUnit(with: .kilo), predicate: recent)

        let body = HealthPayload.Body(
            oxygen: oxygen.map { ($0 * 100).rounded() },
            hrv: hrv.map { $0.rounded() },
            temperature: temperature.map { ($0 * 10).rounded() / 10 },
            weightKg: weight.map { ($0 * 10).rounded() / 10 })

        let isEmpty = body.oxygen == nil && body.hrv == nil && body.temperature == nil && body.weightKg == nil
        return isEmpty ? nil : body
    }

    // MARK: - Write

    /// The "今天来了" button on the Cycle card.
    func logPeriodStart() async {
        let sample = HKCategorySample(
            type: HKCategoryType(.menstrualFlow),
            value: HKCategoryValueVaginalBleeding.light.rawValue,
            start: Date(),
            end: Date(),
            metadata: [HKMetadataKeyMenstrualCycleStart: true])
        do {
            try await store.save(sample)
            await syncToday()
        } catch {
            lastError = error.localizedDescription
        }
    }
}

private extension HKCategoryValueSleepAnalysis {
    var stageLabel: String {
        switch self {
        case .asleepREM: "rem"
        case .asleepDeep: "deep"
        case .asleepCore: "core"
        case .awake: "awake"
        default: "asleep"
        }
    }
}
