import Foundation
import HablamonModels
import Testing

@testable import HablamonCore

@Suite struct LiveControllerTests {
    let start = Date(timeIntervalSince1970: 1_800_000_000)
    let screen = rect(400, 160, 1080, 608)
    let frameArea = 1920.0 * 1080
    let reference = GrayImage(width: 128, height: 72, fill: 90)
    /// Striped, so it differs from the flat reference even after brightness is normalized.
    let elsewhere = GrayImage(
        width: 128, height: 72, pixels: (0..<(128 * 72)).map { ($0 % 128) / 6 % 2 == 0 ? 40 : 200 })

    func controller(calibrated: Bool = true) -> LiveController {
        LiveController(
            calibration: calibrated ? screen : nil, reference: calibrated ? reference : nil,
            scheduler: SampleScheduler(idleInterval: 2, dialogueRate: 4), startingAt: start)
    }

    /// Feeds 30 fps frames for `seconds`, returning every output.
    func frames(_ live: inout LiveController, from: Double, seconds: Double, inDialogue: Bool = false)
        -> [LiveOutput]
    {
        (0..<Int(seconds * 30)).flatMap { index -> [LiveOutput] in
            let time = from + Double(index) / 30
            return live.handle(.frame(time: time, date: start.addingTimeInterval(time), inDialogue: inDialogue))
        }
    }

    func date(_ seconds: Double) -> Date { start.addingTimeInterval(seconds) }

    @Test func tracksAndProcessesOnSchedule() {
        var live = controller()
        let outputs = frames(&live, from: 0, seconds: 4, inDialogue: true)
        #expect(outputs.filter { if case .process = $0 { true } else { false } }.count == 16)
        #expect(live.state == .tracking)
    }

    @Test func bezelCheckUsesCurrentQuad() {
        var live = controller()
        let outputs = frames(&live, from: 0, seconds: 11)
        #expect(outputs.contains(.checkBezel(screen)))
    }

    @Test func bezelMismatchStartsRefinding() {
        var live = controller()
        let outputs = live.handle(.bezel(quad: screen, thumbnail: elsewhere, date: date(10)))
        #expect(outputs.contains(.effect(.stopPipeline)))
        if case .refinding = live.state {} else { Issue.record("expected refinding, got \(live.state)") }
    }

    @Test func matchingBezelKeepsTracking() {
        var live = controller()
        #expect(live.handle(.bezel(quad: screen, thumbnail: reference, date: date(10))).isEmpty)
        #expect(live.state == .tracking)
    }

    @Test func suspendStopsAndLogsGap() {
        var live = controller()
        let stop = live.handle(.camera(.cameraSuspended, date: date(5)))
        #expect(stop.contains(.effect(.stopPipeline)))
        #expect(live.state == .paused)
        _ = live.handle(.camera(.cameraResumed, date: date(19)))
        let search = frames(&live, from: 19, seconds: 1)
        #expect(search.contains(.findRectangles))
        let candidate = live.handle(.rectangles([screen], frameArea: frameArea, date: date(20)))
        #expect(candidate == [.checkBezel(screen)])
        let back = live.handle(.bezel(quad: screen, thumbnail: reference, date: date(20)))
        #expect(back.contains(.effect(.logGap(reason: .cameraPaused, duration: 15))))
        #expect(live.quad == screen, "same place, so the quad is unchanged")
        #expect(!back.contains(.effect(.logRecalibration(.automatic))))
        #expect(live.state == .tracking)
    }

    @Test func movedPhoneRefindsAutomatically() {
        var live = controller()
        _ = live.handle(.bezel(quad: screen, thumbnail: elsewhere, date: date(10)))
        let moved = rect(430, 170, 1070, 602)
        #expect(live.handle(.rectangles([moved], frameArea: frameArea, date: date(11))) == [.checkBezel(moved)])
        let back = live.handle(.bezel(quad: moved, thumbnail: reference, date: date(11)))
        #expect(back.contains(.useQuad(moved)))
        #expect(back.contains(.effect(.logRecalibration(.automatic))))
        #expect(live.quad == moved)
        #expect(live.state == .tracking)
    }

    @Test func refindTimeoutAsksForHelp() {
        var live = controller()
        _ = live.handle(.bezel(quad: screen, thumbnail: elsewhere, date: date(10)))
        _ = frames(&live, from: 10, seconds: 11)
        let outputs = live.handle(.tick(date(21)))
        #expect(outputs.contains(.effect(.showCalibration)))
        #expect(outputs.contains(.effect(.play(.needsAttention))))
        #expect(live.state == .recalibrating)
    }

    @Test func confirmingCornersResumes() {
        var live = controller(calibrated: false)
        let corners = rect(410, 150, 1090, 610)
        let outputs = live.handle(.calibrationConfirmed(corners, reference: reference, date: date(3)))
        #expect(outputs.contains(.useQuad(corners)))
        #expect(live.state == .tracking)
        #expect(live.quad == corners)
    }

    @Test func noCalibrationStartsRecalibrating() {
        var live = controller(calibrated: false)
        #expect(live.state == .recalibrating)
        let outputs = frames(&live, from: 0, seconds: 2)
        #expect(outputs.contains(.findRectangles))
        #expect(!outputs.contains { if case .process = $0 { true } else { false } })
        _ = live.handle(.rectangles([screen], frameArea: frameArea, date: date(2)))
        #expect(live.proposal == screen)
    }
}
