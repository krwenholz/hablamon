import Foundation
import HablamonModels

/// Tracks whether the camera can see the TV, and decides what to do when it can't.
///
/// Picking up the phone is expected: the pipeline pauses, logs a gap, re-finds the screen when
/// the phone is set down, and only asks the player for help after `refindTimeout` without a match.
/// This type is pure: feed it signals with timestamps and perform the effects it returns.
public struct ConnectionMonitor: Sendable {
    public enum State: Equatable, Sendable {
        /// Watching the TV normally.
        case tracking
        /// The phone was picked up (Continuity Camera suspended) or frames stopped arriving.
        case paused
        /// The pinned camera disconnected.
        case lost
        /// Frames are arriving; looking for the screen quad again.
        case refinding(since: Date)
        /// Couldn't re-find the screen on its own; waiting for the player.
        case recalibrating
    }

    public enum Signal: Equatable, Sendable {
        case frameReceived
        case cameraSuspended
        case cameraResumed
        case cameraDisconnected
        case cameraReconnected
        /// The bezel no longer matches the reference, or box detection fails on every sample.
        case screenMismatch
        /// Rectangle detection found a quad matching the reference bezel.
        case screenFound(quadChanged: Bool)
        /// The player accepted or adjusted the corners in the calibration view.
        case calibrationConfirmed
        /// Periodic check for timeouts.
        case tick
    }

    public enum Cue: Equatable, Sendable {
        case stoppedWatching
        case resumedWatching
        case needsAttention
    }

    public enum Effect: Equatable, Sendable {
        /// Stop speech and drop any half-settled page.
        case stopPipeline
        case logGap(reason: TranscriptGap.Reason, duration: TimeInterval)
        case logRecalibration(TranscriptRecalibration.Trigger)
        /// Bring the window forward with the calibration preview.
        case showCalibration
        case play(Cue)
    }

    public struct Configuration: Sendable, Equatable {
        /// No frames for this long counts as paused.
        public var frameTimeout: TimeInterval
        /// Re-finding for this long without a match asks the player to recalibrate.
        public var refindTimeout: TimeInterval

        public init(frameTimeout: TimeInterval = 1, refindTimeout: TimeInterval = 10) {
            self.frameTimeout = frameTimeout
            self.refindTimeout = refindTimeout
        }
    }

    public private(set) var state: State
    public var configuration: Configuration
    private var lastFrameAt: Date
    /// When tracking stopped and why; becomes a gap entry once tracking resumes.
    private var outage: (since: Date, reason: TranscriptGap.Reason)?

    public init(startingAt date: Date, configuration: Configuration = .init()) {
        self.state = .tracking
        self.configuration = configuration
        self.lastFrameAt = date
    }

    public mutating func handle(_ signal: Signal, at date: Date) -> [Effect] {
        if signal == .frameReceived { lastFrameAt = date }

        switch (state, signal) {
        // Leaving tracking.
        case (.tracking, .cameraSuspended):
            return leaveTracking(to: .paused, reason: .cameraPaused, at: date)
        case (.tracking, .tick) where date.timeIntervalSince(lastFrameAt) > configuration.frameTimeout:
            return leaveTracking(to: .paused, reason: .cameraPaused, at: date)
        case (.tracking, .cameraDisconnected):
            return leaveTracking(to: .lost, reason: .cameraLost, at: date)
        case (.tracking, .screenMismatch):
            return leaveTracking(to: .refinding(since: date), reason: .screenLost, at: date)

        // Camera interruptions while already away.
        case (.paused, .cameraDisconnected), (.refinding, .cameraDisconnected), (.recalibrating, .cameraDisconnected):
            state = .lost
            return []
        case (.refinding, .cameraSuspended), (.recalibrating, .cameraSuspended):
            state = .paused
            return []
        case (.refinding, .tick) where date.timeIntervalSince(lastFrameAt) > configuration.frameTimeout:
            state = .paused
            return []

        // Camera back: look for the screen again, since the phone may have moved.
        case (.paused, .cameraResumed), (.paused, .frameReceived), (.lost, .cameraReconnected):
            state = .refinding(since: date)
            return []

        // Re-finding.
        case (.refinding, .screenFound(let quadChanged)), (.recalibrating, .screenFound(let quadChanged)):
            return resumeTracking(at: date, recalibration: quadChanged ? .automatic : nil)
        case (.refinding(let since), .tick) where date.timeIntervalSince(since) > configuration.refindTimeout:
            state = .recalibrating
            return [.showCalibration, .play(.needsAttention)]
        case (.recalibrating, .calibrationConfirmed), (.refinding, .calibrationConfirmed):
            return resumeTracking(at: date, recalibration: .manual)

        default:
            return []
        }
    }

    private mutating func leaveTracking(to newState: State, reason: TranscriptGap.Reason, at date: Date) -> [Effect] {
        state = newState
        outage = (date, reason)
        return [.stopPipeline, .play(.stoppedWatching)]
    }

    private mutating func resumeTracking(at date: Date, recalibration: TranscriptRecalibration.Trigger?) -> [Effect] {
        state = .tracking
        lastFrameAt = date
        var effects: [Effect] = []
        if let outage {
            effects.append(.logGap(reason: outage.reason, duration: date.timeIntervalSince(outage.since)))
        }
        if let recalibration { effects.append(.logRecalibration(recalibration)) }
        effects.append(.play(.resumedWatching))
        outage = nil
        return effects
    }
}
