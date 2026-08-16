import SwiftUI

// MARK: - Today's Whisper

/// The dark card at the top: a short private note the AI wrote about the day.
struct WhisperCard: View {
    @Environment(AppModel.self) private var model

    let whisper: HomePayload.Whisper
    var onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(alignment: .top, spacing: 12) {
                AvatarView(sender: .aiA, size: 34, name: model.profile.aiAName)

                VStack(alignment: .leading, spacing: 10) {
                    Text(whisper.text)
                        .font(.system(size: 15))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 4) {
                        Text("Today's Whisper")
                            .font(.display(12))
                        Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold))
                    }
                    .foregroundStyle(.white.opacity(0.55))
                }

                Spacer(minLength: 0)
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color(hex: 0x1A1A1A)))
        }
        .buttonStyle(.plain)
    }
}

struct WhisperDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppModel.self) private var model
    @Environment(ThemeStore.self) private var theme

    let whisper: HomePayload.Whisper?
    @State private var isRefreshing = false

    var body: some View {
        ZStack {
            SkinBackground()

            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Text("Today's Whisper").font(.display(22, weight: .semibold))
                    Spacer()
                    Button("完成") { dismiss() }.font(.system(size: 15))
                }
                .foregroundStyle(theme.onBackground)

                Text(whisper?.text ?? "今天还没有。")
                    .font(.system(size: 17))
                    .foregroundStyle(theme.onBackground)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .card()

                Button {
                    Task {
                        isRefreshing = true
                        _ = try? await model.api.refreshWhisper()
                        await model.refreshHome()
                        isRefreshing = false
                    }
                } label: {
                    Label(isRefreshing ? "重新写…" : "换一条", systemImage: "arrow.clockwise")
                        .font(.system(size: 14))
                        .foregroundStyle(theme.accent)
                }
                .disabled(isRefreshing)

                Spacer()
            }
            .padding(22)
        }
    }
}

// MARK: - Us

/// "Day 35" — how long you've been counting.
struct UsDayCard: View {
    @Environment(ThemeStore.self) private var theme
    let us: HomePayload.Us

    @State private var beat = false

    var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Us")
                    .font(.display(13))
                    .foregroundStyle(theme.secondaryOnBackground)
                Text("Day \(us.day ?? 0)")
                    .font(.display(40, weight: .medium))
                    .foregroundStyle(theme.onBackground)
                Text(us.caption)
                    .font(.system(size: 12))
                    .foregroundStyle(theme.secondaryOnBackground)
            }

            Spacer()

            Image(systemName: "heart.fill")
                .font(.system(size: 30))
                .foregroundStyle(theme.accent.opacity(0.25))
                .scaleEffect(beat ? 1.08 : 1)
                .animation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true), value: beat)
                .onAppear { beat = true }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }
}

// MARK: - Anniversaries

/// The monthly ring plus the longer countdowns underneath it.
struct AnniversaryCard: View {
    @Environment(ThemeStore.self) private var theme

    let monthly: HomePayload.Countdown
    let items: [HomePayload.Anniversary]

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Monthly Anniversary")
                        .font(.display(19, weight: .medium))
                        .foregroundStyle(theme.onBackground)
                    Text(shortDate)
                        .font(.system(size: 12))
                        .foregroundStyle(theme.secondaryOnBackground)
                }
                Spacer()
                CountdownRing(daysUntil: monthly.daysUntil, span: 31)
            }

            if !items.isEmpty {
                HStack(spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        if index > 0 {
                            Rectangle()
                                .fill(theme.onBackground.opacity(0.12))
                                .frame(width: 1, height: 34)
                        }
                        countdownRow(item)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .card()
    }

    private var shortDate: String {
        guard let parsed = DateOnly.parse(monthly.date) else { return monthly.date }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "MMM d"
        return f.string(from: parsed)
    }

    private func countdownRow(_ item: HomePayload.Anniversary) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text(item.label)
                    .font(.system(size: 13))
                    .foregroundStyle(theme.onBackground)
                    .lineLimit(2)
                Text(item.shortDate)
                    .font(.system(size: 11))
                    .foregroundStyle(theme.secondaryOnBackground)
            }
            Spacer(minLength: 6)
            Text("\(item.daysUntil)")
                .font(.display(19, weight: .medium))
                .foregroundStyle(theme.onBackground)
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity)
    }
}

