#if canImport(SwiftUI)
    import HablamonCore
    import SwiftUI

    /// The line being spoken, drawn like the game's own dialogue box. Words not yet spoken are dimmed.
    struct HeroBox: View {
        var page: SpokenPage?
        /// The line in English, once translated.
        var translation: String? = nil
        /// Shown instead of a line before there is one, such as "Esperando el iPhone…".
        var waiting: String? = nil
        var spokenUTF16: Int
        var pill: StatusPill
        var english: Bool
        var keys: (repeatLine: String, slow: String)

        var body: some View {
            ZStack(alignment: .topLeading) {
                box
                    .padding(.top, 30)
                if let name = speakerName {
                    NameTag(name: name, size: 23).offset(x: -6, y: 4)
                }
                HStack(spacing: 8) {
                    Spacer()
                    if pill == .speaking { Badge(text: "▶ " + text(LabelKey.speaking, english: english), filled: true) }
                    Badge(text: "↻ \(keys.repeatLine)", filled: false)
                    Badge(text: "\(text(.slow, english: english)) \(keys.slow)", filled: false)
                }
                .padding(.trailing, 16)
            }
        }

        private var speakerName: String? {
            guard let page else { return nil }
            if case .narrator = page.speaker { return nil }
            return page.speaker.name
        }

        private var box: some View {
            VStack(alignment: .leading, spacing: 14) {
                Text(attributedLine)
                    .font(Theme.dialogue(44))
                    .lineSpacing(6)
                    .lineLimit(3)
                    .minimumScaleFactor(0.6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(page == nil ? " " : translation ?? "…")
                    .font(Theme.menu(30, heavy: false))
                    .italic()
                    .foregroundStyle(Theme.navy.opacity(translation == nil ? 0.35 : 0.85))
                    .lineLimit(3)
                    .minimumScaleFactor(0.7)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.leading, 52)
            .padding(.trailing, 100)
            .padding(.vertical, 34)
            .frame(maxWidth: .infinity, minHeight: 330, maxHeight: .infinity, alignment: .topLeading)
            .background(Theme.paper)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(alignment: .topLeading) { Tick().padding(.leading, 18).padding(.top, 20) }
            .overlay(alignment: .bottomTrailing) {
                HStack(alignment: .bottom, spacing: 18) {
                    Text("▽").font(.system(size: 18)).foregroundStyle(Theme.navy)
                    Tick()
                }
                .padding(.trailing, 18).padding(.bottom, 18)
            }
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.ink, lineWidth: 3))
            .background(RoundedRectangle(cornerRadius: 14).fill(Theme.ink).offset(x: 6, y: 6))
        }

        private var attributedLine: AttributedString {
            guard let page else {
                var placeholder = AttributedString(waiting ?? "…")
                placeholder.foregroundColor = Theme.unspoken
                return placeholder
            }
            let utf16 = page.text.utf16
            let split = utf16.index(utf16.startIndex, offsetBy: min(spokenUTF16, utf16.count))
            let index = split.samePosition(in: page.text) ?? page.text.endIndex
            var spoken = AttributedString(page.text[..<index])
            spoken.foregroundColor = Theme.ink
            var rest = AttributedString(page.text[index...])
            rest.foregroundColor = pill == .speaking ? Theme.unspoken : Theme.ink
            return spoken + rest
        }
    }

    /// The yellow tick marks on the game's dialogue box.
    struct Tick: View {
        var body: some View {
            RoundedRectangle(cornerRadius: 2).fill(Theme.yellow).frame(width: 7, height: 44)
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

    struct Badge: View {
        var text: String
        var filled: Bool

        var body: some View {
            Text(text)
                .font(Theme.menu(14))
                .foregroundStyle(filled ? Theme.ink : .white)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(Capsule().fill(filled ? Theme.yellow : Theme.ink))
        }
    }
#endif
