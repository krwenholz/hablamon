#if canImport(SwiftUI)
    import HablamonCore
    import SwiftUI

    /// The bottom strip: state, the five pipeline lights, voice, and key hints.
    struct StatusStrip: View {
        var state: CompanionState
        var english: Bool
        var voiceSummary: String
        var keys: (pause: String, recalibrate: String)
        var onSpeakers: () -> Void
        var onDiagnostics: () -> Void

        var body: some View {
            HStack(spacing: 14) {
                Text("● " + text(state.pill, english: english))
                    .font(Theme.menu(14))
                    .foregroundStyle(Theme.ink)
                    .padding(.horizontal, 16).padding(.vertical, 6)
                    .background(Capsule().fill(Theme.color(state.pill)))
                light(.camera, state.lights.camera)
                light(.tv, state.lights.tv)
                light(.box, state.lights.box)
                light(.text, state.lights.text)
                light(.voice, state.lights.voice)
                Rectangle().fill(Color(hex: 0x3A3A46)).frame(width: 1, height: 22)
                Text(voiceSummary).foregroundStyle(Color(hex: 0xC9C8D2))
                Spacer()
                if !state.unknownSpeakers.isEmpty {
                    Button(action: onSpeakers) {
                        Text(unassignedVoices(state.unknownSpeakers.count, english: english))
                            .foregroundStyle(Theme.yellow)
                    }
                    .buttonStyle(.plain)
                }
                Button(action: onDiagnostics) {
                    Text(text(.diagnostics, english: english)).foregroundStyle(Color(hex: 0x9A98A8))
                }
                .buttonStyle(.plain)
                hint(.pause, keys.pause)
                hint(.recalibrate, keys.recalibrate)
            }
            .font(Theme.menu(13, heavy: false))
            .padding(.horizontal, 10)
            .frame(height: 52)
            .background(Capsule().fill(Theme.ink))
        }

        private func light(_ label: LabelKey, _ light: Light) -> some View {
            HStack(spacing: 7) {
                Circle().fill(Theme.color(light)).frame(width: 9, height: 9)
                    .shadow(color: light == .off ? .clear : Theme.color(light), radius: 4)
                Text(text(label, english: english)).foregroundStyle(Color(hex: 0xC9C8D2))
            }
        }

        private func hint(_ label: LabelKey, _ key: String) -> some View {
            HStack(spacing: 4) {
                Text(text(label, english: english)).foregroundStyle(Color(hex: 0x9A98A8))
                Text(KeyMap.label(key)).foregroundStyle(.white)
            }
        }
    }
#endif
