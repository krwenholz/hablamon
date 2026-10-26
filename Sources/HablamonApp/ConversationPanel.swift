#if canImport(SwiftUI)
    import HablamonCore
    import HablamonModels
    import SwiftUI

    /// The conversation so far, newest at the bottom. Tapping a line says it again.
    struct ConversationPanel: View {
        var items: [ConversationItem]
        var lineCount: Int
        var english: Bool
        var onReplay: (SpokenPage) -> Void

        var body: some View {
            InkCard(title: text(.conversation, english: english), detail: "\(lineCount)") {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 12) {
                            ForEach(items) { item in
                                row(item).id(item.id)
                            }
                        }
                        .padding(16)
                    }
                    .onChange(of: items.last?.id) { _, last in
                        guard let last else { return }
                        withAnimation(.easeOut(duration: 0.25)) { proxy.scrollTo(last, anchor: .bottom) }
                    }
                }
            }
        }

        @ViewBuilder private func row(_ item: ConversationItem) -> some View {
            switch item {
            case .line(_, let page):
                LineRow(page: page, english: english).onTapGesture { onReplay(page) }
            case .gap(_, let reason, let seconds):
                Text("\(text(gapLabel(reason), english: english)) · \(Int(seconds.rounded())) s")
                    .font(Theme.menu(12, heavy: false))
                    .foregroundStyle(Color(hex: 0x6B6A72))
                    .padding(.horizontal, 12).padding(.vertical, 4)
                    .background(Capsule().fill(Color(hex: 0xECE9DC)))
                    .frame(maxWidth: .infinity)
            }
        }

        private func gapLabel(_ reason: TranscriptGap.Reason) -> LabelKey {
            switch reason {
            case .cameraPaused: .gapPaused
            case .cameraLost: .gapLost
            case .screenLost: .gapScreen
            }
        }
    }

    struct LineRow: View {
        var page: SpokenPage
        var english: Bool

        private var name: String {
            if case .narrator = page.speaker { return text(.narrator, english: english) }
            return page.speaker.name
        }

        var body: some View {
            HStack(alignment: .top, spacing: 12) {
                Text(String(name.prefix(1)).uppercased())
                    .font(Theme.menu(18))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(Theme.avatar(for: name)))
                    .overlay(Circle().stroke(Theme.ink, lineWidth: 2.5))
                VStack(alignment: .leading, spacing: 2) {
                    Text(name.uppercased()).font(Theme.menu(12)).foregroundStyle(Theme.navy)
                    Text(page.text).font(Theme.dialogue(19)).foregroundStyle(Theme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 14).padding(.top, 8).padding(.bottom, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    UnevenRoundedRectangle(
                        topLeadingRadius: 4, bottomLeadingRadius: 16, bottomTrailingRadius: 16, topTrailingRadius: 16
                    ).fill(Theme.bubble))
                Text(timestamp).font(Theme.menu(11, heavy: false)).foregroundStyle(Theme.muted).padding(.top, 4)
            }
            .contentShape(Rectangle())
        }

        private var timestamp: String {
            let seconds = Int(page.time)
            return String(format: "%d:%02d", seconds / 60, seconds % 60)
        }
    }
#endif
