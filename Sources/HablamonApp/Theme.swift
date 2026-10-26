#if canImport(SwiftUI)
    import HablamonCore
    import SwiftUI

    /// Colors and type borrowed from Scarlet's menus and dialogue box (see docs/plans/mockups).
    enum Theme {
        static let navy = Color(hex: 0x1B2453)
        static let ink = Color(hex: 0x1D1D24)
        static let paper = Color(hex: 0xFBFAF3)
        static let bubble = Color(hex: 0xF3F1E8)
        static let yellow = Color(hex: 0xF6CF1A)
        static let scarlet = Color(hex: 0xE5402A)
        static let green = Color(hex: 0x3FCF6E)
        static let amber = Color(hex: 0xFFB21A)
        static let red = Color(hex: 0xFF4D4D)
        static let muted = Color(hex: 0x9A98A0)
        static let unspoken = Color(hex: 0xA3A5AD)

        static let background = LinearGradient(
            colors: [Color(hex: 0xFFB33B), Color(hex: 0xFF7A1A), Color(hex: 0xE5402A)],
            startPoint: .topLeading, endPoint: .bottomTrailing)

        /// The game's dialogue face is a humanist sans; Gill Sans is the closest system match.
        static func dialogue(_ size: CGFloat, bold: Bool = false) -> Font {
            .custom(bold ? "GillSans-SemiBold" : "GillSans", size: size)
        }

        /// Heavy italic headers, like Scarlet's menu pills.
        static func menu(_ size: CGFloat, heavy: Bool = true) -> Font {
            .custom(heavy ? "AvenirNext-HeavyItalic" : "AvenirNext-DemiBold", size: size)
        }

        static func color(_ light: Light) -> Color {
            switch light {
            case .off: Color(hex: 0x5A607A)
            case .ok: green
            case .working: yellow
            case .bad: red
            }
        }

        static func color(_ pill: StatusPill) -> Color {
            switch pill {
            case .idle: Color(hex: 0x8A8F9E)
            case .reading: green
            case .speaking: yellow
            case .phoneInUse, .findingTV: amber
            case .lostCamera, .needsYou: red
            }
        }

        /// A stable avatar color per speaker name.
        static func avatar(for name: String) -> Color {
            let palette: [UInt32] = [0x3C5BD6, 0x7A3FB8, 0x2E9E6B, 0xD9572B, 0xB8396F, 0x2F8FB3]
            let index = name.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0xFFFF } % palette.count
            return Color(hex: palette[index])
        }
    }

    /// Diagonal stripes over the background, like the game's menu screens.
    struct Stripes: View {
        var body: some View {
            Canvas { context, size in
                let step: CGFloat = 44
                var x: CGFloat = -size.height
                while x < size.width {
                    var path = Path()
                    path.move(to: CGPoint(x: x, y: size.height))
                    path.addLine(to: CGPoint(x: x + size.height, y: 0))
                    path.addLine(to: CGPoint(x: x + size.height + step / 2, y: 0))
                    path.addLine(to: CGPoint(x: x + step / 2, y: size.height))
                    context.fill(path, with: .color(.white.opacity(0.10)))
                    x += step
                }
            }
        }
    }

    /// White card with a heavy ink outline and a hard offset shadow.
    struct InkCard<Content: View>: View {
        var title: String
        var detail: String?
        @ViewBuilder var content: Content

        var body: some View {
            VStack(spacing: 0) {
                HStack {
                    Text(title).font(Theme.menu(18))
                    Spacer()
                    if let detail { Text(detail).font(Theme.menu(13)).foregroundStyle(Theme.yellow) }
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 18)
                .padding(.vertical, 9)
                .background(Theme.ink)
                content.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
            .background(.white)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.ink, lineWidth: 3))
            .background(RoundedRectangle(cornerRadius: 16).fill(Theme.ink).offset(x: 6, y: 6))
        }
    }

    extension Color {
        init(hex: UInt32) {
            self.init(
                red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
                blue: Double(hex & 0xFF) / 255)
        }
    }
#endif
