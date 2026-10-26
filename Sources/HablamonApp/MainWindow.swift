#if canImport(SwiftUI) && canImport(AVFoundation)
    import HablamonCore
    import SwiftUI

    /// What the right-hand slot shows. Words unless the player opens speakers or diagnostics.
    enum SidePanel: String {
        case words, speakers, diagnostics
    }

    /// Layout B from docs/plans/mockups/main-window.png, sized for a 13" Air at full screen.
    struct MainWindow: View {
        @Bindable var model: AppModel
        @Binding var side: SidePanel

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
                    sidePanel.frame(width: 430)
                }
                StatusStrip(
                    state: model.state, english: model.english, voiceSummary: model.voiceSummary,
                    hotkeys: (model.hotkeys.togglePause, model.hotkeys.recalibrate),
                    onSpeakers: { side = side == .speakers ? .words : .speakers },
                    onDiagnostics: { side = side == .diagnostics ? .words : .diagnostics })
            }
            .padding(.horizontal, 26)
            .padding(.top, 22)
            .padding(.bottom, 18)
            .frame(minWidth: 1100, minHeight: 720)
            .onChange(of: model.state.unknownSpeakers.isEmpty) { _, empty in
                if empty && side == .speakers { side = .words }
            }
            .background {
                ZStack {
                    Theme.background
                    Stripes()
                }
                .ignoresSafeArea()
            }
        }

        @ViewBuilder private var sidePanel: some View {
            switch side {
            case .words:
                WordsPanel(words: model.words, english: model.english) { model.markKnown($0) }
            case .speakers:
                SpeakersPanel(
                    speakers: model.state.unknownSpeakers, english: model.english,
                    onTag: { model.tag($0, as: $1) }, onReplay: { model.replay($0) }, onClose: { side = .words })
            case .diagnostics:
                DiagnosticsPanel(model: model) { side = .words }
            }
        }
    }
#endif
