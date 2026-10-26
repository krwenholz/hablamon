#if canImport(SwiftUI)
    import HablamonCore
    import HablamonModels
    import SwiftUI

    /// Unknown speakers and what they said, with a voice choice for each. Opens only when asked.
    struct SpeakersPanel: View {
        var speakers: [UnknownSpeaker]
        var english: Bool
        var onTag: (UnknownSpeaker, Gender) -> Void
        var onReplay: (SpokenPage) -> Void
        var onClose: () -> Void

        var body: some View {
            InkCard(title: unassignedVoices(speakers.count, english: english), detail: nil) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        ForEach(speakers) { speaker in
                            row(speaker)
                        }
                    }
                    .padding(16)
                }
            }
            .overlay(alignment: .topTrailing) { CloseButton(action: onClose) }
        }

        private func row(_ speaker: UnknownSpeaker) -> some View {
            VStack(alignment: .leading, spacing: 8) {
                NameTag(name: speaker.shownName, size: 16)
                ForEach(Array(speaker.lines.suffix(3).enumerated()), id: \.offset) { _, page in
                    Text("▶ " + page.text)
                        .font(Theme.dialogue(15))
                        .foregroundStyle(Theme.ink)
                        .lineLimit(2)
                        .onTapGesture { onReplay(page) }
                }
                HStack(spacing: 8) {
                    choice(.male, .male, speaker)
                    choice(.female, .female, speaker)
                    choice(.neutral, .neutral, speaker)
                }
            }
        }

        private func choice(_ label: LabelKey, _ gender: Gender, _ speaker: UnknownSpeaker) -> some View {
            Button(text(label, english: english)) { onTag(speaker, gender) }
                .buttonStyle(.plain)
                .font(Theme.menu(13))
                .foregroundStyle(.white)
                .padding(.horizontal, 12).padding(.vertical, 5)
                .background(Capsule().fill(Theme.navy))
        }
    }

    /// Numbers for checking that the pipeline is healthy, plus any file problems.
    struct DiagnosticsPanel: View {
        var model: AppModel
        var onClose: () -> Void

        var body: some View {
            InkCard(title: text(.diagnostics, english: model.english), detail: nil) {
                VStack(alignment: .leading, spacing: 8) {
                    row("Fuente", model.source ?? "—")
                    row("Líneas", "\(model.state.lineCount)")
                    row("Confianza OCR", model.state.lastConfidence.map { String(format: "%.2f", $0) } ?? "—")
                    row("Retraso", String(format: "%.1f s", model.replayLag))
                    row("Datos", model.store.root.path)
                    ForEach(model.issues, id: \.self) { issue in
                        Text(issue).font(Theme.menu(12, heavy: false)).foregroundStyle(Theme.scarlet)
                    }
                }
                .padding(18)
            }
            .overlay(alignment: .topTrailing) { CloseButton(action: onClose) }
        }

        private func row(_ name: String, _ value: String) -> some View {
            HStack(alignment: .firstTextBaseline) {
                Text(name).foregroundStyle(Color(hex: 0x45444C))
                Spacer()
                Text(value).foregroundStyle(Theme.ink).lineLimit(1).truncationMode(.head)
            }
            .font(Theme.menu(14, heavy: false))
        }
    }

    struct CloseButton: View {
        var action: () -> Void

        var body: some View {
            Button(action: action) {
                Text("✕").font(Theme.menu(14)).foregroundStyle(.white).padding(10)
            }
            .buttonStyle(.plain)
        }
    }
#endif
