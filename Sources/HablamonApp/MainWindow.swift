#if canImport(SwiftUI) && canImport(AVFoundation)
    import HablamonCore
    import SwiftUI

    /// What the right-hand slot shows. Words unless the player opens speakers or diagnostics.
    enum SidePanel: String {
        case words, speakers, diagnostics, calibration
    }

    /// Layout B from docs/plans/mockups/main-window.png, sized for a 13" Air at full screen.
    struct MainWindow: View {
        @Bindable var model: AppModel
        private var side: SidePanel { model.side }

        var body: some View {
            VStack(spacing: 18) {
                HeroBox(
                    page: model.state.current, waiting: model.liveStatus, spokenUTF16: model.state.spokenUTF16,
                    pill: model.state.pill,
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
                    onSpeakers: { model.side = side == .speakers ? .words : .speakers },
                    onDiagnostics: { model.side = side == .diagnostics ? .words : .diagnostics })
            }
            .padding(.horizontal, 26)
            .padding(.top, 22)
            .padding(.bottom, 18)
            .frame(minWidth: 1100, minHeight: 720)
            .onChange(of: model.state.unknownSpeakers.isEmpty) { _, empty in
                if empty && side == .speakers { model.side = .words }
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
                    onTag: { model.tag($0, as: $1) }, onReplay: { model.replay($0) }, onClose: { model.side = .words })
            case .diagnostics:
                DiagnosticsPanel(model: model) { model.side = .words }
            case .calibration:
                CalibrationPanel(
                    preview: model.calibrationPreview, status: model.liveStatus, english: model.english,
                    onConfirm: { model.confirmCalibration($0) },
                    onClose: {
                        model.side = .words
                        model.live?.engine?.setWantsPreview(false)
                    })
            }
        }
    }
#endif
