import HablamonModels
import Testing

@testable import HablamonCore

/// Records what it was asked to say; can be told to fail or to hang until stopped.
actor FakeEngine: SpeechEngine {
    nonisolated let id: SpeechEngineID
    let fails: Bool
    let holdsUntilStopped: Bool
    private(set) var spoken: [String] = []
    private(set) var rates: [Double] = []
    private(set) var stops = 0
    private var stopped = false

    init(id: SpeechEngineID, fails: Bool = false, holdsUntilStopped: Bool = false) {
        self.id = id
        self.fails = fails
        self.holdsUntilStopped = holdsUntilStopped
    }

    struct Failure: Error {}

    func prepare() async throws {}

    func speak(_ text: String, voice: VoicePlan, rate: Double) async throws {
        try Task.checkCancellation()
        stopped = false
        spoken.append(text)
        rates.append(rate)
        if fails { throw Failure() }
        // Like a real synthesizer: keeps talking until stopped or cancelled.
        while holdsUntilStopped && !stopped && !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(2))
        }
    }

    func stop() async {
        stops += 1
        stopped = true
    }
}

@Suite struct NarratorTests {
    let voice = VoicePlan(register: .female, voiceIdentifier: nil, pitch: 1.1, rate: 1.0)

    @Test func appliesTheGlobalSpeed() async {
        let engine = FakeEngine(id: .apple)
        let narrator = Narrator(engine: engine, fallback: engine, speed: 0.85)
        await narrator.say("¡Hola!", voice: voice)
        await narrator.finish()
        #expect(await engine.rates == [0.85])
    }

    @Test func newLineInterruptsTheOldOne() async {
        let engine = FakeEngine(id: .apple, holdsUntilStopped: true)
        let narrator = Narrator(engine: engine, fallback: engine)
        await narrator.say("Primera página", voice: voice)
        while await engine.spoken.isEmpty { await Task.yield() }
        await narrator.say("Segunda página", voice: voice)
        while await engine.spoken.count < 2 { await Task.yield() }
        #expect(await engine.spoken == ["Primera página", "Segunda página"])
        #expect(await engine.stops == 1)
        await narrator.interrupt()
    }

    @Test func fallsBackWhenTheEngineFails() async {
        let broken = FakeEngine(id: .qwen3, fails: true)
        let apple = FakeEngine(id: .apple)
        let narrator = Narrator(engine: broken, fallback: apple)
        await narrator.say("¿A que impresiona?", voice: voice)
        await narrator.finish()
        #expect(await apple.spoken == ["¿A que impresiona?"], "the line is not lost")
        #expect(await narrator.engine.id == .apple)
        #expect(await narrator.warnings.count == 1)
    }
}
