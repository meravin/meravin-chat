import SwiftUI

/// Three tabs — Home, Chats, Diary — over the skin background, behind the
/// one-time drag gate on the launch screen.
struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(ThemeStore.self) private var theme

    @State private var tab: Tab = .home
    @State private var showSettings = false

    enum Tab: String, CaseIterable, Identifiable {
        case home = "Home"
        case chats = "Chats"
        case diary = "Diary"

        var id: String { rawValue }
    }

    var body: some View {
        ZStack {
            SkinBackground()

            if model.hasEnteredApp {
                content.transition(.opacity)
            } else {
                LaunchGateView()
                    .transition(.opacity)
            }
        }
        .animation(.smooth(duration: 0.6), value: model.hasEnteredApp)
        .sheet(isPresented: $showSettings) { SettingsView() }
    }

    private var content: some View {
        VStack(spacing: 0) {
            Group {
                switch tab {
                case .home: HomeView(showSettings: $showSettings)
                case .chats: ChatListView()
                case .diary: DiaryView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            tabBar
        }
    }

    private var tabBar: some View {
        HStack {
            ForEach(Tab.allCases) { item in
                Button {
                    withAnimation(.smooth(duration: 0.25)) { tab = item }
                } label: {
                    Text(item.rawValue)
                        .font(.display(17, weight: tab == item ? .semibold : .regular))
                        .foregroundStyle(tab == item ? theme.onBackground : theme.secondaryOnBackground)
                        .frame(maxWidth: .infinity)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, 12)
        .padding(.bottom, 4)
        .background(.ultraThinMaterial)
    }
}
