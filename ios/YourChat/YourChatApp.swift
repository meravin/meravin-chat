import SwiftUI

@main
struct YourChatApp: App {
    @State private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .environment(model.theme)
                .environment(model.chat)
                .environment(model.health)
                .preferredColorScheme(model.theme.preferredColorScheme)
                .task { await model.start() }
        }
        .onChange(of: scenePhase) { _, phase in
            // Coming back from the lock screen must reconnect and re-pull, or
            // the outbox sits full while the UI looks online.
            if phase == .active { Task { await model.enterForeground() } }
        }
    }
}

/// Wires the services together and owns the shared, screen-agnostic state
/// (profile, Home payload) so no view has to know how to build a client.
@MainActor
@Observable
final class AppModel {
    let config: RelayConfig
    let api: APIClient
    let chat: ChatService
    let theme: ThemeStore
    let health: HealthService

    private(set) var profile = Profile()
    private(set) var home = HomePayload.placeholder
    private(set) var isLoadingHome = false
    private(set) var homeError: String?
    /// The launch screen's drag gate is dismissed once, per launch.
    var hasEnteredApp = false

    init() {
        let config = RelayConfig()
        let api = APIClient(config: config)
        self.config = config
        self.api = api
        chat = ChatService(config: config, api: api)
        theme = ThemeStore()
        health = HealthService(api: api)
    }

    func start() async {
        await chat.start()
        await refreshProfile()
        await refreshHome()
    }

    func enterForeground() async {
        chat.refresh()
        await refreshHome()
    }

    func refreshProfile() async {
        profile = (try? await api.profile()) ?? profile
    }

    func refreshHome() async {
        isLoadingHome = true
        defer { isLoadingHome = false }
        do {
            home = try await api.home()
            homeError = nil
        } catch {
            homeError = error.localizedDescription
        }
    }

    /// Asks for HealthKit access, reads today, uploads, then re-pulls Home so
    /// the cards and the sync stamp update together.
    func syncHealth() async {
        if health.availability == .unknown { await health.requestAuthorization() }
        await health.syncToday()
        await refreshHome()
    }

    func save(_ updated: Profile) async {
        profile = (try? await api.updateProfile(updated)) ?? updated
        await refreshHome()
    }
}
