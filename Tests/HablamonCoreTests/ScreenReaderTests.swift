#if canImport(AVFoundation) && canImport(CoreImage) && canImport(Vision)
    import CoreImage
    import Foundation
    import Testing

    @testable import HablamonCore

    @Suite struct ScreenReaderTests {
        @Test(.enabled(if: VideoFixtures.available("classroom_far")), .timeLimit(.minutes(1)))
        func readsTheDialogueOffAWholeFrame() async throws {
            let profile = try BundledData.profile("scarlet")
            let corrector = ScreenCorrector(
                quad: try VideoFixtures.calibration("classroom_far").screenQuad, size: profile.frameSize)
            var frame: CIImage?
            try await Replay.forEachFrame(in: VideoFixtures.url("classroom_far.mp4"), every: 1) { image, time in
                if frame == nil, time >= 10 { frame = corrector.correct(image) }
            }
            let corrected = try #require(frame)
            let image = try #require(
                CIContext().createCGImage(corrected, from: CGRect(x: 0, y: 0, width: 1280, height: 720)))
            let blocks = try ScreenReader().read(image)
            print("[screen] \(blocks.map(\.text))")
            let dialogue = try #require(blocks.first { $0.text.contains("haberos avisado") })
            #expect(dialogue.text.contains("uno más en clase"), "both lines of the box form one block")
            #expect(dialogue.box.y > 0.6, "the box is in the bottom of the frame")
            #expect(blocks.contains { $0.text == "Cinio" }, "the name tag is its own block")
        }
    }
#endif
