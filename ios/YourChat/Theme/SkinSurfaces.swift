import SwiftUI

/// The page background for the current skin. Paper skins get a soft flat wash;
/// glass skins get a wallpaper-like field the translucent cards sit on.
struct SkinBackground: View {
    @Environment(ThemeStore.self) private var theme

    var body: some View {
        let skin = theme.skin

        ZStack {
            if let wallpaper = skin.wallpaper {
                Image(wallpaper)
                    .resizable()
                    .scaledToFill()
            } else {
                MeshGradient(
                    width: 3,
                    height: 3,
                    points: Skin.meshPoints,
                    colors: skin.field)
            }

            // A light source high on the left, then a vignette. Together they
            // read as depth rather than as a gradient, which is what separates
            // the glass skins from a plain tinted page.
            if skin.isGlass {
                RadialGradient(
                    colors: [.white.opacity(0.22), .clear],
                    center: .init(x: 0.28, y: 0.12),
                    startRadius: 0,
                    endRadius: 520)

                RadialGradient(
                    colors: [.clear, .black.opacity(0.28)],
                    center: .center,
                    startRadius: 220,
                    endRadius: 720)
            }
        }
        .ignoresSafeArea()
        .animation(.smooth(duration: 0.45), value: theme.skinID)
    }
}

/// One card style for the whole app, so the six skins only need to supply
/// colours — every surface picks up the card colour and opacity for free.
private struct CardSurface: ViewModifier {
    @Environment(ThemeStore.self) private var theme

    var padding: CGFloat
    var radius: CGFloat

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background {
                let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
                if theme.skin.isGlass {
                    // Translucent over the wallpaper, tinted by the card colour.
                    shape
                        .fill(.ultraThinMaterial)
                        .overlay(shape.fill(theme.cardColor.opacity(1 - theme.cardOpacity)))
                } else {
                    shape.fill(theme.cardColor.opacity(theme.cardOpacity))
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(theme.onBackground.opacity(theme.skin.isGlass ? 0.14 : 0.05))
            }
            .shadow(color: .black.opacity(theme.skin.isGlass ? 0.18 : 0.05), radius: 12, y: 4)
    }
}

extension View {
    func card(padding: CGFloat = 18, radius: CGFloat = 22) -> some View {
        modifier(CardSurface(padding: padding, radius: radius))
    }
}

/// The serif display face used for the big numbers and English headings —
/// "Day 35", "Monthly Anniversary", "Good evening".
extension Font {
    static func display(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .serif)
    }
}

/// Circular avatar with a generated fallback, so the app looks right before
/// anyone picks a photo in Settings.
struct AvatarView: View {
    @Environment(ThemeStore.self) private var theme

    let sender: ChatSender
    var size: CGFloat = 40
    var name: String = ""
    /// The group conversation isn't any one sender, so it gets its own mark
    /// rather than borrowing AI A's avatar and initial.
    var isGroup: Bool = false

    var body: some View {
        Group {
            if !isGroup, let image = theme.avatar(for: sender) {
                image.resizable().scaledToFill()
            } else {
                ZStack {
                    Circle().fill(fallbackTint.gradient)
                    if isGroup {
                        Image(systemName: "person.2.fill")
                            .font(.system(size: size * 0.38))
                            .foregroundStyle(.white)
                    } else {
                        Text(initial)
                            .font(.system(size: size * 0.42, weight: .medium, design: .serif))
                            .foregroundStyle(.white)
                    }
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }

    private var initial: String {
        let source = name.isEmpty ? sender.rawValue : name
        return String(source.prefix(1)).uppercased()
    }

    private var fallbackTint: Color {
        if isGroup { return Color(hex: 0x5B6472) }
        switch sender {
        case .user: return theme.accent
        case .aiA: return Color(hex: 0x7A6CF0)
        case .aiB: return Color(hex: 0xD98324)
        }
    }
}
