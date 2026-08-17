import SwiftUI

/// The six skins in Settings. Two families:
///
/// - `.paper` lays flat colour behind the cards and honours the Appearance
///   control (the note under it in Settings says as much).
/// - `.glass` puts a soft wallpaper behind translucent cards, which is why it
///   "carries its own day/night feel" and ignores Appearance.
///
/// Backgrounds are generated as mesh gradients rather than shipped photos, so
/// the app has no image assets to license and every skin stays a few bytes.
/// Drop a photo into `Assets.xcassets` and set `wallpaper` to use one instead.
struct Skin: Identifiable, Hashable, Sendable {
    enum Family: String, Sendable {
        case paper
        case glass
    }

    let id: String
    let name: String
    let family: Family
    /// The circle shown in the Settings picker.
    let swatch: Color
    let defaultAccent: Color
    let defaultCard: Color
    /// Nine colours on a 3×3 mesh, read top-left to bottom-right. Nine rather
    /// than four because a 2×2 mesh reads as a flat wash — the extra mid row is
    /// what gives the glass skins their light-through-haze depth.
    let field: [Color]
    /// Name of an image set in the asset catalogue, when you'd rather use a photo.
    let wallpaper: String?
    let prefersDarkContent: Bool

    var isGlass: Bool { family == .glass }

    /// Deliberately off-centre control points: a symmetric grid looks like a
    /// gradient, an asymmetric one looks like light falling across something.
    static let meshPoints: [SIMD2<Float>] = [
        .init(0.0, 0.0), .init(0.55, 0.0), .init(1.0, 0.0),
        .init(0.0, 0.45), .init(0.62, 0.56), .init(1.0, 0.38),
        .init(0.0, 1.0), .init(0.42, 1.0), .init(1.0, 1.0),
    ]

    static let all: [Skin] = [ivoryPaper, moonSand, creamOrange, mistyMountain, mistyBlue, inkWhite]

    static func named(_ id: String) -> Skin { all.first { $0.id == id } ?? inkWhite }

    // MARK: - Paper

    /// Warm paper with a faint fold of shadow down the right.
    static let ivoryPaper = Skin(
        id: "ivory-paper",
        name: "象牙纸张",
        family: .paper,
        swatch: Color(hex: 0xF6EFE4),
        defaultAccent: Color(hex: 0x1C1B19),
        defaultCard: Color(hex: 0xFFFDF8),
        field: [
            Color(hex: 0xFBF6EC), Color(hex: 0xF8F2E6), Color(hex: 0xF3EBDC),
            Color(hex: 0xF7F0E3), Color(hex: 0xF4EDE0), Color(hex: 0xEDE4D3),
            Color(hex: 0xF2EADB), Color(hex: 0xEEE5D4), Color(hex: 0xE7DCC8),
        ],
        wallpaper: nil,
        prefersDarkContent: true)

    /// Late-afternoon light through a curtain: warm at the top, amber at the base.
    static let creamOrange = Skin(
        id: "cream-orange",
        name: "奶油甜橙",
        family: .paper,
        swatch: Color(hex: 0xF6C98A),
        defaultAccent: Color(hex: 0xC2662A),
        defaultCard: Color(hex: 0xFFF9F1),
        field: [
            Color(hex: 0xFEF6EA), Color(hex: 0xFDF0DC), Color(hex: 0xFBE7C9),
            Color(hex: 0xFDEEDA), Color(hex: 0xFAE3C2), Color(hex: 0xF6D5A8),
            Color(hex: 0xF9E0BC), Color(hex: 0xF5D2A2), Color(hex: 0xEFC086),
        ],
        wallpaper: nil,
        prefersDarkContent: true)

    /// Near-neutral, with just enough drift that the page isn't dead flat.
    static let inkWhite = Skin(
        id: "ink-white",
        name: "墨白",
        family: .paper,
        swatch: Color(hex: 0xFFFFFF),
        defaultAccent: Color(hex: 0x111111),
        defaultCard: Color(hex: 0xFFFFFF),
        field: [
            Color(hex: 0xFAFAFA), Color(hex: 0xF7F7F8), Color(hex: 0xF2F3F4),
            Color(hex: 0xF6F6F7), Color(hex: 0xF2F2F4), Color(hex: 0xEBECEE),
            Color(hex: 0xF0F0F2), Color(hex: 0xEAEBED), Color(hex: 0xE2E4E7),
        ],
        wallpaper: nil,
        prefersDarkContent: true)

    // MARK: - Glass

    /// Moonlight on sand: pale rose at the horizon falling to a warm dark base.
    static let moonSand = Skin(
        id: "moon-sand",
        name: "月沙",
        family: .glass,
        swatch: Color(hex: 0xB08B87),
        defaultAccent: Color(hex: 0xF2919F),
        defaultCard: Color(hex: 0x5A3B3E),
        field: [
            Color(hex: 0xF0CFC6), Color(hex: 0xE8BDB6), Color(hex: 0xD9A7A2),
            Color(hex: 0xD3A69C), Color(hex: 0xBC8880), Color(hex: 0x9A6B67),
            Color(hex: 0x7A554F), Color(hex: 0x5F413E), Color(hex: 0x40292A),
        ],
        wallpaper: nil,
        prefersDarkContent: false)

    /// Fog lifting off a treeline — light at the top, deep green in the valley.
    static let mistyMountain = Skin(
        id: "misty-mountain",
        name: "雾山",
        family: .glass,
        swatch: Color(hex: 0x24402C),
        defaultAccent: Color(hex: 0xA8DCAF),
        defaultCard: Color(hex: 0x2C4433),
        field: [
            Color(hex: 0xB6C9AE), Color(hex: 0x93AE8E), Color(hex: 0x6E8C6E),
            Color(hex: 0x7A9A78), Color(hex: 0x53785A), Color(hex: 0x365A40),
            Color(hex: 0x2F4C39), Color(hex: 0x1F3628), Color(hex: 0x142619),
        ],
        wallpaper: nil,
        prefersDarkContent: false)

    /// Cold morning haze. The one glass skin that stays light enough for dark text.
    static let mistyBlue = Skin(
        id: "misty-blue",
        name: "雾蓝",
        family: .glass,
        swatch: Color(hex: 0xC3D7EA),
        defaultAccent: Color(hex: 0x2F5F8C),
        defaultCard: Color(hex: 0xF4F8FC),
        field: [
            Color(hex: 0xF2F7FC), Color(hex: 0xE7F0F8), Color(hex: 0xD9E7F3),
            Color(hex: 0xE3EFF8), Color(hex: 0xD2E2F0), Color(hex: 0xBED4E9),
            Color(hex: 0xCFE0EF), Color(hex: 0xB9D0E6), Color(hex: 0x9FBDD9),
        ],
        wallpaper: nil,
        prefersDarkContent: true)
}

// MARK: - Color helpers

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1)
    }

    /// `#RRGGBB`, for round-tripping the colour pickers through UserDefaults.
    init?(hexString: String) {
        var text = hexString.trimmingCharacters(in: .whitespaces)
        if text.hasPrefix("#") { text.removeFirst() }
        guard text.count == 6, let value = UInt32(text, radix: 16) else { return nil }
        self.init(hex: value)
    }

    var hexString: String {
        #if canImport(UIKit)
        let ui = UIColor(self)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard ui.getRed(&r, green: &g, blue: &b, alpha: &a) else { return "#000000" }
        return String(format: "#%02X%02X%02X",
                      Int(round(r * 255)), Int(round(g * 255)), Int(round(b * 255)))
        #else
        return "#000000"
        #endif
    }
}
