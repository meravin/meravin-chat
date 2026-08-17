import SwiftUI
import PhotosUI

/// Skins, colours, chat style, appearance, avatars — plus the profile and relay
/// fields, so nothing personal has to be compiled into the app.
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppModel.self) private var model
    @Environment(ThemeStore.self) private var themeStore

    /// The helper sections live outside `body`, so they can't see a local
    /// `@Bindable`; this hands each one the same bindable wrapper.
    private var bindable: Bindable<ThemeStore> { Bindable(themeStore) }

    var body: some View {
        ZStack {
            SkinBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    skinSection(theme: bindable)
                    chatStyleSection(theme: bindable)
                    appearanceSection(theme: bindable)
                    AvatarSection()
                    ProfileSection()
                    RelaySection()
                    DataSection()
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 30)
            }
            .scrollIndicators(.hidden)
        }
    }

    private var header: some View {
        HStack {
            Text("Settings")
                .font(.display(28, weight: .semibold))
                .foregroundStyle(themeStore.onBackground)
            Spacer()
            Button("完成") { dismiss() }
                .font(.system(size: 15))
                .foregroundStyle(themeStore.onBackground)
        }
        .padding(.top, 14)
    }

    // MARK: - Skin

    private func skinSection(theme: Bindable<ThemeStore>) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            label("皮肤")

            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 14) {
                ForEach(Skin.all) { skin in
                    Button { themeStore.select(skin) } label: {
                        VStack(spacing: 5) {
                            ZStack {
                                Circle().fill(skin.swatch)
                                Circle().strokeBorder(themeStore.onBackground.opacity(0.18))
                                if themeStore.skinID == skin.id {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(skin.prefersDarkContent ? .black : .white)
                                }
                            }
                            .frame(width: 46, height: 46)

                            Text(skin.name)
                                .font(.system(size: 10))
                                .foregroundStyle(themeStore.secondaryOnBackground)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }

            Divider().overlay(themeStore.onBackground.opacity(0.1))

            colorRow(
                title: "调色板",
                note: "改的是「\(themeStore.skin.name)」的点缀色，每款皮肤各记各的",
                color: theme.accent) { themeStore.resetAccent() }

            colorRow(
                title: "卡片颜色",
                note: "卡片的底色，跟壁纸搭配着调",
                color: theme.cardColor) { themeStore.resetCard() }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("卡片透明度")
                        .font(.system(size: 15))
                        .foregroundStyle(themeStore.onBackground)
                    Spacer()
                    Text("\(Int(themeStore.cardOpacity * 100))%")
                        .font(.system(size: 13))
                        .foregroundStyle(themeStore.secondaryOnBackground)
                    Button("恢复默认") { themeStore.resetOpacity() }
                        .font(.system(size: 12))
                        .foregroundStyle(themeStore.accent)
                }
                Slider(value: theme.cardOpacity, in: 0.2...1)
                    .tint(themeStore.accent)
            }
        }
        .card()
    }

    private func colorRow(
        title: String, note: String, color: Binding<Color>, reset: @escaping () -> Void
    ) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 15)).foregroundStyle(themeStore.onBackground)
                Text(note).font(.system(size: 11)).foregroundStyle(themeStore.secondaryOnBackground)
            }
            Spacer()
            Button("恢复", action: reset)
                .font(.system(size: 12))
                .foregroundStyle(themeStore.accent)
            ColorPicker("", selection: color, supportsOpacity: false)
                .labelsHidden()
        }
    }

    // MARK: - Chat style & appearance

    private func chatStyleSection(theme: Bindable<ThemeStore>) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            label("聊天样式")
            segmented(options: ThemeStore.ChatStyle.allCases,
                      selection: theme.chatStyle) { $0.label }
            Text(themeStore.chatStyle.note)
                .font(.system(size: 11))
                .foregroundStyle(themeStore.secondaryOnBackground)
        }
        .card()
    }

    private func appearanceSection(theme: Bindable<ThemeStore>) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            label("外观")
            segmented(options: ThemeStore.Appearance.allCases,
                      selection: theme.appearance) { $0.label }
            Text("玻璃皮肤自带昼夜气质，这里只对纸张类皮肤生效")
                .font(.system(size: 11))
                .foregroundStyle(themeStore.secondaryOnBackground)
        }
        .card()
    }

    private func segmented<T: Hashable & Identifiable>(
        options: [T], selection: Binding<T>, title: @escaping (T) -> String
    ) -> some View {
        HStack(spacing: 0) {
            ForEach(options) { option in
                let isOn = selection.wrappedValue == option
                Button {
                    withAnimation(.smooth(duration: 0.2)) { selection.wrappedValue = option }
                } label: {
                    Text(title(option))
                        .font(.system(size: 14, weight: isOn ? .semibold : .regular))
                        .foregroundStyle(isOn ? .white : themeStore.onBackground)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(isOn
                            ? AnyShapeStyle(Color(hex: 0x1A1A1A))
                            : AnyShapeStyle(Color.clear)))
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Capsule().fill(themeStore.onBackground.opacity(0.06)))
    }

    private func label(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(themeStore.secondaryOnBackground)
    }
}

