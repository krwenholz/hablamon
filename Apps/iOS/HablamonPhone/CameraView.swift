import HablamonCore
import HablamonModels
import SwiftUI

/// The camera screen: the live picture with the proposed TV corners (drag to adjust), how readable
/// the text will be, and the lens, zoom, exposure, and focus controls.
struct CameraView: View {
    var model: PhoneModel
    /// Corners in camera pixels once the player starts dragging; until then, the proposal.
    @State private var edited: Quad?

    private var quad: Quad? { edited ?? model.preview?.proposal }

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            if let preview = model.preview {
                picture(preview)
            } else {
                VStack(spacing: 12) {
                    ProgressView()
                    Text(model.status ?? "Abriendo la cámara…").foregroundStyle(.white.opacity(0.6))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            ScrollView {
                sidebar.frame(width: 240)
            }
            .frame(width: 240)
        }
        .padding(12)
        .background(Color.black.ignoresSafeArea())
        .foregroundStyle(.white)
        .font(.system(size: 14, design: .rounded))
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Calibración").font(.system(size: 18, weight: .bold, design: .rounded))
                Spacer()
                Button("Cerrar", systemImage: "xmark") {
                    edited = nil
                    model.showingCamera = false
                }
                .labelStyle(.iconOnly)
            }
            Text("Arrastra las esquinas a la pantalla de la tele.").foregroundStyle(.white.opacity(0.6))
            if let quality = model.preview?.quality {
                Text(String(format: "Texto: %.0f px", quality.textHeight))
                ForEach(quality.warnings, id: \.self) { warning in
                    Text(warning).foregroundStyle(.orange)
                }
            }
            Button {
                if let quad { model.confirm(quad) }
                edited = nil
            } label: {
                Text("Usar estas esquinas").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.yellow)
            .foregroundStyle(.black)
            .disabled(quad == nil)

            Divider().overlay(.white.opacity(0.3))

            if model.lenses.count > 1 {
                Text("Lente")
                HStack {
                    ForEach(model.lenses) { lens in
                        Button(lens.name) {
                            edited = nil
                            model.useLens(lens.id)
                        }
                        .buttonStyle(.bordered)
                        .tint(lens.id == model.lensID ? .yellow : .white)
                    }
                }
            }
            if model.controls.maxZoom > 1 {
                Text(String(format: "Zoom %.1f×", model.controls.zoom))
                Slider(
                    value: Binding(get: { model.controls.zoom }, set: { model.setZoom($0) }),
                    in: 1...model.controls.maxZoom,
                    onEditingChanged: { editing in
                        if !editing {
                            edited = nil
                            model.pictureChanged()
                        }
                    })
            }
            if model.controls.maxBias > model.controls.minBias {
                // Darker keeps the bright dialogue box from blowing out; ±3 stops is plenty.
                Text(String(format: "Exposición %+.1f", model.controls.exposureBias))
                Slider(
                    value: Binding(get: { model.controls.exposureBias }, set: { model.setExposureBias($0) }),
                    in: max(model.controls.minBias, -3)...min(model.controls.maxBias, 3))
            }
            Toggle(
                "Bloquear enfoque",
                isOn: Binding(get: { model.controls.focusLocked }, set: { model.setFocusLocked($0) }))
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
                    .stroke(.green, lineWidth: 2)
                    ForEach(0..<4, id: \.self) { index in
                        handle(index, quad: quad, fit: fit)
                    }
                }
            }
        }
        .aspectRatio(1 / aspect, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    /// A corner to drag; the touch target is larger than the dot, for fingers.
    private func handle(_ index: Int, quad: Quad, fit: Double) -> some View {
        let point = [quad.topLeft, quad.topRight, quad.bottomRight, quad.bottomLeft][index]
        return Circle()
            .fill(.green)
            .overlay(Circle().stroke(.white, lineWidth: 2))
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
