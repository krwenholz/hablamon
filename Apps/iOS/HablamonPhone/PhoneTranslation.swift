import SwiftUI
import Translation

/// Translates spoken lines to English on the phone with Apple's Translation framework, as
/// `TranslationDriver` does on the Mac. The first time, iOS asks to download Spanish and English;
/// after that it works offline.
struct PhoneTranslation: ViewModifier {
    var model: PhoneModel
    @State private var configuration: TranslationSession.Configuration?

    func body(content: Content) -> some View {
        content
            .onChange(of: model.state.pendingTranslation, initial: true) { _, pending in
                guard !pending.isEmpty else { return }
                if configuration == nil {
                    configuration = .init(
                        source: Locale.Language(identifier: "es"), target: Locale.Language(identifier: "en"))
                } else {
                    configuration?.invalidate()
                }
            }
            .translationTask(configuration) { @MainActor session in
                // The framework gives this session to this closure only and keeps it alive for its
                // duration, so handing it to `translate` can't race.
                nonisolated(unsafe) let session = session
                if !model.translationReady {
                    let status = await LanguageAvailability().status(
                        from: Locale.Language(identifier: "es"), to: Locale.Language(identifier: "en"))
                    model.note("translation languages: \(status)")
                    do {
                        if status == .supported { try await session.prepareTranslation() }
                        model.translationReady = status != .unsupported
                    } catch {
                        model.translationProblem = true
                        model.note("translation download failed: \(error)")
                        return
                    }
                }
                for source in model.state.pendingTranslation {
                    do {
                        let english = try await session.translate(source).targetText
                        model.state.apply(.translated(source: source, english: english))
                        model.translationProblem = false
                    } catch {
                        model.translationProblem = true
                        model.note("translation failed: \(error)")
                        return
                    }
                }
            }
    }
}