// MARK: - Avatars

private struct AvatarSection: View {
    @Environment(AppModel.self) private var model
    @Environment(ThemeStore.self) private var theme

    @State private var picking: ChatSender?
    @State private var selection: PhotosPickerItem?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("头像")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(theme.secondaryOnBackground)

            ForEach([ChatSender.user, .aiA, .aiB], id: \.self) { sender in
                HStack(spacing: 12) {
                    AvatarView(sender: sender, size: 34,
                               name: model.profile.displayName(for: sender))
                    Text(model.profile.displayName(for: sender))
                        .font(.system(size: 15))
                        .foregroundStyle(theme.onBackground)
                    Spacer()
                    if theme.hasCustomAvatar(for: sender) {
                        Button("恢复默认") { theme.setAvatar(nil, for: sender) }
                            .font(.system(size: 12))
                            .foregroundStyle(theme.secondaryOnBackground)
                    }
                    Button("换一张") { picking = sender }
                        .font(.system(size: 12))
                        .foregroundStyle(theme.accent)
                }
            }
        }
        .card()
        .photosPicker(isPresented: .init(get: { picking != nil },
                                         set: { if !$0 { picking = nil } }),
                      selection: $selection, matching: .images)
        .onChange(of: selection) { _, item in
            guard let item, let sender = picking else { return }
            Task {
                let data = try? await item.loadTransferable(type: Data.self)
                theme.setAvatar(data, for: sender)
                picking = nil
                selection = nil
            }
        }
    }
}

// MARK: - Profile

private struct ProfileSection: View {
    @Environment(AppModel.self) private var model
    @Environment(ThemeStore.self) private var theme

    @State private var draft = Profile()
    @State private var loaded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("我们")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(theme.secondaryOnBackground)

            field("你的名字", text: $draft.userName)
            field("AI A 的名字", text: $draft.aiAName)
            field("AI B 的名字", text: $draft.aiBName)
            field("群聊名字", text: $draft.groupName)
            field("在一起的第一天", text: $draft.togetherSince, hint: "2026-06-22")
            field("生日", text: $draft.birthday, hint: "01-06")
            field("纪念日", text: $draft.anniversary, hint: "06-22")

            Divider().overlay(theme.onBackground.opacity(0.1)).padding(.vertical, 2)

            field("启动页签名", text: $draft.signature, hint: draft.userName)
            field("扉页那句", text: $draft.epigraph, hint: "留空就不显示")

            Button("保存") {
                Task { await model.save(draft) }
            }
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(theme.accent)
            .padding(.top, 4)
        }
        .card()
        .task {
            guard !loaded else { return }
            loaded = true
            draft = model.profile
        }
    }

    private func field(_ title: String, text: Binding<String>, hint: String = "") -> some View {
        HStack {
            Text(title)
                .font(.system(size: 14))
                .foregroundStyle(theme.onBackground)
                .frame(width: 108, alignment: .leading)
            TextField(hint, text: text)
                .font(.system(size: 14))
                .foregroundStyle(theme.onBackground)
                .multilineTextAlignment(.trailing)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
        }
    }
}

// MARK: - Data

/// Your archive is yours: take it out, or delete it. The relay writes a safety
/// backup before erasing, so a mistaken tap is still recoverable on the Mac.
private struct DataSection: View {
    @Environment(AppModel.self) private var model
    @Environment(ThemeStore.self) private var theme

    @State private var exported: URL?
    @State private var isExporting = false
    @State private var confirmingErase = false
    @State private var isErasing = false
    @State private var note: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("数据")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(theme.secondaryOnBackground)

