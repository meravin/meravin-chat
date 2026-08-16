import SwiftUI

/// Three conversations — the two private chats and the group — over one
/// WebSocket. The dot in the corner is the connection, not a per-chat state.
struct ChatListView: View {
    @Environment(AppModel.self) private var model
    @Environment(ThemeStore.self) private var theme
    @Environment(ChatService.self) private var chat

    @State private var open: ChatChannel?
    @State private var searching = false

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                header

                VStack(spacing: 0) {
                    ForEach(Array(ChatChannel.allCases.enumerated()), id: \.element) { index, channel in
                        if index > 0 {
                            Divider().overlay(theme.onBackground.opacity(0.08)).padding(.leading, 62)
                        }
                        row(channel)
                    }
                }
                .card(padding: 0)

                Spacer()
            }
            .padding(.horizontal, 18)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            // The skin already paints the page behind the tabs, and this screen
            // draws its own "Chats" header — an empty nav bar on top of that
            // just bleeds a second title under the Dynamic Island.
            .background(Color.clear)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(item: $open) { ConversationView(channel: $0) }
        }
        .tint(theme.accent)
        .sheet(isPresented: $searching) {
            SearchView { channel in open = channel }
        }
    }

    private var header: some View {
        HStack {
            Text("Chats")
                .font(.display(30, weight: .semibold))
                .foregroundStyle(theme.onBackground)
            Spacer()
            HStack(spacing: 5) {
                Circle()
                    .fill(chat.connection.isOnline ? Color(hex: 0x3BA55D) : Color(hex: 0xB0B0B0))
                    .frame(width: 6, height: 6)
                Text(chat.connection.label)
                    .font(.system(size: 12))
                    .foregroundStyle(theme.secondaryOnBackground)
            }

            Button { searching = true } label: {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(theme.onBackground)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(theme.cardColor.opacity(theme.cardOpacity)))
            }
            .buttonStyle(.plain)
            .padding(.leading, 4)
        }
        .padding(.top, 12)
    }

    private func row(_ channel: ChatChannel) -> some View {
        Button {
            open = channel
        } label: {
            HStack(spacing: 12) {
                AvatarView(
                    sender: channel == .aiB ? .aiB : .aiA,
                    size: 44,
                    name: model.profile.title(for: channel),
                    isGroup: channel == .group)

                VStack(alignment: .leading, spacing: 3) {
                    Text(model.profile.title(for: channel))
                        .font(.display(16, weight: .medium))
                        .foregroundStyle(theme.onBackground)

                    preview(channel)
                        .font(.system(size: 13))
                        .lineLimit(1)
                }

                Spacer(minLength: 6)

                VStack(alignment: .trailing, spacing: 6) {
                    if let last = chat.lastMessage(in: channel) {
                        Text(Self.clock.string(from: last.date))
                            .font(.system(size: 11))
                            .foregroundStyle(theme.secondaryOnBackground)
                    }
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(theme.secondaryOnBackground.opacity(0.7))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    /// An unsent draft takes priority over the last message, matching the
    /// 草稿 marker on the reference screen.
    @ViewBuilder
    private func preview(_ channel: ChatChannel) -> some View {
        if let draft = chat.drafts[channel], !draft.isEmpty {
            HStack(spacing: 4) {
                Text("草稿").foregroundStyle(Color(hex: 0xD05353))
                Text(draft).foregroundStyle(theme.secondaryOnBackground)
            }
        } else if let last = chat.lastMessage(in: channel) {
            let prefix = channel == .group && last.sender.isAgent
                ? "\(model.profile.displayName(for: last.sender)): "
                : ""
            Text(prefix + last.text).foregroundStyle(theme.secondaryOnBackground)
        } else {
            Text("还没有消息").foregroundStyle(theme.secondaryOnBackground.opacity(0.7))
        }
    }

    private static let clock: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "h:mm a"
        return f
    }()
}
