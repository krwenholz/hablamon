#if canImport(Qwen3TTS) && canImport(AVFoundation)
    @preconcurrency import AVFoundation
    import AudioCommon
    import Foundation
    import HablamonCore
    import HablamonModels
    import Qwen3TTS

    /// Speaks each line in its character's designed voice by cloning the bundled reference clip with
    /// Qwen3-TTS (0.6B Base) on the GPU. Until the model has downloaded and loaded, or for a voice
    /// without a clip, it hands the line to `fallback` (the Apple voice) so speech never stops.
    public final class Qwen3SpeechEngine: CharacterVoiceEngine, @unchecked Sendable {
        public let id: SpeechEngineID = .qwen3
        public let displayName = "Qwen3"
        public static let modelID = "aufklarer/Qwen3-TTS-12Hz-0.6B-Base-MLX-8bit"
        static let sampleRate = 24_000.0

        public var onStatus: (@Sendable (VoiceModelStatus) -> Void)?
        public var onLog: (@Sendable (String) -> Void)?

        private let library: VoiceLibrary
        private let fallback: any SpeechEngine
        private let modelsDirectory: URL
        // The model runs on one serial queue; MLX state isn't safe to share across threads.
        private let queue = DispatchQueue(label: "hablamon.qwen3", qos: .userInitiated)
        private let lock = NSLock()
        private var model: Qwen3TTSModel?
        private var references: [String: [Float]] = [:]
        private var status: VoiceModelStatus = .notLoaded

        private let player = ChunkPlayer(sampleRate: Qwen3SpeechEngine.sampleRate)

        public init(library: VoiceLibrary, fallback: any SpeechEngine, modelsDirectory: URL) {
            self.library = library
            self.fallback = fallback
            self.modelsDirectory = modelsDirectory
        }

        var isReady: Bool { lock.withLock { status == .ready } }

        /// Downloads the model the first time (about 1 GB) and loads it. Safe to call more than once.
        public func prepare() async throws {
            let start = lock.withLock { () -> Bool in
                guard status == .notLoaded || { if case .failed = status { true } else { false } }() else {
                    return false
                }
                status = .loading
                return true
            }
            guard start else { return }
            // MLX aborts the whole process if its shaders are missing, so check before touching it.
            guard Self.metalLibraryAvailable() else {
                let reason = "MLX's Metal shaders are missing (run `mise run metallib`, or reinstall)"
                lock.withLock { status = .failed(reason) }
                report(.failed(reason))
                throw CocoaError(.fileNoSuchFile, userInfo: [NSLocalizedDescriptionKey: reason])
            }
            report(.loading)
            // The model and its speech tokenizer each need their own folder: given one folder for
            // both, speech-swift takes the model's weights for the tokenizer's and speaks silence.
            let modelDirectory = modelsDirectory.appendingPathComponent("qwen3", isDirectory: true)
            let tokenizerDirectory = modelsDirectory.appendingPathComponent("qwen3-tokenizer", isDirectory: true)
            let marker = modelDirectory.appendingPathComponent(".ready")
            do {
                try Self.moveSharedFolderDownload(from: modelsDirectory, to: modelDirectory)
                let cached = FileManager.default.fileExists(atPath: marker.path)
                try FileManager.default.createDirectory(at: modelDirectory, withIntermediateDirectories: true)
                let loaded = try await Qwen3TTSModel.fromPretrained(
                    modelId: Self.modelID, cacheDir: modelDirectory, tokenizerCacheDir: tokenizerDirectory,
                    offlineMode: cached,
                    progressHandler: { [weak self] fraction, _ in
                        if !cached { self?.report(.downloading(fraction)) }
                    })
                FileManager.default.createFile(atPath: marker.path, contents: nil)
                lock.withLock {
                    model = loaded
                    status = .ready
                }
                report(.ready)
            } catch {
                lock.withLock { status = .failed("\(error)") }
                report(.failed("\(error)"))
                throw error
            }
        }

        /// Builds before the fix downloaded the model straight into `models/`; move it into its own
        /// folder rather than fetching 1.2 GB again. The tokenizer was never downloaded, so it will be.
        static func moveSharedFolderDownload(from models: URL, to modelDirectory: URL) throws {
            let files = FileManager.default
            guard files.fileExists(atPath: models.appendingPathComponent("model.safetensors").path),
                !files.fileExists(atPath: modelDirectory.path)
            else { return }
            try files.createDirectory(at: modelDirectory, withIntermediateDirectories: true)
            for name in [
                "config.json", "merges.txt", "model.safetensors", "model.safetensors.index.json",
                "tokenizer_config.json", "vocab.json",
            ] where files.fileExists(atPath: models.appendingPathComponent(name).path) {
                try files.moveItem(
                    at: models.appendingPathComponent(name), to: modelDirectory.appendingPathComponent(name))
            }
            try? files.removeItem(at: models.appendingPathComponent(".qwen3-ready"))
        }

        /// Whether MLX will find its shaders: next to the executable, in `Resources/` beside it, or as
        /// `default.metallib` in MLX's resource bundle inside the app (where the install puts them).
        static func metalLibraryAvailable() -> Bool {
            let executable = Bundle.main.executableURL?.deletingLastPathComponent()
            var candidates = [
                executable?.appendingPathComponent("mlx.metallib"),
                executable?.appendingPathComponent("Resources/mlx.metallib"),
            ]
            // MLX also looks beside the binary its code is linked into, which in tests is the test bundle.
            var image = Dl_info()
            if dladdr(#dsohandle, &image) != 0, let path = image.dli_fname {
                candidates.append(
                    URL(fileURLWithPath: String(cString: path)).deletingLastPathComponent()
                        .appendingPathComponent("mlx.metallib"))
            }
            for bundle in [Bundle.main] + Bundle.allBundles {
                candidates.append(
                    bundle.resourceURL?.appendingPathComponent(
                        "mlx-swift_Cmlx.bundle/Contents/Resources/default.metallib"))
                candidates.append(bundle.resourceURL?.appendingPathComponent("mlx-swift_Cmlx.bundle/default.metallib"))
            }
            return candidates.compactMap { $0 }.contains { FileManager.default.fileExists(atPath: $0.path) }
        }

        public func speak(_ text: String, voice: VoicePlan, rate: Double) async throws {
            try await speak(text, voice: voice, rate: rate, progress: { _ in })
        }

        public func speak(
            _ text: String, voice: VoicePlan, rate: Double, progress: @escaping @Sendable (Int) -> Void
        ) async throws {
            guard isReady, let name = voice.clip, let clip = library.clip(named: name) else {
                try await fallback.speak(text, voice: voice, rate: rate, progress: progress)
                return
            }
            // Generate sentence by sentence and start playing the first while the rest generate.
            let started = Date()
            do {
                let timing = try await player.play(
                    text, chunks: SpeechChunker.chunks(text), rate: rate, progress: progress
                ) { chunk in
                    try await generate(chunk, clip: clip, name: name)
                }
                onLog?(
                    String(
                        format: "qwen3 %@: first audio after %.2f s, %.2f s generating", name, timing.firstAudio,
                        timing.generating))
            } catch is CancellationError {
                onLog?(String(format: "qwen3 %@: interrupted after %.2f s", name, Date().timeIntervalSince(started)))
                throw CancellationError()
            }
        }

        public func stop() async {
            // Stopping the player calls the queued buffers' completions, which finishes the line.
            player.stop()
            await fallback.stop()
        }

        // MARK: Generation

        func generate(_ text: String, clip: VoiceLibrary.Clip, name: String) async throws -> [Float] {
            try await withCheckedThrowingContinuation { continuation in
                queue.async { [self] in
                    do {
                        guard let model = lock.withLock({ self.model }) else { throw CancellationError() }
                        let reference = try referenceAudio(for: name, clip: clip)
                        // Plain cloning (speaker embedding) was faster and steadier than cloning that
                        // also imitates the clip's delivery; the cap stops a line that runs on.
                        var sampling = SamplingConfig.default
                        sampling.maxTokens = SpeechBudget.maxFrames(for: text)
                        let samples = model.synthesizeWithVoiceClone(
                            text: text, referenceAudio: reference, language: "spanish", sampling: sampling)
                        continuation.resume(returning: samples)
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
        }

        /// Reference clips are decoded once and kept; the model also caches their encodings.
        private func referenceAudio(for name: String, clip: VoiceLibrary.Clip) throws -> [Float] {
            if let cached = references[name] { return cached }
            let samples = try AudioFileLoader.load(url: clip.url, targetSampleRate: Int(Self.sampleRate))
            references[name] = samples
            return samples
        }

        private func report(_ status: VoiceModelStatus) {
            onStatus?(status)
        }
    }

#endif
