import Testing

@testable import HablamonCore

@Suite struct SampleSchedulerTests {
    /// Calls `decide` at 30 fps for `seconds` and counts what it asked for.
    func run(_ scheduler: inout SampleScheduler, seconds: Double, inDialogue: Bool, from start: Double = 0)
        -> (samples: Int, bezel: Int)
    {
        var samples = 0
        var bezel = 0
        for frame in 0..<Int(seconds * 30) {
            let decision = scheduler.decide(at: start + Double(frame) / 30, inDialogue: inDialogue)
            if decision.sample { samples += 1 }
            if decision.checkBezel { bezel += 1 }
        }
        return (samples, bezel)
    }

    @Test func idleSamplesEveryInterval() {
        var scheduler = SampleScheduler(idleInterval: 2, dialogueRate: 4)
        #expect(run(&scheduler, seconds: 10, inDialogue: false).samples == 5)
    }

    @Test func dialogueSamplesAtRate() {
        var scheduler = SampleScheduler(idleInterval: 2, dialogueRate: 4)
        #expect(run(&scheduler, seconds: 10, inDialogue: true).samples == 40)
    }

    @Test func switchesImmediatelyIntoDialogue() {
        var scheduler = SampleScheduler(idleInterval: 2, dialogueRate: 4)
        _ = scheduler.decide(at: 0, inDialogue: false)
        #expect(scheduler.decide(at: 0.3, inDialogue: true).sample, "no waiting out the idle interval")
    }

    @Test func bezelEveryTenSeconds() {
        var scheduler = SampleScheduler(idleInterval: 2, dialogueRate: 4)
        #expect(run(&scheduler, seconds: 31, inDialogue: true).bezel == 3)
    }
}
