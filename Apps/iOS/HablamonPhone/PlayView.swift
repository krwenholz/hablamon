import HablamonCore
import HablamonModels
import SwiftUI

/// The play screen: the line being read in the game's own dialogue box, large enough to follow from
/// the sofa, its English below, and a few controls. Tap the line to hear it again.
struct PlayView: View {
    @Bindable var model: PhoneModel

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 14) {
                card
                controls
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            if model.showingStats {
                StatsPanel(model: model).padding(12)
            }
        }
        .background(ThemeBackground())
        .fullScreenCover(isPresented: $model.showingCamera) {
            CameraView(model: model)
        }
    }

    /// The dialogue box with the speaker's tab on its top edge and the state pills opposite.
    private var card: some View {
        ZStack(alignment: .topLeading) {
            box.padding(.top, 24)
            if let name = speakerName {
                NameTag(name: name, size: 18).offset(x: -4, y: 2)
            }
            HStack(spacing: 8) {
                Spacer()
                Text("● " + HablamonCore.text(model.state.pill, english: false))
                    .foregroundStyle(Theme.ink)
                    .padding(.horizontal, 12).padding(.vertical, 5)
                    .background(Capsule().fill(Theme.color(model.state.pill)))
                Text(model.voiceSummary)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12).padding(.vertical, 5)
                    .background(Capsule().fill(Theme.ink))
            }
            .font(Theme.menu(13))
            .lineLimit(1)
            .padding(.trailing, 14)
            .padding(.top, 8)
        }
    }

    private var box: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(attributedLine)
                .font(Theme.dialogue(36))
                .lineSpacing(4)
                .minimumScaleFactor(0.5)
                .frame(maxWidth: .infinity, alignment: .leading)
            if model.state.current != nil {
                Text(model.currentTranslation ?? "…")
                    .font(Theme.menu(22, heavy: false))
                    .italic()
                    .foregroundStyle(Theme.navy.opacity(model.currentTranslation == nil ? 0.35 : 0.85))
                    .minimumScaleFactor(0.6)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.leading, 40)
        .padding(.trailing, 28)
        .padding(.top, 28)
        .padding(.bottom, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .overlay(alignment: .topLeading) { Tick(height: 34).padding(.leading, 16).padding(.top, 20) }
        .overlay(alignment: .bottomTrailing) {
            HStack(alignment: .bottom, spacing: 14) {
                Text("▽").font(.system(size: 14)).foregroundStyle(Theme.navy)
                Tick(height: 34)
            }
            .padding(.trailing, 14).padding(.bottom, 14)
        }
        .inkCard()
        .contentShape(Rectangle())
        .onTapGesture { model.repeatLast(slow: false) }
    }

    private var controls: some View {
        HStack(spacing: 8) {
            Button("Repetir", systemImage: "arrow.counterclockwise") { model.repeatLast(slow: false) }
                .buttonStyle(PillButtonStyle())
            Button("Lento", systemImage: "tortoise") { model.repeatLast(slow: true) }
                .buttonStyle(PillButtonStyle())
            Button(
                model.paused ? "Reanudar" : "Pausa", systemImage: model.paused ? "play.fill" : "pause.fill"
            ) { model.togglePause() }
            .buttonStyle(PillButtonStyle(lit: model.paused))
            Button(model.normalSpeed ? "1×" : "Lenta", systemImage: "speedometer") { model.toggleSpeed() }
                .buttonStyle(PillButtonStyle())
            Spacer(minLength: 0)
            Button("Cámara", systemImage: "camera.viewfinder") { model.recalibrate() }
                .buttonStyle(PillButtonStyle())
            Button("Datos", systemImage: "chart.bar.xaxis") { model.showingStats.toggle() }
                .buttonStyle(PillButtonStyle(lit: model.showingStats))
        }
        .lineLimit(1)
    }

    /// Nil for the narrator, whose lines have no name tab in the game either.
    private var speakerName: String? {
        switch model.state.current?.speaker {
        case nil, .narrator?: nil
        case .known(let name, _)?: name
        case .unknown(let tag)?: tag
        }
    }

    /// The current line with the words not yet spoken dimmed, as on the Mac.
    private var attributedLine: AttributedString {
        guard let page = model.state.current else {
            var placeholder = AttributedString(model.status ?? "Esperando un diálogo…")
            placeholder.foregroundColor = Theme.unspoken
            return placeholder
        }
        let utf16 = page.text.utf16
        let split = utf16.index(utf16.startIndex, offsetBy: min(model.state.spokenUTF16, utf16.count))
        let index = split.samePosition(in: page.text) ?? page.text.endIndex
        var spoken = AttributedString(page.text[..<index])
        spoken.foregroundColor = Theme.ink
        var rest = AttributedString(page.text[index...])
        rest.foregroundColor = model.state.pill == .speaking ? Theme.unspoken : Theme.ink
        return spoken + rest
    }
}

/// Numbers for judging whether the phone copes: heat, battery, speed, and the latest log lines.
struct StatsPanel: View {
    var model: PhoneModel

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(model.deviceSummary).font(Theme.menu(13)).foregroundStyle(Theme.yellow)
            Text(
                "lights: camera \(light(model.state.lights.camera)) tv \(light(model.state.lights.tv)) "
                    + "box \(light(model.state.lights.box)) text \(light(model.state.lights.text))")
            Divider().overlay(Theme.dim.opacity(0.4))
            ForEach(Array(model.recentLog.enumerated()), id: \.offset) { _, line in
                Text(line).lineLimit(1).truncationMode(.middle)
            }
        }
        .font(.system(size: 11, design: .monospaced))
        .foregroundStyle(.white)
        .padding(12)
        .frame(maxWidth: 420, alignment: .leading)
        .inkCard(12, fill: Theme.ink)
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