struct CountdownRing: View {
    @Environment(ThemeStore.self) private var theme

    let daysUntil: Int
    let span: Int
    /// Set explicitly by each card — a fixed inner frame would ignore any
    /// `.frame()` the caller applies and overlap its neighbours.
    var size: CGFloat = 54

    var body: some View {
        ZStack {
            Circle()
                .stroke(theme.onBackground.opacity(0.12), lineWidth: 3)
            Circle()
                .trim(from: 0, to: max(0.02, 1 - Double(daysUntil) / Double(span)))
                .stroke(theme.accent, style: .init(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(daysUntil)")
                .font(.display(size * 0.31, weight: .medium))
                .foregroundStyle(theme.onBackground)
        }
        .frame(width: size, height: size)
        .animation(.smooth, value: daysUntil)
    }
}

// MARK: - Health cards

struct StepsCard: View {
    @Environment(ThemeStore.self) private var theme
    let metrics: HealthPayload

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Steps").font(.display(14)).foregroundStyle(theme.onBackground)
                Spacer()
                if let km = metrics.distanceKm {
                    Text(String(format: "%.2f km", km))
                        .font(.system(size: 11))
                        .foregroundStyle(theme.secondaryOnBackground)
                }
            }

            Text("\(metrics.steps ?? 0)")
                .font(.display(30, weight: .medium))
                .foregroundStyle(theme.onBackground)

            WeekBars(values: metrics.stepsByWeekday ?? [])
                .frame(height: 34)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(padding: 14)
    }
}

private struct WeekBars: View {
    @Environment(ThemeStore.self) private var theme
    let values: [Double]

    private static let labels = ["M", "T", "W", "T", "F", "S", "S"]

    var body: some View {
        let peak = max(values.max() ?? 1, 1)
        HStack(alignment: .bottom, spacing: 5) {
            ForEach(0..<7, id: \.self) { index in
                let value = index < values.count ? values[index] : 0
                let isToday = index == values.count - 1
                VStack(spacing: 3) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(theme.onBackground.opacity(isToday ? 0.75 : 0.28))
                        .frame(height: max(2, 26 * value / peak))
                    Text(Self.labels[index])
                        .font(.system(size: 7))
                        .foregroundStyle(theme.secondaryOnBackground)
                }
                .frame(maxWidth: .infinity, alignment: .bottom)
            }
        }
    }
}

struct HeartRateCard: View {
    @Environment(ThemeStore.self) private var theme
    let rate: HealthPayload.HeartRate

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Heart Rate").font(.display(14)).foregroundStyle(theme.onBackground)

            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text("\(rate.current ?? 0)")
                    .font(.display(30, weight: .medium))
                Text("bpm").font(.system(size: 11))
            }
            .foregroundStyle(theme.onBackground)

            Sparkline(values: rate.series ?? [])
                .stroke(Color(hex: 0xE06C6C), style: .init(lineWidth: 1.4, lineJoin: .round))
                .frame(height: 26)

            if let low = rate.min, let high = rate.max {
                Text("\(low) — \(high) today")
                    .font(.system(size: 10))
                    .foregroundStyle(theme.secondaryOnBackground)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(padding: 14)
    }
}

private struct Sparkline: Shape {
    let values: [Double]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard values.count > 1 else { return path }
        let low = values.min() ?? 0
        let high = values.max() ?? 1
        let span = max(high - low, 1)

        for (index, value) in values.enumerated() {
            let x = rect.width * Double(index) / Double(values.count - 1)
            let y = rect.height * (1 - (value - low) / span)
            index == 0 ? path.move(to: CGPoint(x: x, y: y)) : path.addLine(to: CGPoint(x: x, y: y))
        }
        return path
    }
}

struct SleepCard: View {
    @Environment(ThemeStore.self) private var theme
    let sleep: HealthPayload.Sleep

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Sleep").font(.display(14)).foregroundStyle(theme.onBackground)

            HStack(alignment: .firstTextBaseline, spacing: 1) {
                Text("\(sleep.hours)h").font(.display(30, weight: .medium))
                Text("\(sleep.remainder)m").font(.system(size: 12))
            }
            .foregroundStyle(theme.onBackground)

            StageBar(stages: sleep.stages ?? [])
                .frame(height: 6)

