#if canImport(SwiftUI) && canImport(AVFoundation)
    import CoreImage
    import Foundation
    import HablamonCore
    import SwiftUI
    import Translation
    import _Translation_SwiftUI

    /// Holds the latest replayed frame for the whole-screen translation; written off the main thread.
    final class FrameBox: @unchecked Sendable {
        private let lock = NSLock()
        private var image: CIImage?
        var latest: CIImage? {
            get { lock.withLock { image } }
            set { lock.withLock { image = newValue } }
        }
    }

    extension AppModel {
        func toggleScreenTranslation() {
            if screenOpen { closeScreen() } else { openScreen() }
        }

        func closeScreen() {
            screenOpen = false
            screenTranslation = nil
            screenImage = nil
        }

        /// Snapshots the TV and reads every piece of text on it.
        func openScreen() {
            screenOpen = true
            screenReading = true
            note("screen translation requested")
            if let engine = live?.engine {
                engine.snapshot { image in Task { @MainActor [weak self] in self?.readScreen(image) } }
            } else {
                readScreen(frameBox.latest)
            }
        }

        /// Opens the screen translation on a picture file, for testing with screenshots.
        func openScreen(file: URL) {
            screenOpen = true
            screenReading = true
            // A photo of the room is flattened to the TV first, as the camera would be.
            readScreen(
                CIImage(contentsOf: file, options: [.applyOrientationProperty: true]).map { ScreenReader.flatten($0) })
        }

        private func readScreen(_ frame: CIImage?) {
            guard screenOpen else { return }
            guard let frame, let image = CIContext().createCGImage(frame, from: frame.extent) else {
                screenReading = false
                note("screen translation: no frame yet")
                return
            }
            screenImage = image
            let terms = gameTerms
            Task.detached(priority: .userInitiated) { [weak self] in
                let started = Date()
                let blocks = (try? ScreenReader().read(image)) ?? []
                let elapsed = Date().timeIntervalSince(started)
                await MainActor.run { [weak self] in
                    guard let self, self.screenOpen else { return }
                    self.screenTranslation = terms.map { ScreenTranslation(blocks: blocks, terms: $0) }
                    self.screenReading = false
                    self.note(String(format: "screen translation: %d blocks read in %.2f s", blocks.count, elapsed))
                }
            }
        }
    }

    /// The whole TV frame with English drawn over each piece of Spanish. Escape or T closes it.
    struct ScreenTranslationView: View {
        var model: AppModel
        @State private var configuration: TranslationSession.Configuration?

        var body: some View {
            ZStack {
                Color.black.opacity(0.92).ignoresSafeArea()
                if let image = model.screenImage {
                    GeometryReader { geometry in
                        let size = fitted(image, in: geometry.size)
                        ZStack(alignment: .topLeading) {
                            Image(decorative: image, scale: 1).resizable().frame(width: size.width, height: size.height)
                            if let translation = model.screenTranslation {
                                ForEach(translation.blocks) { block in
                                    label(block, english: translation.english(for: block.id), in: size)
                                }
                            }
                        }
                        .frame(width: size.width, height: size.height)
                        .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
                    }
                    .padding(28)
                }
                VStack {
                    Spacer()
                    Text(status)
                        .font(Theme.menu(14, heavy: false))
                        .foregroundStyle(.white.opacity(0.7))
                        .padding(.bottom, 10)
                }
            }
            .onChange(of: model.screenTranslation?.pending.count ?? 0, initial: true) { _, count in
                guard count > 0 else { return }
                if configuration == nil {
                    configuration = .init(
                        source: Locale.Language(identifier: "es"), target: Locale.Language(identifier: "en"))
                } else {
                    configuration?.invalidate()
                }
            }
            .translationTask(configuration) { @MainActor session in
                // See TranslationDriver: the framework hands this session to this closure only.
                nonisolated(unsafe) let session = session
                for block in model.screenTranslation?.pending ?? [] {
                    guard let english = try? await session.translate(block.text).targetText else { return }
                    model.screenTranslation?.translated(id: block.id, english: english)
                }
            }
        }

        private var status: String {
            if model.screenReading { return "Leyendo la pantalla…" }
            if model.screenImage == nil { return "Todavía no hay imagen de la tele · Esc para cerrar" }
            return "Esc o T para cerrar"
        }

        private func fitted(_ image: CGImage, in space: CGSize) -> CGSize {
            let scale = min(space.width / CGFloat(image.width), space.height / CGFloat(image.height))
            return CGSize(width: CGFloat(image.width) * scale, height: CGFloat(image.height) * scale)
        }

        /// The English sits on a paper label covering the Spanish, sized to the original text.
        private func label(_ block: TextBlock, english: String?, in size: CGSize) -> some View {
            let width = max(block.box.width * size.width + 16, 60)
            let height = max(block.box.height * size.height + 8, 24)
            return Text(english ?? block.text)
                .font(Theme.dialogue(min(height * 0.8, 34), bold: english != nil))
                .foregroundStyle(english == nil ? Theme.muted : Theme.ink)
                .minimumScaleFactor(0.3)
                .lineLimit(nil)
                .multilineTextAlignment(.leading)
                .padding(.horizontal, 6)
                .frame(width: width, height: height, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 6).fill(Theme.paper.opacity(0.94)))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.yellow, lineWidth: 2))
                .offset(x: block.box.x * size.width - 8, y: block.box.y * size.height - 4)
        }
    }
#endif
