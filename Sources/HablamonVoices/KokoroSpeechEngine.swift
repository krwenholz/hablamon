#if canImport(CoreML) && canImport(AVFoundation)
    import AudioCommon
    import CoreML
    import Foundation
    import HablamonCore
    import HablamonModels

    /// Speaks each line in its character's voice with Kokoro-82M on the Neural Engine: a whole line
    /// takes a few tenths of a second, several times faster than Qwen3, from a 312 MB model.
    ///
    /// The character voices are Kokoro styles cloned from the Qwen3 reference clips. Text goes
    /// through `SpanishPhonemes` rather than speech-swift's Kokoro wrapper, whose Spanish rules
    /// put the stress on the wrong syllable and drop the soft b, d, and g Kokoro was trained on.
    public final class KokoroSpeechEngine: CharacterVoiceEngine, @unchecked Sendable {
        public let id: SpeechEngineID = .kokoro
        public let displayName = "Kokoro"
        public static let modelID = "aufklarer/Kokoro-82M-CoreML"
        static let sampleRate = 24_000.0
        /// Input slots of the model (`input_ids` is `[1, 128]`).
        static let inputSlots = 128
        /// Phonemes per pass, which at Kokoro's rate (~10 a second) fit the model's 5 s of output.
        static let phonemesPerPass = 54

        public var onStatus: (@Sendable (VoiceModelStatus) -> Void)?
        public var onLog: (@Sendable (String) -> Void)?

        private let fallback: any SpeechEngine
        private let directory: URL
        // CoreML predictions run one at a time on this queue.
        private let queue = DispatchQueue(label: "hablamon.kokoro", qos: .userInitiated)
        private let lock = NSLock()
        private var model: MLModel?
        private var vocabulary: [Character: Int32] = [:]
        private var styles: [String: [Float]] = [:]
        private var pronunciations: [String: String] = [:]
        private var status: VoiceModelStatus = .notLoaded
        private let player = ChunkPlayer(sampleRate: KokoroSpeechEngine.sampleRate)

        public init(fallback: any SpeechEngine, modelsDirectory: URL) {
            self.fallback = fallback
            directory = modelsDirectory.appendingPathComponent("kokoro", isDirectory: true)
        }

        var isReady: Bool { lock.withLock { status == .ready } }

        /// Downloads the model the first time and loads it. Safe to call more than once.
        public func prepare() async throws {
            let start = lock.withLock { () -> Bool in
                guard status == .notLoaded || { if case .failed = status { true } else { false } }() else {
                    return false
                }
                status = .loading
                return true
            }
            guard start else { return }
            report(.loading)
            let marker = directory.appendingPathComponent(".ready")
            do {
                if !FileManager.default.fileExists(atPath: marker.path) {
                    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                    try await HuggingFaceDownloader.downloadWeights(
                        modelId: Self.modelID, to: directory,
                        additionalFiles: ["kokoro_5s.mlmodelc/**", "vocab_index.json"]
                    ) { [weak self] fraction in self?.report(.downloading(fraction)) }
                    FileManager.default.createFile(atPath: marker.path, contents: nil)
                    report(.loading)
                }
                let vocabulary = try Self.loadVocabulary(directory.appendingPathComponent("vocab_index.json"))
                let configuration = MLModelConfiguration()
                configuration.computeUnits = .all
                let model = try MLModel(
                    contentsOf: directory.appendingPathComponent("kokoro_5s.mlmodelc"), configuration: configuration)
                let styles = try KokoroVoices.bundled()
                let pronunciations = try SpanishPhonemes.bundledPronunciations()
                lock.withLock {
                    self.pronunciations = pronunciations
                    self.model = model
                    self.vocabulary = vocabulary
                    self.styles = styles
                }
                // The first prediction compiles for the Neural Engine; pay for it now, not on a line.
                if let style = styles.values.first { _ = try await render("ˈola", style: style) }
                lock.withLock { status = .ready }
                report(.ready)
            } catch {
                lock.withLock { status = .failed("\(error)") }
                report(.failed("\(error)"))
                throw error
            }
        }

        public func speak(_ text: String, voice: VoicePlan, rate: Double) async throws {
            try await speak(text, voice: voice, rate: rate, progress: { _ in })
        }

        public func speak(
            _ text: String, voice: VoicePlan, rate: Double, progress: @escaping @Sendable (Int) -> Void
        ) async throws {
            guard isReady, let name = voice.clip, let style = lock.withLock({ styles[name] }) else {
                try await fallback.speak(text, voice: voice, rate: rate, progress: progress)
                return
            }
            let started = Date()
            do {
                let timing = try await player.play(
                    text, chunks: SpeechChunker.chunks(text), rate: rate, progress: progress
                ) { chunk in
                    try await synthesize(chunk, style: style)
                }
                onLog?(
                    String(
                        format: "kokoro %@: first audio after %.2f s, %.2f s generating", name, timing.firstAudio,
                        timing.generating))
            } catch is CancellationError {
                onLog?(String(format: "kokoro %@: interrupted after %.2f s", name, Date().timeIntervalSince(started)))
                throw CancellationError()
            }
        }

        public func stop() async {
            player.stop()
            await fallback.stop()
        }

        // MARK: Rendering

        /// Speech for `text` in the voice called `name`, or nil if there's no such voice.
        func synthesize(_ text: String, voice name: String) async throws -> [Float]? {
            guard let style = lock.withLock({ styles[name] }) else { return nil }
            return try await synthesize(text, style: style)
        }

        private func synthesize(_ text: String, style: [Float]) async throws -> [Float] {
            var samples: [Float] = []
            let phonemes = SpanishPhonemes.phonemize(text, pronunciations: lock.withLock { pronunciations })
            for piece in SpanishPhonemes.pieces(phonemes, maxLength: Self.phonemesPerPass) {
                samples += try await render(piece, style: style)
            }
            return samples
        }

        /// One pass of the model: phonemes in, 24 kHz speech out.
        private func render(_ phonemes: String, style: [Float]) async throws -> [Float] {
            try await withCheckedThrowingContinuation { continuation in
                queue.async { [self] in
                    do {
                        continuation.resume(returning: try predict(phonemes, style: style))
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
        }

        private func predict(_ phonemes: String, style: [Float]) throws -> [Float] {
            guard let model = lock.withLock({ self.model }) else { throw CancellationError() }
            let vocabulary = lock.withLock { self.vocabulary }
            // Start and end of text are both token 0; unknown symbols are skipped.
            let tokens = Array(([0] + phonemes.compactMap { vocabulary[$0] }).prefix(Self.inputSlots - 1)) + [0]
            let ids = try MLMultiArray(shape: [1, NSNumber(value: Self.inputSlots)], dataType: .int32)
            let mask = try MLMultiArray(shape: [1, NSNumber(value: Self.inputSlots)], dataType: .int32)
            for slot in 0..<Self.inputSlots {
                ids[slot] = NSNumber(value: slot < tokens.count ? tokens[slot] : 0)
                mask[slot] = NSNumber(value: slot < tokens.count ? 1 : 0)
            }
            let reference = try MLMultiArray(shape: [1, NSNumber(value: style.count)], dataType: .float32)
            for (index, value) in style.enumerated() { reference[index] = NSNumber(value: value) }
            let phases = try MLMultiArray(shape: [1, 9], dataType: .float32)
            for index in 0..<9 { phases[index] = NSNumber(value: Float.random(in: 0..<1)) }
            let speed = try MLMultiArray(shape: [1], dataType: .float32)
            speed[0] = 1
            let output = try model.prediction(
                from: MLDictionaryFeatureProvider(dictionary: [
                    "input_ids": ids, "attention_mask": mask, "ref_s": reference, "random_phases": phases,
                    "speed": speed,
                ]))
            guard let audio = output.featureValue(for: "audio")?.multiArrayValue,
                let length = output.featureValue(for: "audio_length_samples")?.multiArrayValue
            else { throw CocoaError(.coderValueNotFound) }
            let count = min(max(0, length[0].intValue), audio.count)
            let samples = (0..<count).map { audio[$0].floatValue }
            return SpeechAudio.trimmingTrailingNoise(samples, sampleRate: Int(Self.sampleRate))
        }

        /// `vocab_index.json`: `{"vocab": {"phoneme": id}}`.
        private static func loadVocabulary(_ url: URL) throws -> [Character: Int32] {
            struct File: Decodable { var vocab: [String: Int32] }
            let file = try JSONDecoder().decode(File.self, from: Data(contentsOf: url))
            var vocabulary: [Character: Int32] = [:]
            for (symbol, id) in file.vocab where symbol.count == 1 { vocabulary[symbol.first!] = id }
            return vocabulary
        }

        private func report(_ status: VoiceModelStatus) {
            onStatus?(status)
        }
    }
#endif
