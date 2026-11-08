import HablamonCore
import HablamonModels
import SwiftUI

/// The play screen: the line being read in the game's own dialogue box, large enough to follow from
/// the sofa, its English below, and a few controls. Tap the line to hear it again. The buttons sit
/// in a row in landscape and in a grid below the box in portrait.
struct PlayView: View {
    @Bindable var model: PhoneModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geometry in
            let portrait = geometry.size.height > geometry.size.width
            ZStack(alignment: .topTrailing) {
                VStack(spacing: 14) {
                    card
                    if portrait { portraitControls } else { landscapeControls }
                }
                .padding(.horizontal, portrait ? 12 : 16)
                .padding(.vertical, 8)
                if model.showingStats {
                    StatsPanel(model: model).padding(12)
                        .transition(Motion.panel(from: .topTrailing, reduceMotion: reduceMotion))
                }
            }
            .animation(Motion.appear, value: model.showingStats)
        }
        .background(ThemeBackground())
        .accessibilityHidden(model.showingCamera)
        // Laid over the play screen and cross-faded, rather than a full-screen cover sliding up:
        // both screens share the background, so only their contents change.
        .overlay {
            if model.showingCamera {
                CameraView(model: model)
                    .contentShape(Rectangle())
                    .compositingGroup()
                    .transition(.opacity)
            }
        }
        .animation(Motion.appear, value: model.showingCamera)
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
                    .contentTransition(.opacity)
                    .foregroundStyle(Theme.ink)
                    .padding(.horizontal, 12).padding(.vertical, 5)
                    .background(Capsule().fill(Theme.color(model.state.pill)))
                    .animation(reduceMotion ? nil : Motion.quick, value: model.state.pill)
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
                    .fadesIn(on: model.currentTranslation)
            }
        }
        .fadesIn(on: model.state.lineCount, rise: Motion.rise)
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

    /// Speech controls on the left, the screen's on the right.
    private var landscapeControls: some View {
        HStack(spacing: 8) {
            speechButtons(padding: 10)
            Spacer(minLength: 0)
            screenButtons(padding: 10)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.7)
    }

    /// Too narrow for one row of seven: the four speech controls, then the three for the screen.
    private var portraitControls: some View {
        VStack(spacing: 8) {
            LazyVGrid(columns: columns(4), spacing: 8) { speechButtons(padding: 8) }
            LazyVGrid(columns: columns(3), spacing: 8) { screenButtons(padding: 10) }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.7)
    }

    private func columns(_ count: Int) -> [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 6), count: count)
    }

    @ViewBuilder private func speechButtons(padding: CGFloat) -> some View {
        Button("Repetir", systemImage: "arrow.counterclockwise") { model.repeatLast(slow: false) }
            .buttonStyle(PillButtonStyle(padding: padding))
        Button("Lento", systemImage: "tortoise") { model.repeatLast(slow: true) }
            .buttonStyle(PillButtonStyle(padding: padding))
        Button(
            model.paused ? "Reanudar" : "Pausa", systemImage: model.paused ? "play.fill" : "pause.fill"
        ) { model.togglePause() }
        .buttonStyle(PillButtonStyle(lit: model.paused, padding: padding))
        Button(model.normalSpeed ? "1×" : "Lenta", systemImage: "speedometer") { model.toggleSpeed() }
            .buttonStyle(PillButtonStyle(padding: padding))
    }

    @ViewBuilder private func screenButtons(padding: CGFloat) -> some View {
        Button("Traducir", systemImage: "character.bubble") { model.openScreen() }
            .buttonStyle(PillButtonStyle(padding: padding))
        Button("Cámara", systemImage: "camera.viewfinder") { model.recalibrate() }
            .buttonStyle(PillButtonStyle(padding: padding))
        Button("Datos", systemImage: "chart.bar.xaxis") { model.showingStats.toggle() }
            .buttonStyle(PillButtonStyle(lit: model.showingStats, padding: padding))
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
            // For a line that was missed or misread: press it while the box is on screen.
            Button("Guardar captura", systemImage: "camera.metering.center.weighted") { model.saveCapture() }
                .buttonStyle(PillButtonStyle(lit: true, padding: 10))
                .padding(.top, 6)
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
