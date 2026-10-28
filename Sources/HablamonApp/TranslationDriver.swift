#if canImport(SwiftUI) && canImport(Translation)
    import HablamonCore
    import SwiftUI
    import Translation

    /// Translates spoken lines to English on the device with Apple's Translation framework. The first
    /// time, macOS asks to download the Spanish–English languages; after that it works offline.
    struct TranslationDriver: ViewModifier {
        var model: AppModel

        func body(content: Content) -> some View {
            if #available(macOS 15, *) {
                content.modifier(Driver(model: model))
            } else {
                content
            }
        }

        @available(macOS 15, *)
        struct Driver: ViewModifier {
            var model: AppModel
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
                        // The framework gives this session to this closure only and keeps it alive
                        // for its duration, so handing it to `translate` can't race.
                        nonisolated(unsafe) let session = session
                        if !model.translationReady {
                            let status = await LanguageAvailability().status(
                                from: Locale.Language(identifier: "es"), to: Locale.Language(identifier: "en"))
                            model.note("translation languages: \(status)")
                            do {
                                // Shows macOS's download prompt the first time; offline afterwards.
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
    }
#else
    import SwiftUI

    struct TranslationDriver: ViewModifier {
        var model: AppModel
        func body(content: Content) -> some View { content }
    }
#endif
