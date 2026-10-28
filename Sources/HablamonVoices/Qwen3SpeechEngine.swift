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
        private var finished: CheckedContinuation<Void, Never>?

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
            let marker = modelsDirectory.appendingPathComponent(".qwen3-ready")
            let cached = FileManager.default.fileExists(atPath: marker.path)
            do {
                try FileManager.default.createDirectory(at: modelsDirectory, withIntermediateDirectories: true)
                let loaded = try await Qwen3TTSModel.fromPretrained(
                    modelId: Self.modelID, cacheDir: modelsDirectory, tokenizerCacheDir: modelsDirectory,
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

        /// Whether MLX will find its shaders: next to the executable, in `Resources/` beside it, or as
        /// `default.metallib` in MLX's resource bundle inside the app (where the install puts them).
        static func metalLibraryAvailable() -> Bool {
            let executable = Bundle.main.executableURL?.deletingLastPathComponent()
            var candidates = [
                executable?.appendingPathComponent("mlx.metallib"),
                executable?.appendingPathComponent("Resources/mlx.metallib"),
            ]
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
            let started = Date()
            let samples = try await generate(text, clip: clip, name: name)
            if Task.isCancelled {
                onLog?(String(format: "qwen3 %@: interrupted after %.2f s", name, Date().timeIntervalSince(started)))
                throw CancellationError()
            }
            let seconds = Double(samples.count) / Self.sampleRate
            onLog?(
                String(format: "qwen3 %@: %.2f s to make %.2f s", name, Date().timeIntervalSince(started), seconds))
            await play(samples, rate: rate, text: text, progress: progress)
        }

        public func stop() async {
            player.stop()
            let waiting = lock.withLock { () -> CheckedContinuation<Void, Never>? in
                defer { finished = nil }
                return finished
            }
            waiting?.resume()
            await fallback.stop()
        }

        // MARK: Generation

        private func generate(_ text: String, clip: VoiceLibrary.Clip, name: String) async throws -> [Float] {
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

        /// Plays at `rate` without changing pitch, reporting word progress until done or stopped.
        private func play(_ samples: [Float], rate: Double, text: String, progress: @escaping @Sendable (Int) -> Void)
            async
        {
            guard !samples.isEmpty,
                let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count))
            else { return }
            buffer.frameLength = AVAudioFrameCount(samples.count)
            samples.withUnsafeBufferPointer { source in
                buffer.floatChannelData![0].update(from: source.baseAddress!, count: samples.count)
            }
            timePitch.rate = Float(min(max(rate, 0.5), 2.0))
            if !audio.isRunning { try? audio.start() }

            let total = Double(samples.count)
            let ticker = Task { [self] in
                while !Task.isCancelled {
                    if let nodeTime = player.lastRenderTime, let time = player.playerTime(forNodeTime: nodeTime) {
                        progress(PlaybackProgress.offset(fraction: Double(time.sampleTime) / total, in: text))
                    }
                    try? await Task.sleep(for: .milliseconds(100))
                }
            }
            await withTaskCancellationHandler {
                await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                    lock.withLock { finished = continuation }
                    player.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { [weak self] _ in
                        guard let self else { return }
                        let waiting = self.lock.withLock { () -> CheckedContinuation<Void, Never>? in
                            defer { self.finished = nil }
                            return self.finished
                        }
                        waiting?.resume()
                    }
                    player.play()
                }
            } onCancel: { [self] in
                player.stop()
            }
            ticker.cancel()
            progress(text.utf16.count)
        }

        private func report(_ status: Status) {
            onStatus?(status)
        }
    }
#endif
