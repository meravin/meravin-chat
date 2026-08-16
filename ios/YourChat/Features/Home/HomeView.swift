import SwiftUI

/// The relationship dashboard: greeting and weather, the AI's note for the day,
/// how long you've been counting, what's coming up, and today's body numbers.
struct HomeView: View {
    @Environment(AppModel.self) private var model
    @Environment(ThemeStore.self) private var theme
    @Environment(HealthService.self) private var health

    @Binding var showSettings: Bool
    @State private var showWhisperDetail = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header

                if let whisper = model.home.whisper {
                    WhisperCard(whisper: whisper) { showWhisperDetail = true }
                }

                if let us = model.home.us {
                    UsDayCard(us: us)
                }

                if let monthly = model.home.monthly {
                    AnniversaryCard(monthly: monthly, items: model.home.anniversaries)
                }

                healthGrid
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .refreshable {
            await model.refreshHome()
            await model.syncHealth()
        }
        .task {
            // First run asks for HealthKit, then keeps the cards current.
            await model.syncHealth()
        }
        .sheet(isPresented: $showWhisperDetail) {
            WhisperDetailView(whisper: model.home.whisper)
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center) {
                Text(model.home.headerDate)
                    .font(.display(15))
                    .foregroundStyle(theme.secondaryOnBackground)

                Spacer()

                syncStamp

                Button { showSettings = true } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 15))
                        .foregroundStyle(theme.secondaryOnBackground)
                        .frame(width: 32, height: 32)
                        .background(Circle().fill(theme.cardColor.opacity(theme.cardOpacity * 0.7)))
                }
                .buttonStyle(.plain)
            }

            Text("\(model.home.greeting), \(model.home.userName)")
                .font(.display(30, weight: .semibold))
                .foregroundStyle(theme.onBackground)

            if let weather = model.home.weather {
                Text(weather.line)
                    .font(.system(size: 13))
                    .foregroundStyle(theme.secondaryOnBackground)
            }
        }
        .padding(.top, 12)
    }

    private var syncStamp: some View {
        Group {
            if let syncedAt = model.home.syncedAt {
                Text("sync · \(Self.clock.string(from: Date(timeIntervalSince1970: TimeInterval(syncedAt) / 1000)))")
            } else if health.availability == .denied {
                Text("健康未授权")
            } else {
                Text("未同步")
            }
        }
        .font(.system(size: 11))
        .foregroundStyle(theme.secondaryOnBackground)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Capsule().fill(theme.cardColor.opacity(theme.cardOpacity * 0.7)))
    }

    private static let clock: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "h:mm a"
        return f
    }()

    // MARK: - Health

    private var metrics: HealthPayload? { model.home.health ?? health.snapshot }

    @ViewBuilder
    private var healthGrid: some View {
        if let metrics, !metrics.isEmpty {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible())], spacing: 14) {
                if metrics.steps != nil { StepsCard(metrics: metrics) }
                if metrics.heartRate != nil { HeartRateCard(rate: metrics.heartRate!) }
                if metrics.sleep != nil { SleepCard(sleep: metrics.sleep!) }
                if metrics.cycle != nil { CycleCard(cycle: metrics.cycle!) }
            }

            if let body = metrics.body {
                BodyCard(body: body)
            }
        } else {
            HealthEmptyCard()
        }
    }
}
