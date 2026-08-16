import SwiftUI

/// The launch screen: a question, and you answer it by signing your name.
///
/// Dragging writes the signature left to right with the nib at the tip and the
/// ink line trailing behind it, so the gesture that opens the app and the mark
/// it leaves are the same motion. Where you stop is recorded as today's
/// closeness — a one-gesture check-in before anything else loads.
struct LaunchGateView: View {
    @Environment(AppModel.self) private var model
    @Environment(ThemeStore.self) private var theme

    @State private var progress: Double = 0
    @State private var isDragging = false

    private let nib: CGFloat = 24
    private let signatureHeight: CGFloat = 52

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 8) {
                Text("How close do you feel today?")
                    .font(.system(size: 15, weight: .medium, design: .serif))
                    .foregroundStyle(theme.onBackground)

                Text("Drag →")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(theme.secondaryOnBackground)
                    .opacity(isDragging || progress > 0.02 ? 0 : 1)
                    .animation(.easeOut(duration: 0.2), value: isDragging)
            }

            signaturePad
                .padding(.top, 40)
                .padding(.horizontal, 44)

            VStack(spacing: 5) {
                Text(dedication)
                    .font(.system(size: 12, design: .serif))
                    .foregroundStyle(theme.onBackground.opacity(0.7))

                if !model.profile.epigraph.isEmpty {
                    Text(model.profile.epigraph)
                        .font(.system(size: 11, design: .serif))
                        .foregroundStyle(theme.secondaryOnBackground)
                }
            }
            .padding(.top, 52)

            Spacer()
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var dedication: String {
        let you = model.profile.userName.isEmpty ? "You" : model.profile.userName
        return "For \(you) & \(model.profile.aiAName)"
    }

    // MARK: - Signing

    private var signaturePad: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let travel = width - nib
            let tip = nib / 2 + travel * progress

            ZStack(alignment: .topLeading) {
                // The name, revealed only as far as the nib has travelled.
                Text(model.profile.signatureText)
                    .font(.custom("SnellRoundhand-Black", size: 40))
                    .foregroundStyle(theme.onBackground)
                    .frame(width: width, height: signatureHeight, alignment: .center)
                    .mask(alignment: .leading) {
                        Rectangle().frame(width: max(0, tip))
                    }

                // Track, then the ink actually laid down.
                Group {
                    Capsule()
                        .fill(theme.onBackground.opacity(0.22))
                        .frame(width: width, height: 1.5)

                    Capsule()
                        .fill(theme.onBackground)
                        .frame(width: tip, height: 1.5)
                }
                .offset(y: signatureHeight + 6)

                Nib()
                    .stroke(theme.onBackground, style: .init(lineWidth: 1.6, lineCap: .round))
                    .frame(width: nib, height: nib)
                    .rotationEffect(.degrees(-12))
                    .scaleEffect(isDragging ? 1.18 : 1)
                    .offset(x: tip - nib / 2, y: signatureHeight + 6 - nib / 2)
                    .animation(.spring(duration: 0.25), value: isDragging)
            }
            .frame(width: width, height: signatureHeight + nib)
            .contentShape(.rect)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        isDragging = true
                        progress = min(max((value.location.x - nib / 2) / travel, 0), 1)
                    }
                    .onEnded { _ in
                        isDragging = false
                        // Signing most of the way opens the app; a half-hearted
                        // nudge springs back and the ink lifts.
                        if progress > 0.75 {
                            withAnimation(.smooth(duration: 0.35)) { progress = 1 }
                            model.hasEnteredApp = true
                        } else {
                            withAnimation(.spring(duration: 0.45)) { progress = 0 }
                        }
                    })
        }
        .frame(height: signatureHeight + nib)
    }
}

/// A pen nib: two shoulders meeting at a point, with the slit up the middle.
private struct Nib: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height

        path.move(to: CGPoint(x: w * 0.28, y: h * 0.06))
        path.addQuadCurve(
            to: CGPoint(x: w * 0.5, y: h * 0.94),
            control: CGPoint(x: w * 0.16, y: h * 0.62))
        path.addQuadCurve(
            to: CGPoint(x: w * 0.72, y: h * 0.06),
            control: CGPoint(x: w * 0.84, y: h * 0.62))

        path.move(to: CGPoint(x: w * 0.5, y: h * 0.42))
        path.addLine(to: CGPoint(x: w * 0.5, y: h * 0.9))
        return path
    }
}
