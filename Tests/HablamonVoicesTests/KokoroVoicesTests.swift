import HablamonModels
import Testing

@testable import HablamonVoices

@Suite struct KokoroVoicesTests {
    @Test func everyDesignedVoiceHasAKokoroStyle() throws {
        let styles = try KokoroVoices.bundled()
        let library = try VoiceLibrary.bundled()
        #expect(Set(styles.keys) == library.names)
        for (name, style) in styles {
            #expect(style.count == KokoroStyles.styleLength, "\(name)")
        }
    }
}

#if canImport(CoreML) && canImport(AVFoundation)
    import Foundation
    import HablamonCore

    /// Runs only once the app has downloaded the model, so tests never fetch 312 MB.
    @Suite(.serialized) struct KokoroSpeechEngineTests {
        static let models = AppSupportStore().root.appendingPathComponent("models", isDirectory: true)
        static let cached = FileManager.default.fileExists(
            atPath: models.appendingPathComponent("kokoro/.ready").path)

        @Test(.enabled(if: cached, "Kokoro isn't downloaded yet; launch the app with engine kokoro once"))
        func speaksALineInACharactersVoice() async throws {
            let engine = KokoroSpeechEngine(
                library: try VoiceLibrary.bundled(), fallback: AppleSpeechEngine(), modelsDirectory: Self.models)
            try await engine.prepare()
            let line = "¡Has obtenido una Poción! La guardas en el bolsillo de Medicinas."
            let started = Date()
            let samples = try #require(try await engine.synthesize(line, voice: "narrator"))
            let seconds = Double(samples.count) / KokoroSpeechEngine.sampleRate
            #expect(seconds > 3 && seconds < 9)
            #expect(Date().timeIntervalSince(started) < 2)
            #expect(try await engine.synthesize(line, voice: "nobody") == nil)
        }
    }
#endif
