import SwiftUI

/// One field over both archives: what was said, and what was written down.
struct SearchView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppModel.self) private var model
    @Environment(ThemeStore.self) private var theme

    /// Set when a chat result is tapped, so the caller can open that channel.
    var onOpenChannel: (ChatChannel) -> Void = { _ in }

    @State private var query = ""
    @State private var results: APIClient.SearchResults?
    @State private var isSearching = false
    @FocusState private var focused: Bool

    var body: some View {
        ZStack {
            SkinBackground()

            VStack(spacing: 14) {
                field

                if isSearching {
                    ProgressView().controlSize(.small).padding(.top, 30)
                } else if let results {
                    if results.isEmpty {
                        Text("没有找到「\(results.query)」")
                            .font(.system(size: 13))
                            .foregroundStyle(theme.secondaryOnBackground)
                            .padding(.top, 30)
                    } else {
                        list(results)
                    }
                } else {
                    Text("搜聊天记录和日记")
                        .font(.system(size: 13))
                        .foregroundStyle(theme.secondaryOnBackground)
                        .padding(.top, 30)
                }

                Spacer()
            }
            .padding(.horizontal, 18)
            .padding(.top, 16)
        }
        .onAppear { focused = true }
    }

    private var field: some View {
        HStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 13))
                    .foregroundStyle(theme.secondaryOnBackground)

                TextField("搜索", text: $query)
                    .font(.system(size: 15))
                    .foregroundStyle(theme.onBackground)
                    .focused($focused)
                    .submitLabel(.search)
                    .autocorrectionDisabled()
                    .onSubmit { Task { await run() } }

                if !query.isEmpty {
                    Button {
                        query = ""
                        results = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(theme.secondaryOnBackground)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(theme.cardColor.opacity(theme.cardOpacity)))

            Button("完成") { dismiss() }
                .font(.system(size: 15))
                .foregroundStyle(theme.onBackground)
        }
    }

    private func list(_ results: APIClient.SearchResults) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if !results.messages.isEmpty {
                    section("聊天 (\(results.messages.count))") {
                        ForEach(results.messages) { hit in
                            Button {
                                onOpenChannel(hit.channel)
                                dismiss()
                            } label: {
                                messageRow(hit)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                if !results.diary.isEmpty {
                    section("日记 (\(results.diary.count))") {
                        ForEach(results.diary) { hit in
                            diaryRow(hit)
                        }
                    }
                }
            }
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
    }

    private func section<Content: View>(
        _ title: String, @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(theme.secondaryOnBackground)
            VStack(spacing: 0) { content() }.card(padding: 4)
        }
    }

    private func messageRow(_ hit: APIClient.SearchResults.Message) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(model.profile.title(for: hit.channel))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(theme.accent)
                Text(model.profile.displayName(for: hit.sender))
                    .font(.system(size: 11))
                    .foregroundStyle(theme.secondaryOnBackground)
                Spacer()
                Text(Self.day.string(from: Date(timeIntervalSince1970: TimeInterval(hit.time) / 1000)))
                    .font(.system(size: 11))
                    .foregroundStyle(theme.secondaryOnBackground)
            }
            Text(hit.text)
                .font(.system(size: 14))
                .foregroundStyle(theme.onBackground)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .contentShape(.rect)
    }

    private func diaryRow(_ hit: APIClient.SearchResults.Entry) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(hit.author == .user
                     ? (model.profile.userName.isEmpty ? "我" : model.profile.userName)
                     : model.profile.aiAName)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(theme.accent)
                if let mood = hit.mood, !mood.isEmpty {
                    Text(mood).font(.system(size: 11)).foregroundStyle(theme.secondaryOnBackground)
                }
                Spacer()
                Text(hit.date).font(.system(size: 11)).foregroundStyle(theme.secondaryOnBackground)
            }
            Text(hit.excerpt)
                .font(.system(size: 14))
                .foregroundStyle(theme.onBackground)
                .lineLimit(3)
                .multilineTextAlignment(.leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private func run() async {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        isSearching = true
        defer { isSearching = false }
        results = try? await model.api.search(text)
    }

    private static let day: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "MMM d"
        return f
    }()
}
