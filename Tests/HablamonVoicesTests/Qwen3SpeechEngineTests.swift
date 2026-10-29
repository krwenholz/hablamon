#if canImport(Qwen3TTS) && canImport(AVFoundation)
    import Foundation
    import HablamonCore
    import Testing

    @testable import HablamonVoices

    /// Runs only once the app has downloaded the model, so tests never fetch a gigabyte.
    @Suite(.serialized) struct Qwen3SpeechEngineTests {
        static let models = AppSupportStore().root.appendingPathComponent("models", isDirectory: true)
        static let cached =
            FileManager.default.fileExists(atPath: models.appendingPathComponent(".qwen3-ready").path)
            || FileManager.default.fileExists(atPath: models.appendingPathComponent("qwen3/.ready").path)

        @Test(
            .enabled(
                if: cached && Qwen3SpeechEngine.metalLibraryAvailable(),
                "needs the Qwen3 model downloaded and mlx.metallib beside the test bundle"))
        func speaksAudibly() async throws {
            let library = try VoiceLibrary.bundled()
            let engine = Qwen3SpeechEngine(
                library: library, fallback: AppleSpeechEngine(), modelsDirectory: Self.models)
            try await engine.prepare()
            let clip = try #require(library.clip(named: "Clavel"))
            let samples = try await engine.generate(
                "Gracias por avisarme de algo tan grave.", clip: clip, name: "Clavel")
            let rms = (samples.reduce(0) { $0 + $1 * $1 } / Float(max(1, samples.count))).squareRoot()
            #expect(rms > 0.01, "speech, not near-silence")
        }
    }
#endif
