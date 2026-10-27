#if canImport(SwiftUI) && canImport(AVFoundation)
    import HablamonCore
    import HablamonModels
    import SwiftUI

    /// The camera's view with the proposed TV corners, which the player can drag and accept.
    struct CalibrationPanel: View {
        var preview: CalibrationPreview?
        var status: String?
        var english: Bool
        var onConfirm: (Quad) -> Void
        var onClose: () -> Void
        /// Corners in camera pixels once the player starts dragging; until then, the proposal.
        @State private var edited: Quad?

        private var quad: Quad? { edited ?? preview?.proposal }

        var body: some View {
            InkCard(title: text(.calibration, english: english), detail: nil) {
                VStack(alignment: .leading, spacing: 12) {
                    if let preview {
                        frame(preview)
                        Text(text(.dragCorners, english: english))
                            .font(Theme.menu(13, heavy: false)).foregroundStyle(Color(hex: 0x45444C))
                        if let quality = preview.quality {
                            Text(String(format: "Texto: %.0f px", quality.textHeight))
                                .font(Theme.menu(14, heavy: false)).foregroundStyle(Theme.ink)
                            ForEach(quality.warnings, id: \.self) { warning in
                                Text(warning).font(Theme.menu(13, heavy: false)).foregroundStyle(Theme.scarlet)
                            }
                        }
                        Button {
                            if let quad { onConfirm(quad) }
                            edited = nil
                        } label: {
                            Text(text(.useCorners, english: english) + " ⏎")
                                .font(Theme.menu(15))
                                .foregroundStyle(Theme.ink)
                                .padding(.horizontal, 16).padding(.vertical, 8)
                                .background(Capsule().fill(Theme.yellow))
                        }
                        .buttonStyle(.plain)
                        .keyboardShortcut(.defaultAction)
                        .disabled(quad == nil)
                    } else {
                        Text(status ?? text(.waitingForPhone, english: english))
                            .font(Theme.menu(16, heavy: false)).foregroundStyle(Theme.muted)
                    }
                }
                .padding(16)
            }
            .overlay(alignment: .topTrailing) { CloseButton(action: onClose) }
        }

        private func frame(_ preview: CalibrationPreview) -> some View {
            let image = preview.image
            let aspect = Double(image.height) / Double(image.width)
            return GeometryReader { geometry in
                // View points per camera pixel.
                let fit = geometry.size.width / Double(image.width) * preview.scale
                ZStack(alignment: .topLeading) {
                    Image(decorative: image, scale: 1).resizable().frame(
                        width: geometry.size.width, height: geometry.size.width * aspect)
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
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }

        private func handle(_ index: Int, quad: Quad, fit: Double) -> some View {
            let point = [quad.topLeft, quad.topRight, quad.bottomRight, quad.bottomLeft][index]
            return Circle()
                .fill(Theme.green)
                .overlay(Circle().stroke(.white, lineWidth: 2))
                .frame(width: 16, height: 16)
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
#endif
