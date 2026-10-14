import HablamonModels

/// A text-to-speech backend. The Apple engine is always available; others can be swapped in.
public protocol SpeechEngine: Sendable {
    var id: SpeechEngineID { get }
    /// Loads models; may take seconds.
    func prepare() async throws
    /// Speaks `text` and returns when it finishes or is stopped.
    func speak(_ text: String, voice: VoicePlan, rate: Double) async throws
    /// Interrupts speech immediately.
    func stop() async
}

/// Speaks pages one at a time: a new page interrupts the current one, so lines never pile up.
/// If the chosen engine fails, it switches to the fallback engine for the rest of the session.
public actor Narrator {
    public private(set) var engine: any SpeechEngine
    private let fallback: any SpeechEngine
    /// Global speed multiplier (the slow default helps listening practice).
    public var speed: Double
    public private(set) var warnings: [String] = []
    private var current: Task<Void, Never>?
    private var generation = 0

    public init(engine: any SpeechEngine, fallback: any SpeechEngine, speed: Double = 0.85) {
        self.engine = engine
        self.fallback = fallback
        self.speed = speed
    }

    public func setSpeed(_ speed: Double) {
        self.speed = speed
    }

    /// Starts speaking, interrupting whatever is playing. Returns once the new line has started.
    public func say(_ text: String, voice: VoicePlan) async {
        await interrupt()
        generation += 1
        let token = generation
        let engine = engine
        let rate = speed * voice.rate
        current = Task {
            do {
                try await engine.speak(text, voice: voice, rate: rate)
            } catch is CancellationError {
            } catch {
                await self.engineFailed(engine, error: error, retry: text, voice: voice, token: token)
            }
        }
    }

    /// Waits for the current line to finish. Mainly for tests and replays.
    public func finish() async {
        await current?.value
    }

    public func interrupt() async {
        guard let current else { return }
        current.cancel()
        await engine.stop()
        await current.value
        self.current = nil
    }

    private func engineFailed(
        _ failed: any SpeechEngine, error: Error, retry text: String, voice: VoicePlan, token: Int
    ) async {
        guard failed.id != fallback.id else {
            warnings.append("\(failed.id.rawValue) speech failed: \(error)")
            return
        }
        warnings.append("\(failed.id.rawValue) speech failed (\(error)); using \(fallback.id.rawValue) instead")
        engine = fallback
        // Only retry if no newer line has started meanwhile.
        if token == generation {
            try? await fallback.speak(text, voice: voice, rate: speed * voice.rate)
        }
    }
}
