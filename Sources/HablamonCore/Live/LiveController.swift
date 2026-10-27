import Foundation
import HablamonModels

public enum LiveInput: Sendable {
    /// Every camera frame. `inDialogue` is the pipeline's current dialogue state.
    case frame(time: Double, date: Date, inDialogue: Bool)
    /// Suspended, resumed, disconnected, or reconnected.
    case camera(ConnectionMonitor.Signal, date: Date)
    /// Rectangle candidates found in the latest frame, answering `.findRectangles`.
    case rectangles([Quad], frameArea: Double, date: Date)
    /// The bezel thumbnail around `quad` in the latest frame, answering `.checkBezel`.
    case bezel(quad: Quad, thumbnail: GrayImage, date: Date)
    /// The player accepted these corners; `reference` is the bezel thumbnail around them.
    case calibrationConfirmed(Quad, reference: GrayImage, date: Date)
    case tick(Date)
}

public enum LiveOutput: Equatable, Sendable {
    /// Run the dialogue pipeline on this frame.
    case process(time: Double)
    /// Run rectangle detection on this frame and answer with `.rectangles`.
    case findRectangles
    /// Make a bezel thumbnail around this quad from this frame and answer with `.bezel`.
    case checkBezel(Quad)
    /// Correct frames with this quad from now on.
    case useQuad(Quad)
    case effect(ConnectionMonitor.Effect)
}

/// Runs the live camera loop's decisions: which frames to analyze, when to check that the phone
/// hasn't moved, and how to find the TV again. Wraps `ConnectionMonitor` for the recovery states.
/// Pure: the app performs the outputs (OCR, Vision, thumbnails) and feeds results back in.
public struct LiveController: Sendable {
    /// The screen corners in use.
    public private(set) var quad: Quad?
    /// The best candidate seen while uncalibrated, for the calibration panel.
    public private(set) var proposal: Quad?
    /// The last bezel comparison, for the log while tuning the threshold.
    public private(set) var lastBezelDifference: Double?
    private var reference: GrayImage?
    private var monitor: ConnectionMonitor
    private var scheduler: SampleScheduler
    private let matcher = BezelMatcher()
    private var lastSearch: Double?
    /// Seconds between rectangle searches while looking for the TV.
    public static let searchInterval = 0.5
    /// A re-found quad farther than this (mean corner pixels) counts as a recalibration.
    public static let movedThreshold = 8.0

    public init(calibration quad: Quad?, reference: GrayImage?, scheduler: SampleScheduler, startingAt date: Date) {
        self.quad = quad
        self.reference = reference
        self.scheduler = scheduler
        let calibrated = quad != nil && reference != nil
        monitor = ConnectionMonitor(startingAt: date, state: calibrated ? .tracking : .recalibrating)
    }

    public var state: ConnectionMonitor.State { monitor.state }

    public mutating func handle(_ input: LiveInput) -> [LiveOutput] {
        switch input {
        case .frame(let time, let date, let inDialogue):
            var outputs = signal(.frameReceived, at: date)
            switch monitor.state {
            case .tracking:
                let decision = scheduler.decide(at: time, inDialogue: inDialogue)
                if decision.sample { outputs.append(.process(time: time)) }
                if decision.checkBezel, let quad { outputs.append(.checkBezel(quad)) }
            case .refinding, .recalibrating:
                if lastSearch.map({ time - $0 >= Self.searchInterval }) ?? true {
                    lastSearch = time
                    // Try the saved corners first: the phone is often set back where it was,
                    // and Vision may not find the screen in a dark scene.
                    if let quad, reference != nil { outputs.append(.checkBezel(quad)) }
                    outputs.append(.findRectangles)
                }
            case .paused, .lost:
                break
            }
            return outputs

        case .camera(let cameraSignal, let date):
            return signal(cameraSignal, at: date)

        case .rectangles(let candidates, let frameArea, _):
            guard let picked = QuadPicker.pick(candidates, near: quad ?? proposal, frameArea: frameArea) else {
                return []
            }
            proposal = picked
            return reference == nil ? [] : [.checkBezel(picked)]

        case .bezel(let checked, let thumbnail, let date):
            guard let reference else { return [] }
            let difference = matcher.difference(reference, thumbnail)
            lastBezelDifference = difference
            let matches = difference <= matcher.threshold
            switch monitor.state {
            case .tracking where checked == quad:
                return matches ? [] : signal(.screenMismatch, at: date)
            case .refinding, .recalibrating:
                guard matches else { return [] }
                let moved = quad.map { checked.distance(to: $0) > Self.movedThreshold } ?? true
                quad = checked
                scheduler.reset()
                return [.useQuad(checked)] + signal(.screenFound(quadChanged: moved), at: date)
            default:
                return []
            }

        case .calibrationConfirmed(let corners, let thumbnail, let date):
            quad = corners
            reference = thumbnail
            proposal = nil
            scheduler.reset()
            return [.useQuad(corners)] + signal(.calibrationConfirmed, at: date)

        case .tick(let date):
            return signal(.tick, at: date)
        }
    }

    private mutating func signal(_ signal: ConnectionMonitor.Signal, at date: Date) -> [LiveOutput] {
        let effects = monitor.handle(signal, at: date)
        if effects.contains(.stopPipeline) { scheduler.reset() }
        return effects.map { .effect($0) }
    }
}
