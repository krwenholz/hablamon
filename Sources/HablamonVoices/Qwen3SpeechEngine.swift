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
    public final class Qwen3SpeechEngine: SpeechEngine, @unchecked Sendable {
        public enum Status: Equatable, Sendable {
            case notLoaded
            /// Downloading the model the first time (0–1).
            case downloading(Double)
            case loading
            case ready
            case failed(String)
        }

        public let id: SpeechEngineID = .qwen3
        public static let modelID = "aufklarer/Qwen3-TTS-12Hz-0.6B-Base-MLX-8bit"
        static let sampleRate = 24_000.0

        /// Called on any thread when the model's status changes.
        public var onStatus: (@Sendable (Status) -> Void)?
        /// Called with a line for the session log after each spoken line (generation time and length).
        public var onLog: (@Sendable (String) -> Void)?

        private let library: VoiceLibrary
        private let fallback: any SpeechEngine
        private let modelsDirectory: URL
        // The model runs on one serial queue; MLX state isn't safe to share across threads.
        private let queue = DispatchQueue(label: "hablamon.qwen3", qos: .userInitiated)
        private let lock = NSLock()
        private var model: Qwen3TTSModel?
        private var references: [String: [Float]] = [:]
        private var status: Status = .notLoaded

        private let audio = AVAudioEngine()
        private let player = AVAudioPlayerNode()
        private let timePitch = AVAudioUnitTimePitch()
        private let format = AVAudioFormat(standardFormatWithSampleRate: 24_000, channels: 1)!

        public init(library: VoiceLibrary, fallback: any SpeechEngine, modelsDirectory: URL) {
            self.library = library
            self.fallback = fallback
            self.modelsDirectory = modelsDirectory
            audio.attach(player)
            audio.attach(timePitch)
            audio.connect(player, to: timePitch, format: format)
            audio.connect(timePitch, to: audio.mainMixerNode, format: format)
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
            let chunks = SpeechChunker.chunks(text)
            let offsets = SpeechChunker.offsets(of: chunks, in: text)
            let started = Date()
            let playback = Playback(text: text, chunks: chunks, offsets: offsets)
            player.stop()
            timePitch.rate = Float(min(max(rate, 0.5), 2.0))
            if !audio.isRunning { try? audio.start() }
            let ticker = Task { [self] in
                while !Task.isCancelled {
                    if let nodeTime = player.lastRenderTime, let time = player.playerTime(forNodeTime: nodeTime) {
                        progress(playback.offset(atSample: Int(time.sampleTime)))
                    }
                    try? await Task.sleep(for: .milliseconds(100))
                }
            }
            defer { ticker.cancel() }
            var firstAudio: TimeInterval?
            for (index, chunk) in chunks.enumerated() {
                let samples = try await generate(chunk, clip: clip, name: name)
                if Task.isCancelled {
                    player.stop()
                    onLog?(
                        String(format: "qwen3 %@: interrupted after %.2f s", name, Date().timeIntervalSince(started)))
                    throw CancellationError()
                }
                schedule(samples, last: index == chunks.count - 1, playback: playback)
                if firstAudio == nil {
                    firstAudio = Date().timeIntervalSince(started)
                    player.play()
                }
            }
            onLog?(
                String(
                    format: "qwen3 %@: first audio after %.2f s, %d part(s), %.2f s generating", name, firstAudio ?? 0,
                    chunks.count, Date().timeIntervalSince(started)))
            await withTaskCancellationHandler {
                await playback.finished()
            } onCancel: { [self] in
                player.stop()
                playback.finish()
            }
            progress(text.utf16.count)
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

        // MARK: Playback

        /// Queues a generated piece after whatever is already playing.
        private func schedule(_ samples: [Float], last: Bool, playback: Playback) {
            guard !samples.isEmpty,
                let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count))
            else {
                if last { playback.finish() }
                return
            }
            buffer.frameLength = AVAudioFrameCount(samples.count)
            samples.withUnsafeBufferPointer { source in
                buffer.floatChannelData![0].update(from: source.baseAddress!, count: samples.count)
            }
            playback.add(samples: samples.count)
            player.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { _ in
                if last { playback.finish() }
            }
        }

        /// Tracks the pieces of one line as they're queued, to map playback position to a word and to
        /// know when the last piece has played.
        final class Playback: @unchecked Sendable {
            private let lock = NSLock()
            private let text: String
            private let chunks: [String]
            private let offsets: [Int]
            private var ends: [Int] = []
            private var done = false
            private var waiting: CheckedContinuation<Void, Never>?

            init(text: String, chunks: [String], offsets: [Int]) {
                self.text = text
                self.chunks = chunks
                self.offsets = offsets
            }

            func add(samples: Int) {
                lock.withLock { ends.append((ends.last ?? 0) + samples) }
            }

            /// The word being spoken at `sample` samples into the line.
            func offset(atSample sample: Int) -> Int {
                lock.withLock {
                    guard let index = ends.firstIndex(where: { sample < $0 }), index < chunks.count else {
                        return ends.count == chunks.count ? text.utf16.count : (offsets[safe: ends.count] ?? 0)
                    }
                    let start = index == 0 ? 0 : ends[index - 1]
                    let fraction = Double(sample - start) / Double(max(1, ends[index] - start))
                    return offsets[index] + PlaybackProgress.offset(fraction: fraction, in: chunks[index])
                }
            }

            func finish() {
                let continuation = lock.withLock { () -> CheckedContinuation<Void, Never>? in
                    done = true
                    defer { waiting = nil }
                    return waiting
                }
                continuation?.resume()
            }

            func finished() async {
                await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                    let alreadyDone = lock.withLock { () -> Bool in
                        if done { return true }
                        waiting = continuation
                        return false
                    }
                    if alreadyDone { continuation.resume() }
                }
            }
        }

        private func report(_ status: Status) {
            onStatus?(status)
        }
    }

    extension Array {
        subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
    }
#endif
