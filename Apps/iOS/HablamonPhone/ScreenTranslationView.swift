import CoreImage
import HablamonCore
import SwiftUI
import Translation

/// Holds the latest replayed frame for the whole-screen translation; written off the main thread.
/// A copy of the Mac's; phase 3 shares it.
final class FrameBox: @unchecked Sendable {
    private let lock = NSLock()
    private var image: CIImage?
    var latest: CIImage? {
        get { lock.withLock { image } }
        set { lock.withLock { image = newValue } }
    }
}

/// The whole TV picture with English drawn over each piece of Spanish, as T shows on the Mac. Game
/// terms show at once; the rest fills in from Apple's Translation, or stays in Spanish, greyed,
/// when translation isn't available. Tap anywhere to close.
struct ScreenTranslationView: View {
    var model: PhoneModel
    @State private var configuration: TranslationSession.Configuration?

    var body: some View {
        VStack(spacing: 8) {
            if let image = model.screenImage {
                GeometryReader { geometry in
                    let size = fitted(image, in: geometry.size)
                    ZStack(alignment: .topLeading) {
                        Image(decorative: image, scale: 1).resizable().frame(width: size.width, height: size.height)
                        if let translation = model.screenTranslation {
                            ForEach(translation.blocks) { block in
                                label(block, in: translation, size: size)
                            }
                        }
                    }
                    .frame(width: size.width, height: size.height)
                    .clipped()
                    .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
                }
            } else {
                Spacer()
                if model.screenReading { ProgressView().tint(.white) }
                Spacer()
            }
            Text(status)
                .font(Theme.menu(14, heavy: false))
                .foregroundStyle(.white.opacity(0.75))
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 8)
        .padding(.top, 44)
        .padding(.bottom, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.ignoresSafeArea())
        .overlay(alignment: .topTrailing) {
            Button("Cerrar", systemImage: "xmark") { model.closeScreen() }
                .labelStyle(.iconOnly)
                .buttonStyle(PillButtonStyle(padding: 12))
                .padding(.trailing, 12)
                .padding(.top, 4)
        }
        .contentShape(Rectangle())
        .onTapGesture { model.closeScreen() }
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
            // See PhoneTranslation: the framework hands this session to this closure only.
            nonisolated(unsafe) let session = session
            if !model.translationReady {
                let status = await LanguageAvailability().status(
                    from: Locale.Language(identifier: "es"), to: Locale.Language(identifier: "en"))
                if status == .unsupported {
                    giveUp("translation languages: \(status)")
                    return
                }
                do {
                    if status == .supported { try await session.prepareTranslation() }
                    model.translationReady = true
                } catch {
                    if !Task.isCancelled { giveUp("translation download failed: \(error)") }
                    return
                }
            }
            for block in model.screenTranslation?.pending ?? [] {
                do {
                    let english = try await session.translate(block.text).targetText
                    model.screenTranslation?.translated(id: block.id, english: english)
                } catch {
                    if !Task.isCancelled { giveUp("screen translation failed: \(error)") }
                    return
                }
            }
        }
    }

    /// Stops waiting, so the blocks without a game term say they won't be translated.
    private func giveUp(_ reason: String) {
        model.note(reason)
        model.screenTranslation?.translationUnavailable()
    }

    private var status: String {
        if model.screenReading { return "Leyendo la pantalla…" }
        guard model.screenImage != nil else { return "Todavía no hay imagen de la tele · Toca para cerrar" }
        guard let translation = model.screenTranslation else { return "Toca para cerrar" }
        if translation.blocks.isEmpty { return "No hay texto en la pantalla · Toca para cerrar" }
        if translation.unavailable && !translation.untranslated.isEmpty {
            return "Traducción no disponible: solo los nombres del juego · Toca para cerrar"
        }
        if !translation.pending.isEmpty { return "Traduciendo… · Toca para cerrar" }
        return "Toca para cerrar"
    }

    private func fitted(_ image: CGImage, in space: CGSize) -> CGSize {
        let scale = min(space.width / CGFloat(image.width), space.height / CGFloat(image.height))
        return CGSize(width: CGFloat(image.width) * scale, height: CGFloat(image.height) * scale)
    }

    /// The English sits on a paper label covering the Spanish, sized to the original text, as on the
    /// Mac. A block still waiting shows its Spanish greyed; one that won't be translated keeps its
    /// Spanish on a grey-edged label. Copied from the Mac's view; phase 3 shares it.
    private func label(_ block: TextBlock, in translation: ScreenTranslation, size: CGSize) -> some View {
        let english = translation.english(for: block.id)
        let untranslatable = english == nil && translation.unavailable
        let width = max(block.box.width * size.width + 10, 40)
        let height = max(block.box.height * size.height + 6, 16)
        return Text(english ?? block.text)
            .font(Theme.dialogue(min(height * 0.8, 28), bold: english != nil))
            .foregroundStyle(english != nil ? Theme.ink : untranslatable ? Theme.faint : Theme.unspoken)
            .minimumScaleFactor(0.3)
            .lineLimit(nil)
            .multilineTextAlignment(.leading)
            .padding(.horizontal, 4)
            .frame(width: width, height: height, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 5).fill(Theme.paper.opacity(untranslatable ? 0.85 : 0.94)))
            .overlay(
                RoundedRectangle(cornerRadius: 5).stroke(untranslatable ? Theme.unspoken : Theme.yellow, lineWidth: 2)
            )
            .offset(x: block.box.x * size.width - 5, y: block.box.y * size.height - 3)
    }
}
