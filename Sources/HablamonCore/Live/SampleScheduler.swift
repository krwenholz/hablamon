/// Decides which camera frames to analyze: rarely while nothing is happening, often during
/// dialogue, and a bezel check every so often to notice a moved phone. Saves battery on a fanless Air.
public struct SampleScheduler: Sendable {
    public var idleInterval: Double
    public var dialogueRate: Double
    public var bezelInterval: Double
    /// When the next sample is due; targets advance by the interval so frame timing doesn't drift.
    private var nextSample: Double?
    private var dialogue = false
    private var nextBezel: Double?

    public init(idleInterval: Double, dialogueRate: Double, bezelInterval: Double = 10) {
        self.idleInterval = idleInterval
        self.dialogueRate = dialogueRate
        self.bezelInterval = bezelInterval
    }

    public mutating func decide(at time: Double, inDialogue: Bool) -> (sample: Bool, checkBezel: Bool) {
        let interval = inDialogue ? 1 / dialogueRate : idleInterval
        // Entering dialogue samples right away instead of waiting out the idle interval.
        if inDialogue && !dialogue { nextSample = nil }
        dialogue = inDialogue
        let sample = time >= (nextSample ?? time)
        if sample { nextSample = Self.advance(nextSample ?? time, by: interval, past: time) }
        if nextBezel == nil { nextBezel = time + bezelInterval }
        let bezel = time >= nextBezel!
        if bezel { nextBezel = Self.advance(nextBezel!, by: bezelInterval, past: time) }
        return (sample, bezel)
    }

    /// Starts fresh, as after the camera comes back.
    public mutating func reset() {
        nextSample = nil
        nextBezel = nil
    }

    /// The next due time after `time`, skipping missed slots rather than bursting to catch up.
    static func advance(_ due: Double, by interval: Double, past time: Double) -> Double {
        var next = due + interval
        while next <= time { next += interval }
        return next
    }
}
