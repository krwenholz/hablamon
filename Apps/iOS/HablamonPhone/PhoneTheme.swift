import HablamonCore
import SwiftUI

// A copy of the Mac's Theme.swift and HeroBox pieces the phone needs; phase 3 merges them into
// HablamonUI (docs/plans/ios-app.md).

/// Colors and type borrowed from Scarlet's menus and dialogue box, as on the Mac.
enum Theme {
    static let navy = Color(hex: 0x1B2453)
    static let ink = Color(hex: 0x1D1D24)
    static let paper = Color(hex: 0xFBFAF3)
    static let yellow = Color(hex: 0xF6CF1A)
    static let scarlet = Color(hex: 0xE5402A)
    static let green = Color(hex: 0x3FCF6E)
    static let amber = Color(hex: 0xFFB21A)
    static let red = Color(hex: 0xFF4D4D)
    static let unspoken = Color(hex: 0xA3A5AD)
    /// Secondary text on ink.
    static let dim = Color(hex: 0xC9C8D2)
    /// Secondary text on paper.
    static let faint = Color(hex: 0x45444C)

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

    static func color(_ pill: StatusPill) -> Color {
        switch pill {
        case .idle: Color(hex: 0x8A8F9E)
        case .reading: green
        case .speaking: yellow
        case .phoneInUse, .findingTV: amber
        case .lostCamera, .needsYou: red
        }
    }
}

/// The striped orange background of the game's menu screens.
struct ThemeBackground: View {
    var body: some View {
        ZStack {
            Theme.background
            Stripes()
        }
        .ignoresSafeArea()
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

extension View {
    /// The heavy ink outline and hard offset shadow of the game's dialogue box.
    func inkCard(_ radius: CGFloat = 14, fill: Color = Theme.paper) -> some View {
        background(fill)
            .clipShape(RoundedRectangle(cornerRadius: radius))
            .overlay(RoundedRectangle(cornerRadius: radius).stroke(Theme.ink, lineWidth: 3))
            .background(RoundedRectangle(cornerRadius: radius).fill(Theme.ink).offset(x: 5, y: 5))
    }
}

/// The yellow tick marks on the game's dialogue box.
struct Tick: View {
    var height: CGFloat = 44

    var body: some View {
        RoundedRectangle(cornerRadius: 2).fill(Theme.yellow).frame(width: 7, height: height)
    }
}

/// The navy name tab with a slanted right edge.
struct NameTag: View {
    var name: String
    var size: CGFloat

    var body: some View {
        Text(name)
            .font(Theme.dialogue(size, bold: true))
            .foregroundStyle(.white)
            .padding(.leading, size * 0.9)
            .padding(.trailing, size * 1.4)
            .padding(.vertical, size * 0.28)
            .background(Theme.navy)
            .clipShape(SlantedTab())
    }
}

struct SlantedTab: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: rect.origin)
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX - 10, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.closeSubpath()
        }
    }
}

/// A button drawn as one of the game's dark menu pills; `lit` turns it yellow, for a state that's on.
struct PillButtonStyle: ButtonStyle {
    var lit = false
    var padding: CGFloat = 14

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.menu(14))
            .foregroundStyle(lit ? Theme.ink : .white)
            .padding(.horizontal, padding)
            .padding(.vertical, 8)
            .background(Capsule().fill(lit ? Theme.yellow : Theme.ink))
            .opacity(configuration.isPressed ? 0.7 : 1)
            .contentShape(Capsule())
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255)
    }
}
