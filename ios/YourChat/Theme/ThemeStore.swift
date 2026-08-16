import SwiftUI
import Observation

/// Everything the Settings sheet controls. Each skin remembers its own accent
/// and card colour ("每款皮肤各记各的"), so switching back restores what you
/// had rather than resetting to the default.
@MainActor
@Observable
final class ThemeStore {
    enum ChatStyle: String, CaseIterable, Identifiable, Sendable {
        case plain
        case bubble

        var id: String { rawValue }
        var label: String { self == .plain ? "简约" : "气泡" }
        var note: String {
            self == .plain
                ? "简约：只显示正文，接近纸上的对话。"
                : "气泡：每条消息带头像，双方都在气泡里，像聊天软件。"
        }
    }

    enum Appearance: String, CaseIterable, Identifiable, Sendable {
        case system
        case light
        case dark

        var id: String { rawValue }
        var label: String {
            switch self {
            case .system: "跟随系统"
            case .light: "浅色"
            case .dark: "夜间"
            }
        }
        var colorScheme: ColorScheme? {
            switch self {
            case .system: nil
            case .light: .light
            case .dark: .dark
            }
        }
    }

    private enum Keys {
        static let skin = "theme.skin"
        static let accents = "theme.accents"
        static let cards = "theme.cards"
        static let opacity = "theme.cardOpacity"
        static let chatStyle = "theme.chatStyle"
        static let appearance = "theme.appearance"
        static let avatars = "theme.avatars"
    }

    static let defaultCardOpacity = 0.85

    private let defaults: UserDefaults

    private(set) var skinID: String {
        didSet { defaults.set(skinID, forKey: Keys.skin) }
    }
    /// skin id → "#RRGGBB"
    private var accents: [String: String] {
        didSet { defaults.set(accents, forKey: Keys.accents) }
    }
    private var cards: [String: String] {
        didSet { defaults.set(cards, forKey: Keys.cards) }
    }
    var cardOpacity: Double {
        didSet { defaults.set(cardOpacity, forKey: Keys.opacity) }
    }
    var chatStyle: ChatStyle {
        didSet { defaults.set(chatStyle.rawValue, forKey: Keys.chatStyle) }
    }
    var appearance: Appearance {
        didSet { defaults.set(appearance.rawValue, forKey: Keys.appearance) }
    }
    /// sender raw value → PNG data, set from the photo picker.
    private var avatars: [String: Data] {
        didSet { defaults.set(avatars, forKey: Keys.avatars) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        skinID = defaults.string(forKey: Keys.skin) ?? Skin.inkWhite.id
        accents = defaults.dictionary(forKey: Keys.accents) as? [String: String] ?? [:]
        cards = defaults.dictionary(forKey: Keys.cards) as? [String: String] ?? [:]
        cardOpacity = defaults.object(forKey: Keys.opacity) as? Double ?? Self.defaultCardOpacity
        chatStyle = ChatStyle(rawValue: defaults.string(forKey: Keys.chatStyle) ?? "") ?? .bubble
        appearance = Appearance(rawValue: defaults.string(forKey: Keys.appearance) ?? "") ?? .system
        avatars = defaults.dictionary(forKey: Keys.avatars) as? [String: Data] ?? [:]
    }

    // MARK: - Derived

    var skin: Skin { Skin.named(skinID) }

    func select(_ skin: Skin) {
        withAnimation(.smooth(duration: 0.45)) { skinID = skin.id }
    }

    var accent: Color {
        get { accents[skinID].flatMap(Color.init(hexString:)) ?? skin.defaultAccent }
        set { accents[skinID] = newValue.hexString }
    }

    var cardColor: Color {
        get { cards[skinID].flatMap(Color.init(hexString:)) ?? skin.defaultCard }
        set { cards[skinID] = newValue.hexString }
    }

    /// Only the paper skins follow the Appearance control — the glass skins
    /// carry their own light/dark character, exactly as the Settings note says.
    var preferredColorScheme: ColorScheme? {
        skin.isGlass ? nil : appearance.colorScheme
    }

    /// Text and icon colour that stays legible on the current background.
    var onBackground: Color {
        skin.prefersDarkContent ? Color(hex: 0x14130F) : .white
    }

    var secondaryOnBackground: Color {
        onBackground.opacity(0.55)
    }

    func resetAccent() { accents[skinID] = nil }
    func resetCard() { cards[skinID] = nil }
    func resetOpacity() { cardOpacity = Self.defaultCardOpacity }

    // MARK: - Avatars

    func avatar(for sender: ChatSender) -> Image? {
        #if canImport(UIKit)
        guard let data = avatars[sender.rawValue], let ui = UIImage(data: data) else { return nil }
        return Image(uiImage: ui)
        #else
        return nil
        #endif
    }

    func setAvatar(_ data: Data?, for sender: ChatSender) {
        avatars[sender.rawValue] = data
    }

    func hasCustomAvatar(for sender: ChatSender) -> Bool { avatars[sender.rawValue] != nil }
}
