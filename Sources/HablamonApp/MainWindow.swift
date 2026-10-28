#if canImport(SwiftUI) && canImport(AVFoundation)
    import HablamonCore
    import SwiftUI

    /// What the right-hand slot shows next to the key words, if anything.
    enum SidePanel: String {
        case words, speakers, diagnostics, calibration
    }

    /// The line being spoken with its English, and the line's key words. The conversation and the
    /// session's word list live in the recap, one click (or H) away.
    struct MainWindow: View {
        @Bindable var model: AppModel
        private var side: SidePanel { model.side }

        var body: some View {
            VStack(spacing: 22) {
                HeroBox(
                    page: model.state.current, translation: model.currentTranslation, waiting: model.liveStatus,
                    spokenUTF16: model.state.spokenUTF16, pill: model.state.pill, english: model.english,
                    keys: (KeyMap.label(model.keys.repeatLast), KeyMap.label(model.keys.repeatLastSlowly)))
                Group {
                    if model.showRecap {
                        RecapView(model: model)
                    } else {
                        HStack(spacing: 22) {
                            KeyWordsPanel(words: model.keyWords, english: model.english) { model.markKnown($0) }
                            if side != .words { sidePanel.frame(width: 430) }
                        }
                    }
                }
                .frame(maxHeight: model.showRecap || side != .words ? .infinity : 300)
                StatusStrip(
                    state: model.state, english: model.english, voiceSummary: model.voiceSummary,
                    camera: model.live == nil ? nil : model.cameraSource,
                    keys: (model.keys.togglePause, model.keys.recalibrate),
                    recapKey: model.keys.toggleRecap ?? "h", cameraKey: model.keys.toggleCamera ?? "m",
                    onSpeakers: { model.side = side == .speakers ? .words : .speakers },
                    onDiagnostics: { model.side = side == .diagnostics ? .words : .diagnostics },
                    onRecap: { model.showRecap.toggle() },
                    onCamera: { model.toggleCamera() })
            }
            .padding(.horizontal, 26)
            .padding(.top, 22)
            .padding(.bottom, 18)
            .frame(minWidth: 1100, maxWidth: .infinity, minHeight: 720, maxHeight: .infinity)
            .onChange(of: model.state.unknownSpeakers.isEmpty) { _, empty in
                if empty && side == .speakers { model.side = .words }
            }
            .modifier(TranslationDriver(model: model))
            .overlay {
                if model.screenOpen { ScreenTranslationView(model: model) }
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
                EmptyView()
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

    /// The conversation so far and the session's words, for looking back. Opened with H or the strip.
    struct RecapView: View {
        var model: AppModel

        var body: some View {
            HStack(spacing: 22) {
                ConversationPanel(
                    items: model.state.conversation, lineCount: model.state.lineCount, english: model.english,
                    translation: { model.state.translation(of: $0) }
                ) { model.replay($0) }
                WordsPanel(words: model.words, english: model.english) { model.markKnown($0) }
                    .frame(width: 430)
            }
        }
    }
#endif
