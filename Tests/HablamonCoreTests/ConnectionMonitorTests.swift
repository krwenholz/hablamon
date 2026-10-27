import Foundation
import Testing

@testable import HablamonCore

@Suite struct ConnectionMonitorTests {
    let t0 = Date(timeIntervalSince1970: 1_791_772_200)

    /// Replays (seconds after t0, signal) pairs and returns the monitor plus every effect in order.
    func run(_ script: [(Double, ConnectionMonitor.Signal)]) -> (ConnectionMonitor, [ConnectionMonitor.Effect]) {
        var monitor = ConnectionMonitor(startingAt: t0)
        var effects: [ConnectionMonitor.Effect] = []
        for (seconds, signal) in script {
            effects += monitor.handle(signal, at: t0.addingTimeInterval(seconds))
        }
        return (monitor, effects)
    }

    @Test func phonePickedUpAndPutBack() {
        let (monitor, effects) = run([
            (0, .frameReceived),
            (5, .cameraSuspended),
            (50, .cameraResumed),
            (51, .screenFound(quadChanged: true)),
        ])
        #expect(monitor.state == .tracking)
        #expect(
            effects == [
                .stopPipeline, .play(.stoppedWatching),
                .logGap(reason: .cameraPaused, duration: 46), .logRecalibration(.automatic), .play(.resumedWatching),
            ]
        )
    }

    @Test func unmovedPhoneLogsNoRecalibration() {
        let (_, effects) = run([(0, .cameraSuspended), (3, .cameraResumed), (4, .screenFound(quadChanged: false))])
        #expect(effects.contains(.logGap(reason: .cameraPaused, duration: 4)))
        #expect(!effects.contains(.logRecalibration(.automatic)))
    }

    @Test func framesStoppingCountsAsPaused() {
        let (monitor, effects) = run([(0, .frameReceived), (0.5, .tick), (1.6, .tick)])
        #expect(monitor.state == .paused)
        #expect(effects == [.stopPipeline, .play(.stoppedWatching)])
    }

    @Test func framesReturningStartsRefinding() {
        let (monitor, _) = run([(0, .frameReceived), (2, .tick), (3, .frameReceived)])
        #expect(monitor.state == .refinding(since: t0.addingTimeInterval(3)))
    }

    @Test func disconnectAndReconnect() {
        let (monitor, effects) = run([
            (0, .cameraDisconnected),
            (20, .cameraReconnected),
            (21, .frameReceived),
            (22, .screenFound(quadChanged: false)),
        ])
        #expect(monitor.state == .tracking)
        #expect(effects.contains(.logGap(reason: .cameraLost, duration: 22)))
    }

    @Test func bumpedPhoneRefindsScreen() {
        let (monitor, effects) = run([
            (0, .frameReceived), (1, .screenMismatch), (2, .frameReceived), (3, .screenFound(quadChanged: true)),
        ])
        #expect(monitor.state == .tracking)
        #expect(effects.contains(.logGap(reason: .screenLost, duration: 2)))
    }

    @Test func asksForHelpAfterTenSeconds() {
        var script: [(Double, ConnectionMonitor.Signal)] = [(0, .frameReceived), (0, .screenMismatch)]
        for second in stride(from: 0.5, through: 11, by: 0.5) {
            script += [(second, .frameReceived), (second, .tick)]
        }
        let (monitor, effects) = run(script)
        #expect(monitor.state == .recalibrating)
        #expect(effects.filter { $0 == .showCalibration }.count == 1, "asks once, not on every tick")
    }

    @Test func playerConfirmsCalibration() {
        var script: [(Double, ConnectionMonitor.Signal)] = [(0, .screenMismatch)]
        for second in stride(from: 1.0, through: 11, by: 1) { script += [(second, .frameReceived), (second, .tick)] }
        script.append((30, .calibrationConfirmed))
        let (monitor, effects) = run(script)
        #expect(monitor.state == .tracking)
        #expect(
            effects.suffix(3) == [
                .logGap(reason: .screenLost, duration: 30), .logRecalibration(.manual), .play(.resumedWatching),
            ])
    }

    @Test func gapKeepsTheFirstReason() {
        // Picked up, then disconnected while away: the outage started as a pause.
        let (_, effects) = run([
            (0, .cameraSuspended), (5, .cameraDisconnected), (9, .cameraReconnected),
            (10, .screenFound(quadChanged: false)),
        ])
        #expect(effects.contains(.logGap(reason: .cameraPaused, duration: 10)))
    }

    @Test func steadyTrackingDoesNothing() {
        var script: [(Double, ConnectionMonitor.Signal)] = []
        for second in stride(from: 0.25, through: 30, by: 0.25) {
            script += [(second, .frameReceived), (second, .tick)]
        }
        let (monitor, effects) = run(script)
        #expect(monitor.state == .tracking)
        #expect(effects.isEmpty)
    }

    @Test func framesWhileSuspendedDoNotEndThePause() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        var monitor = ConnectionMonitor(startingAt: start)
        _ = monitor.handle(.cameraSuspended, at: start.addingTimeInterval(1))
        _ = monitor.handle(.frameReceived, at: start.addingTimeInterval(1.1))
        #expect(monitor.state == .paused, "a trailing or frozen frame isn't the phone coming back")
        _ = monitor.handle(.cameraResumed, at: start.addingTimeInterval(5))
        if case .refinding = monitor.state {} else { Issue.record("expected refinding, got \(monitor.state)") }
    }
}
