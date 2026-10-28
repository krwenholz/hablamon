#if canImport(AVFoundation) && canImport(CoreImage) && canImport(Vision)
    import CoreImage
    import Foundation
    import HablamonModels
    import Testing

    @testable import HablamonCore

    /// Feeds fixture videos to the live engine as if they came from the camera.
    @Suite struct LiveEngineTests {
        final class Inbox: @unchecked Sendable {
            private let lock = NSLock()
            private var items: [LiveEngine.Message] = []
            func add(_ message: LiveEngine.Message) { lock.withLock { items.append(message) } }
            var all: [LiveEngine.Message] { lock.withLock { items } }
        }

        let start = Date(timeIntervalSince1970: 1_800_000_000)

        func engine(calibrated: Bool, inbox: Inbox, reference: GrayImage? = nil) throws -> LiveEngine {
            LiveEngine(
                profile: try BundledData.profile("scarlet"), characters: try BundledData.defaultCharacters(),
                calibration: calibrated ? try VideoFixtures.calibration("academy-lobby_far").screenQuad : nil,
                reference: reference, settings: .defaults, startingAt: start, onMessage: inbox.add)
        }

        func feed(_ engine: LiveEngine, from: Double = 0, seconds: Double, every step: Double = 1.0 / 15) async throws {
            try await Replay.forEachFrame(in: VideoFixtures.url("academy-lobby_far.mp4"), every: step) { image, time in
                guard time >= from, time < seconds else { return }
                engine.feed(image, at: start.addingTimeInterval(time), wait: true)
            }
        }

        @Test(.enabled(if: VideoFixtures.available("academy-lobby_far")), .timeLimit(.minutes(2)))
        func readsAVideoAsIfLive() async throws {
            let inbox = Inbox()
            let quad = try VideoFixtures.calibration("academy-lobby_far").screenQuad
            var reference: GrayImage?
            try await Replay.forEachFrame(in: VideoFixtures.url("academy-lobby_far.mp4"), every: 1) { image, time in
                if reference == nil, time >= 1 {
                    reference = try BezelThumbnail.make(from: image, quad: quad, context: CIContext())
                }
            }
            let live = try engine(calibrated: true, inbox: inbox, reference: reference)
            try await feed(live, seconds: 26)
            let lines = inbox.all.compactMap { message -> String? in
                if case .pipeline(.speak(let page)) = message { page.text } else { nil }
            }
            print("[live] \(lines)")
            #expect(lines.count >= 4)
            #expect(lines.first?.hasPrefix("¡De nada!") == true)
            #expect(live.state == .tracking, "same place the whole time")
        }

        @Test(.timeLimit(.minutes(1)))
        func speaksSubtitlesWithoutABox() async throws {
            let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
                .appendingPathComponent("Fixtures/photos/subtitle-proyecto_far_straight.jpeg")
            let photo = try #require(CIImage(contentsOf: url, options: [.applyOrientationProperty: true]))
            let area = Double(photo.extent.width * photo.extent.height)
            let quad = try #require(
                QuadPicker.pick(try RectangleFinder().candidates(in: photo), near: nil, frameArea: area))
            let inbox = Inbox()
            let live = LiveEngine(
                profile: try BundledData.profile("scarlet"), characters: try BundledData.defaultCharacters(),
                calibration: quad, reference: try BezelThumbnail.make(from: photo, quad: quad, context: CIContext()),
                settings: .defaults, startingAt: start, onMessage: inbox.add)
            // The same cutscene frame for four seconds, as the camera would see it.
            for index in 0..<40 {
                live.feed(photo, at: start.addingTimeInterval(Double(index) * 0.1), wait: true)
                live.waitForFreeSpeech()
            }
            let spoken = inbox.all.compactMap { message -> SpokenPage? in
                if case .pipeline(.speak(let page)) = message { page } else { nil }
            }
            #expect(spoken.count == 1, "said once, not every check")
            #expect(spoken.first?.text.contains("proyecto extracurricular") == true)
            #expect(spoken.first?.speaker == .narrator)
        }

        @Test func framesDroppedWhileBusyKeepTrackingAlive() async throws {
            let inbox = Inbox()
            let live = LiveEngine(
                profile: try BundledData.profile("scarlet"), characters: CharacterTable(characters: [:]),
                calibration: rect(400, 160, 1080, 608), reference: GrayImage(width: 128, height: 72, fill: 90),
                settings: .defaults, startingAt: start, onMessage: inbox.add)
            // A slow sample is still being read; frames keep arriving and are dropped.
            live.noteArrival(start.addingTimeInterval(1.8))
            live.tick(start.addingTimeInterval(2))
            #expect(live.state == .tracking, "the camera is alive, just busy")
            live.tick(start.addingTimeInterval(4))
            #expect(live.state == .paused, "no frames at all for over a second is a pause")
        }

        @Test(.enabled(if: VideoFixtures.available("academy-lobby_far")), .timeLimit(.minutes(2)))
        func calibratesFromScratch() async throws {
            let inbox = Inbox()
            let live = try engine(calibrated: false, inbox: inbox)
            #expect(live.state == .recalibrating)
            // The video opens zoomed in and the camera settles over the first few seconds.
            try await feed(live, from: 8, seconds: 11)
            let proposal = try #require(
                inbox.all.compactMap { message -> Quad? in
                    if case .preview(_, _, let proposal, _) = message { proposal } else { nil }
                }.last)
            let distance = proposal.distance(to: try VideoFixtures.calibration("academy-lobby_far").screenQuad)
            #expect(distance < 25, "proposal \(proposal) is \(distance) px off")
            live.confirm(proposal, at: start.addingTimeInterval(11), wait: true)
            #expect(live.state == .tracking)
            #expect(inbox.all.contains { if case .calibrated = $0 { true } else { false } })
        }
    }
#endif
