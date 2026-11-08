import HablamonCore
import HablamonModels
import SwiftUI

/// The camera screen: the live picture with the proposed TV corners (drag to adjust), how readable
/// the text will be, and the zoom buttons, with exposure and focus under Ajustes.
struct CameraView: View {
    var model: PhoneModel
    /// Corners in camera pixels once the player starts dragging; until then, the proposal.
    @State private var edited: Quad?

    private var quad: Quad? { edited ?? model.preview?.proposal }

    var body: some View {
        GeometryReader { geometry in
            // The picture beside the controls in landscape, above them in portrait; there it's tall,
            // so it gets at most 55 % of the height and the controls the rest.
            if geometry.size.height > geometry.size.width {
                VStack(spacing: 12) {
                    pictureOrPlaceholder.frame(maxHeight: geometry.size.height * 0.55)
                    sidebar
                }
            } else {
                HStack(alignment: .top, spacing: 16) {
                    pictureOrPlaceholder
                    sidebar.frame(width: 260)
                }
            }
        }
        .padding(12)
        .background(ThemeBackground())
        .font(Theme.menu(14, heavy: false))
        .foregroundStyle(Theme.ink)
    }

    @ViewBuilder private var pictureOrPlaceholder: some View {
        if let preview = model.preview {
            picture(preview).frame(maxWidth: .infinity)
        } else {
            VStack(spacing: 12) {
                ProgressView().tint(.white)
                Text(model.status ?? "Abriendo la cámara…").font(Theme.menu(14, heavy: false))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .inkCard(12, fill: Theme.ink)
        }
    }

    /// What the camera screen needs at a glance: readability, zoom, and the confirm button. The
    /// rarely needed exposure and focus controls sit folded away under Ajustes.
    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Cámara").font(Theme.menu(18))
                Spacer()
                Button("Cerrar", systemImage: "xmark") {
                    edited = nil
                    model.showingCamera = false
                }
                .labelStyle(.iconOnly)
                .font(.system(size: 16, weight: .bold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Theme.ink)
            VStack(alignment: .leading, spacing: 12) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Arrastra las esquinas a la pantalla de la tele.").foregroundStyle(Theme.faint)
                        if let quality = model.preview?.quality {
                            Text(String(format: "Texto: %.0f px", quality.textHeight)).font(Theme.menu(15))
                            ForEach(quality.warnings, id: \.self) { warning in
                                Text(warning).foregroundStyle(Theme.scarlet)
                            }
                        }
                        zoomButtons
                        DisclosureGroup("Ajustes") { adjustments.padding(.top, 8) }
                            .tint(Theme.ink)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                Button {
                    if let quad { model.confirm(quad) }
                    edited = nil
                } label: {
                    Text("Usar estas esquinas").frame(maxWidth: .infinity)
                }
                .buttonStyle(PillButtonStyle(lit: true))
                .overlay(Capsule().stroke(Theme.ink, lineWidth: 2))
                .opacity(quad == nil ? 0.5 : 1)
                .disabled(quad == nil)
            }
            .padding(12)
        }
        .inkCard(12)
    }

    private var zoomButtons: some View {
        HStack(spacing: 6) {
            ForEach(model.zoomOptions) { option in
                Button {
                    edited = nil
                    model.useZoom(option)
                } label: {
                    Text(option.name).frame(maxWidth: .infinity)
                }
                .buttonStyle(
                    PillButtonStyle(lit: option.matches(lensID: model.lensID, zoom: model.controls.zoom), padding: 6))
            }
        }
    }

    private var adjustments: some View {
        VStack(alignment: .leading, spacing: 12) {
            if model.controls.maxBias > model.controls.minBias {
                // Darker keeps the bright dialogue box from blowing out; ±3 stops is plenty.
                Text(String(format: "Exposición %+.1f", model.controls.exposureBias))
                Slider(
                    value: Binding(get: { model.controls.exposureBias }, set: { model.setExposureBias($0) }),
                    in: max(model.controls.minBias, -3)...min(model.controls.maxBias, 3)
                )
                .tint(Theme.navy)
            }
            Toggle(
                "Bloquear enfoque",
                isOn: Binding(get: { model.controls.focusLocked }, set: { model.setFocusLocked($0) })
            )
            .tint(Theme.green)
        }
    }

    private func picture(_ preview: CameraPreview) -> some View {
        let image = preview.image
        let aspect = Double(image.height) / Double(image.width)
        return GeometryReader { geometry in
            // View points per camera pixel.
            let fit = geometry.size.width / Double(image.width) * preview.scale
            ZStack(alignment: .topLeading) {
                Image(decorative: image, scale: 1).resizable()
                    .frame(width: geometry.size.width, height: geometry.size.width * aspect)
                if let quad {
                    Path { path in
                        let corners = [quad.topLeft, quad.topRight, quad.bottomRight, quad.bottomLeft]
                        path.addLines(corners.map { CGPoint(x: $0.x * fit, y: $0.y * fit) })
                        path.closeSubpath()
                    }
                    .stroke(Theme.green, lineWidth: 2)
                    ForEach(0..<4, id: \.self) { index in
                        handle(index, quad: quad, fit: fit)
                    }
                }
            }
        }
        .aspectRatio(1 / aspect, contentMode: .fit)
        .inkCard(12, fill: Theme.ink)
    }

    /// A corner to drag; the touch target is larger than the dot, for fingers.
    private func handle(_ index: Int, quad: Quad, fit: Double) -> some View {
        let point = [quad.topLeft, quad.topRight, quad.bottomRight, quad.bottomLeft][index]
        return Circle()
            .fill(Theme.green)
            .overlay(Circle().stroke(Theme.ink, lineWidth: 2))
            .frame(width: 18, height: 18)
            .frame(width: 44, height: 44)
            .contentShape(Circle())
            .position(x: point.x * fit, y: point.y * fit)
            .gesture(
                DragGesture().onChanged { drag in
                    var updated = edited ?? quad
                    let moved = Point(x: drag.location.x / fit, y: drag.location.y / fit)
                    switch index {
                    case 0: updated.topLeft = moved
                    case 1: updated.topRight = moved
                    case 2: updated.bottomRight = moved
                    default: updated.bottomLeft = moved
                    }
                    edited = updated
                })
    }
}