            HStack {
                Text("导出全部")
                    .font(.system(size: 15))
                    .foregroundStyle(theme.onBackground)
                Spacer()
                if isExporting {
                    ProgressView().controlSize(.small)
                } else if let exported {
                    ShareLink(item: exported) {
                        Text("分享").font(.system(size: 13)).foregroundStyle(theme.accent)
                    }
                } else {
                    Button("生成") { export() }
                        .font(.system(size: 13))
                        .foregroundStyle(theme.accent)
                }
            }

            Text("聊天、日记、待办、健康快照，一个 JSON 文件。")
                .font(.system(size: 11))
                .foregroundStyle(theme.secondaryOnBackground)

            Divider().overlay(theme.onBackground.opacity(0.1))

            HStack {
                Text("清除全部数据")
                    .font(.system(size: 15))
                    .foregroundStyle(theme.onBackground)
                Spacer()
                if isErasing {
                    ProgressView().controlSize(.small)
                } else {
                    Button("清除") { confirmingErase = true }
                        .font(.system(size: 13))
                        .foregroundStyle(Color(hex: 0xD05353))
                }
            }

            if let note {
                Text(note)
                    .font(.system(size: 11))
                    .foregroundStyle(theme.secondaryOnBackground)
            }
        }
        .card()
        .confirmationDialog(
            "清除全部聊天、日记、待办和健康记录？",
            isPresented: $confirmingErase,
            titleVisibility: .visible
        ) {
            Button("清除全部", role: .destructive) { erase() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("消息桥会先在 data/backups/ 存一份备份，名字和你的名字无关。")
        }
    }

    private func export() {
        isExporting = true
        Task {
            exported = try? await model.api.exportBundle()
            note = exported == nil ? "导出失败，检查消息桥连接。" : nil
            isExporting = false
        }
    }

    private func erase() {
        isErasing = true
        Task {
            do {
                let counts = try await model.api.eraseEverything()
                let total = counts.values.reduce(0, +)
                note = "已清除 \(total) 条记录，备份留在消息桥上。"
                exported = nil
                await model.start()
            } catch {
                note = "清除失败：\(error.localizedDescription)"
            }
            isErasing = false
        }
    }
}

// MARK: - Relay

private struct RelaySection: View {
    @Environment(AppModel.self) private var model
    @Environment(ThemeStore.self) private var theme
    @Environment(ChatService.self) private var chat

    var body: some View {
        @Bindable var config = model.config

        VStack(alignment: .leading, spacing: 10) {
            Text("消息桥")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(theme.secondaryOnBackground)

            HStack {
                Text("地址").font(.system(size: 14)).foregroundStyle(theme.onBackground)
                TextField("127.0.0.1:9191", text: $config.host)
                    .font(.system(size: 14, design: .monospaced))
                    .foregroundStyle(theme.onBackground)
                    .multilineTextAlignment(.trailing)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
            }

            Toggle("使用 HTTPS / WSS", isOn: $config.useTLS)
                .font(.system(size: 14))
                .foregroundStyle(theme.onBackground)
                .tint(theme.accent)

            HStack {
                Text("令牌").font(.system(size: 14)).foregroundStyle(theme.onBackground)
                SecureField("YOURCHAT_TOKEN", text: $config.token)
                    .font(.system(size: 14, design: .monospaced))
                    .foregroundStyle(theme.onBackground)
                    .multilineTextAlignment(.trailing)
            }

            Text("令牌存在钥匙串里，不会写进代码或备份到 iCloud。真机和正式版必须用 wss://。")
                .font(.system(size: 11))
                .foregroundStyle(theme.secondaryOnBackground)

            HStack {
                Circle()
                    .fill(chat.connection.isOnline ? Color(hex: 0x3BA55D) : Color(hex: 0xB0B0B0))
                    .frame(width: 6, height: 6)
                Text(chat.connection.label)
                    .font(.system(size: 12))
                    .foregroundStyle(theme.secondaryOnBackground)
                if chat.unsentCount > 0 {
                    Text("· \(chat.unsentCount) 条待发")
                        .font(.system(size: 12))
                        .foregroundStyle(theme.secondaryOnBackground)
                }
                Spacer()
                Button("重新连接") {
                    chat.disconnect()
                    chat.connect()
                }
                .font(.system(size: 13))
                .foregroundStyle(theme.accent)
            }
            .padding(.top, 2)
        }
        .card()
    }
}
