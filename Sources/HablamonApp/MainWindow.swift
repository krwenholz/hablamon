#if canImport(SwiftUI) && canImport(AVFoundation)
    import HablamonCore
    import SwiftUI

    /// Layout B from docs/plans/mockups/main-window.png, sized for a 13" Air at full screen.
    struct MainWindow: View {
        @Bindable var model: AppModel
        @State private var showSpeakers = false
        @State private var showDiagnostics = false

        var body: some View {
            VStack(spacing: 18) {
                HeroBox(
                    page: model.state.current, spokenUTF16: model.state.spokenUTF16, pill: model.state.pill,
                    english: model.english,
                    hotkeys: (
                        HotkeyText.symbols(model.hotkeys.repeatLast), HotkeyText.symbols(model.hotkeys.repeatLastSlowly)
                    ))
                HStack(spacing: 22) {
                    ConversationPanel(
                        items: model.state.conversation, lineCount: model.state.lineCount, english: model.english
                    ) { model.replay($0) }
                    WordsPanel(words: model.words, english: model.english) { model.markKnown($0) }
                        .frame(width: 430)
                }
                StatusStrip(
                    state: model.state, english: model.english, voiceSummary: model.voiceSummary,
                    hotkeys: (model.hotkeys.togglePause, model.hotkeys.recalibrate),
                    onSpeakers: { showSpeakers = true }, onDiagnostics: { showDiagnostics.toggle() })
            }
            .padding(.horizontal, 26)
            .padding(.top, 22)
            .padding(.bottom, 18)
            .frame(minWidth: 1100, minHeight: 720)
            .background {
                ZStack {
                    Theme.background
                    Stripes()
                }
                .ignoresSafeArea()
            }
        }
    }
#endif
