import HablamonCore
import HablamonModels
import SwiftUI

/// The play screen: the line being read, large enough to follow from the sofa, its English below,
/// and a few controls. Tap the line to hear it again.
struct PlayView: View {
    @Bindable var model: PhoneModel

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 12) {
                header
                Text(attributedLine)
                    .font(.system(size: 30, weight: .semibold, design: .rounded))
                    .minimumScaleFactor(0.5)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture { model.repeatLast(slow: false) }
                if let english = model.currentTranslation {
                    Text(english)
                        .font(.system(size: 20, design: .rounded)).italic()
                        .foregroundStyle(.white.opacity(0.65))
                        .minimumScaleFactor(0.6)
                }
                Spacer(minLength: 0)
                controls
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            if model.showingStats {
                StatsPanel(model: model).padding(12)
            }
        }
        .fullScreenCover(isPresented: $model.showingCamera) {
            CameraView(model: model)
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            if let page = model.state.current {
                Text(speakerName(page.speaker))
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(.yellow)
            }
            Spacer()
            Text(HablamonCore.text(model.state.pill, english: false))
            Text("·")
            Text(model.voiceSummary)
        }
        .font(.system(size: 14, design: .rounded))
        .foregroundStyle(.white.opacity(0.6))
    }

    private var controls: some View {
        HStack(spacing: 10) {
            Button("Repetir", systemImage: "arrow.counterclockwise") { model.repeatLast(slow: false) }
            Button("Lento", systemImage: "tortoise") { model.repeatLast(slow: true) }
            Button(
                model.paused ? "Reanudar" : "Pausa", systemImage: model.paused ? "play.fill" : "pause.fill"
            ) { model.togglePause() }
            Button(model.normalSpeed ? "1×" : "Lenta", systemImage: "speedometer") { model.toggleSpeed() }
            Spacer()
            Button("Cámara", systemImage: "camera.viewfinder") { model.recalibrate() }
            Button("Datos", systemImage: "chart.bar.xaxis") { model.showingStats.toggle() }
        }
        .buttonStyle(.bordered)
        .tint(.white)
        .font(.system(size: 14, design: .rounded))
    }

    private func speakerName(_ speaker: ResolvedSpeaker) -> String {
        switch speaker {
        case .narrator: HablamonCore.text(.narrator, english: false)
        case .known(let name, _): name
        case .unknown(let tag): tag
        }
    }

    /// The current line with the words not yet spoken dimmed, as on the Mac.
    private var attributedLine: AttributedString {
        guard let page = model.state.current else {
            var placeholder = AttributedString(model.status ?? "Esperando un diálogo…")
            placeholder.foregroundColor = Color.white.opacity(0.4)
            return placeholder
        }
        let utf16 = page.text.utf16
        let split = utf16.index(utf16.startIndex, offsetBy: min(model.state.spokenUTF16, utf16.count))
        let index = split.samePosition(in: page.text) ?? page.text.endIndex
        var spoken = AttributedString(page.text[..<index])
        spoken.foregroundColor = Color.white
        var rest = AttributedString(page.text[index...])
        rest.foregroundColor = model.state.pill == .speaking ? Color.white.opacity(0.45) : Color.white
        return spoken + rest
    }
}

/// Numbers for judging whether the phone copes: heat, battery, speed, and the latest log lines.
struct StatsPanel: View {
    var model: PhoneModel

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(model.deviceSummary).bold()
            Text(
                "lights: camera \(light(model.state.lights.camera)) tv \(light(model.state.lights.tv)) "
                    + "box \(light(model.state.lights.box)) text \(light(model.state.lights.text))")
            Divider().overlay(.white.opacity(0.3))
            ForEach(Array(model.recentLog.enumerated()), id: \.offset) { _, line in
                Text(line).lineLimit(1).truncationMode(.middle)
            }
        }
        .font(.system(size: 11, design: .monospaced))
        .foregroundStyle(.white)
        .padding(10)
        .frame(maxWidth: 420, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(.black.opacity(0.85)))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(.white.opacity(0.2)))
        .onTapGesture { model.showingStats = false }
    }

    private func light(_ light: Light) -> String {
        switch light {
        case .off: "–"
        case .ok: "ok"
        case .working: "…"
        case .bad: "✗"
        }
    }
}
