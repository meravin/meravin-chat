import SwiftUI

/// One channel's transcript. The send button only ever picks a channel — there
/// is no per-channel networking code, just `chat.send(text, to: channel)`.
struct ConversationView: View {
    @Environment(AppModel.self) private var model
    @Environment(ThemeStore.self) private var theme
    @Environment(ChatService.self) private var chat

    let channel: ChatChannel

    @State private var draft = ""
    @FocusState private var inputFocused: Bool

    var body: some View {
        ZStack {
            SkinBackground()

            VStack(spacing: 0) {
                transcript
                statusLine
                composer
            }
        }
        .navigationTitle(model.profile.title(for: channel))
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
        .onAppear { draft = chat.drafts[channel] ?? "" }
        .onDisappear { chat.drafts[channel] = draft.isEmpty ? nil : draft }
    }

    private var messages: [ChatMessage] { chat.messages(in: channel) }

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: theme.chatStyle == .bubble ? 10 : 16) {
                    topOfHistory

                    ForEach(messages) { message in
                        MessageRow(message: message, channel: channel)
                            .id(message.id)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }
            .scrollIndicators(.hidden)
            .defaultScrollAnchor(.bottom)
            // Driven by scroll position rather than the sentinel's `onAppear`,
            // which fires once and then stalls because the spinner never leaves
            // the screen. Observing the offset itself — not a `Bool` — matters
            // for the same reason: a Bool only reports transitions, so sitting
            // at the top after one page would never ask for the next.
            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                geometry.contentOffset.y - geometry.contentInsets.top
            } action: { _, distanceFromTop in
                guard distanceFromTop < 120 else { return }
                Task { await loadOlder(proxy: proxy) }
            }
            // Keyed on the last message rather than the count: appending changes
            // it and should follow the conversation down, while prepending an
            // older page leaves it alone and must not yank the view.
            .onChange(of: messages.last?.id) { _, newest in
                guard let newest else { return }
                withAnimation(.smooth) { proxy.scrollTo(newest, anchor: .bottom) }
            }
        }
    }

    private func loadOlder(proxy: ScrollViewProxy) async {
        // Pin the current top so the prepended page grows upward instead of
        // shoving the reader down the transcript.
        let anchor = messages.first?.id
        await chat.loadOlder(in: channel)
        if let anchor, messages.first?.id != anchor {
            proxy.scrollTo(anchor, anchor: .top)
        }
    }

    /// Status line above the first message — purely an indicator; the fetch is
    /// triggered by scroll position.
    @ViewBuilder
    private var topOfHistory: some View {
        if messages.isEmpty {
            EmptyView()
        } else if chat.hasMoreHistory[channel] == false {
            Text("没有更早的了")
                .font(.system(size: 11))
                .foregroundStyle(theme.secondaryOnBackground)
                .padding(.bottom, 6)
        } else {
            ProgressView()
                .controlSize(.small)
                .padding(.bottom, 6)
        }
    }

    /// Either an AI is composing, or one failed — never an endless spinner.
    @ViewBuilder
    private var statusLine: some View {
        if let error = chat.errorDetail(in: channel) {
            label(error, tint: Color(hex: 0xD05353), icon: "exclamationmark.triangle")
        } else if chat.isThinking(in: channel) {
            label("正在输入…", tint: theme.secondaryOnBackground, icon: nil)
        } else if case .offline(let reason) = chat.connection {
            label(reason.map { "离线：\($0)" } ?? "离线，正在重连…",
                  tint: theme.secondaryOnBackground, icon: "wifi.slash")
        }
    }

    private func label(_ text: String, tint: Color, icon: String?) -> some View {
        HStack(spacing: 5) {
            if let icon { Image(systemName: icon).font(.system(size: 10)) }
            Text(text).font(.system(size: 11))
            Spacer()
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 20)
        .padding(.bottom, 6)
        .transition(.opacity)
    }

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 10) {
            // Only the group routes on mentions, so only the group offers one.
            if channel == .group {
                Menu {
                    ForEach([ChatSender.aiA, .aiB], id: \.self) { agent in
                        Button(model.profile.displayName(for: agent)) { mention(agent) }
                    }
                } label: {
                    Text("@")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(theme.accent)
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(theme.cardColor.opacity(theme.cardOpacity)))
                }
            }

            TextField("说点什么…", text: $draft, axis: .vertical)
                .lineLimit(1...5)
                .font(.system(size: 15))
                .foregroundStyle(theme.onBackground)
                .focused($inputFocused)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(theme.cardColor.opacity(theme.cardOpacity)))

            Button(action: send) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(canSend ? theme.accent : theme.secondaryOnBackground))
            }
            .buttonStyle(.plain)
            .disabled(!canSend)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
    }

    private var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func send() {
        chat.send(draft, to: channel)
        draft = ""
    }

    /// Inserts "@Name " — the relay only forwards a group message to the other
    /// AI when it carries an explicit mention like this.
    private func mention(_ agent: ChatSender) {
        let handle = "@\(model.profile.displayName(for: agent)) "
        if draft.isEmpty {
            draft = handle
        } else if draft.hasSuffix(" ") {
            draft += handle
        } else {
            draft += " \(handle)"
        }
        inputFocused = true
    }
}

/// One message, in whichever style Settings selected.
struct MessageRow: View {
    @Environment(AppModel.self) private var model
    @Environment(ThemeStore.self) private var theme

    let message: ChatMessage
    let channel: ChatChannel

    private var isMine: Bool { message.sender == .user }
    /// The group shows who is speaking; a private chat doesn't need the label.
    private var showsName: Bool { channel == .group && !isMine }

    var body: some View {
        switch theme.chatStyle {
        case .bubble: bubble
        case .plain: plain
        }
    }

    private var bubble: some View {
        HStack(alignment: .top, spacing: 8) {
            if isMine { Spacer(minLength: 40) } else { avatar }

            VStack(alignment: isMine ? .trailing : .leading, spacing: 3) {
                if showsName {
                    Text(model.profile.displayName(for: message.sender))
                        .font(.system(size: 11))
                        .foregroundStyle(theme.secondaryOnBackground)
                }

                Text(message.text)
                    .font(.system(size: 15))
                    .foregroundStyle(isMine ? .white : theme.onBackground)
                    .padding(.horizontal, 13)
                    .padding(.vertical, 9)
                    .background(
                        RoundedRectangle(cornerRadius: 17, style: .continuous)
                            .fill(isMine ? theme.accent : theme.cardColor.opacity(theme.cardOpacity)))

                if isMine, message.delivery == .sending {
                    Text("发送中")
                        .font(.system(size: 10))
                        .foregroundStyle(theme.secondaryOnBackground)
                }
            }

            if isMine { avatar } else { Spacer(minLength: 40) }
        }
    }

    private var plain: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(isMine
                     ? (model.profile.userName.isEmpty ? "我" : model.profile.userName)
                     : model.profile.displayName(for: message.sender))
                    .font(.display(12, weight: .medium))
                    .foregroundStyle(isMine ? theme.accent : theme.onBackground)

                if isMine, message.delivery == .sending {
                    Text("发送中").font(.system(size: 10)).foregroundStyle(theme.secondaryOnBackground)
                }
            }

            Text(message.text)
                .font(.system(size: 15))
                .foregroundStyle(theme.onBackground)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var avatar: some View {
        AvatarView(
            sender: message.sender,
            size: 30,
            name: model.profile.displayName(for: message.sender))
    }
}