            if let start = time(sleep.start), let end = time(sleep.end) {
                HStack {
                    Text(start)
                    Spacer()
                    Text(end)
                }
                .font(.system(size: 10))
                .foregroundStyle(theme.secondaryOnBackground)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(padding: 14)
    }

    private func time(_ iso: String?) -> String? {
        guard let iso, let date = ISO8601DateFormatter().date(from: iso) else { return nil }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "h:mm a"
        return f.string(from: date)
    }
}

private struct StageBar: View {
    let stages: [HealthPayload.SleepStage]

    private func tint(_ stage: String) -> Color {
        switch stage {
        case "deep": Color(hex: 0x2E7D6B)
        case "rem": Color(hex: 0x7FB2E5)
        case "awake": Color(hex: 0xE0A05A)
        default: Color(hex: 0xA9CBE8)
        }
    }

    var body: some View {
        GeometryReader { geo in
            let total = max(stages.reduce(0) { $0 + $1.minutes }, 1)
            HStack(spacing: 1) {
                ForEach(Array(stages.enumerated()), id: \.offset) { _, stage in
                    Capsule()
                        .fill(tint(stage.stage))
                        .frame(width: max(2, geo.size.width * stage.minutes / total))
                }
            }
        }
    }
}

/// The one card that writes back to HealthKit, via "今天来了".
struct CycleCard: View {
    @Environment(ThemeStore.self) private var theme
    @Environment(HealthService.self) private var health

    let cycle: HealthPayload.Cycle
    @State private var isLogging = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Cycle").font(.display(14)).foregroundStyle(theme.onBackground)
                Spacer()
                if let next = cycle.nextExpected {
                    Text("~\(shortDate(next))")
                        .font(.system(size: 10))
                        .foregroundStyle(theme.secondaryOnBackground)
                }
            }

            HStack(spacing: 10) {
                CountdownRing(daysUntil: cycle.day ?? 0, span: cycle.length ?? 28, size: 42)
                Text("Day \(cycle.day ?? 0)")
                    .font(.display(19, weight: .medium))
                    .foregroundStyle(theme.onBackground)
                Spacer(minLength: 0)
            }

            Button {
                isLogging = true
                Task {
                    await health.logPeriodStart()
                    isLogging = false
                }
            } label: {
                Text(isLogging ? "记录中…" : "今天来了")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
                    .background(Capsule().fill(Color(hex: 0x1A1A1A)))
            }
            .buttonStyle(.plain)
            .disabled(isLogging)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(padding: 14)
    }

    private func shortDate(_ iso: String) -> String {
        guard let parsed = DateOnly.parse(iso) else { return iso }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "MMM d"
        return f.string(from: parsed)
    }
}

struct BodyCard: View {
    @Environment(ThemeStore.self) private var theme
    let body_: HealthPayload.Body

    init(body: HealthPayload.Body) { body_ = body }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Body").font(.display(14)).foregroundStyle(theme.onBackground)

            HStack(spacing: 0) {
                if let oxygen = body_.oxygen { metric("\(Int(oxygen))%", "血氧") }
                if let hrv = body_.hrv { metric("\(Int(hrv))ms", "HRV") }
                if let temp = body_.temperature { metric(String(format: "%.1f°", temp), "体温") }
                if let weight = body_.weightKg { metric(String(format: "%.1fkg", weight), "体重") }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(padding: 14)
    }

    private func metric(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.display(17, weight: .medium)).foregroundStyle(theme.onBackground)
            Text(label).font(.system(size: 10)).foregroundStyle(theme.secondaryOnBackground)
        }
        .frame(maxWidth: .infinity)
    }
}

struct HealthEmptyCard: View {
    @Environment(ThemeStore.self) private var theme
    @Environment(AppModel.self) private var model
    @Environment(HealthService.self) private var health

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("健康数据").font(.display(15)).foregroundStyle(theme.onBackground)
            Text(message)
                .font(.system(size: 13))
                .foregroundStyle(theme.secondaryOnBackground)
                .fixedSize(horizontal: false, vertical: true)

            Button("连接健康 App") {
                Task { await model.syncHealth() }
            }
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(theme.accent)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private var message: String {
        switch health.availability {
        case .unavailable: "这台设备没有健康数据。"
        case .denied: "还没有授权读取健康数据，去「设置 → 健康 → 数据访问」打开。"
        default: "授权后这里会显示步数、心率、睡眠和生理周期。"
        }
    }
}
