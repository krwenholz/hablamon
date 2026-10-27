#if canImport(AVFoundation) && canImport(CoreImage) && canImport(Vision)
    import CoreImage
    import Foundation
    import HablamonModels
    import Testing

    @testable import HablamonCore

    /// Vision and the bezel check against real frames from Kyle's setup.
    @Suite struct RectangleFinderTests {
        let finder = RectangleFinder()
        let context = CIContext()

        func frames(_ name: String, at times: [Double]) async throws -> [Double: CIImage] {
            var found: [Double: CIImage] = [:]
            try await Replay.forEachFrame(in: VideoFixtures.url("\(name).mp4"), every: 0.5) { image, time in
                if let target = times.first(where: { abs($0 - time) < 0.26 }), found[target] == nil {
                    found[target] = image
                }
            }
            return found
        }

        @Test(
            .enabled(if: VideoFixtures.available("academy-lobby_far") && VideoFixtures.available("classroom_far")),
            arguments: [("academy-lobby_far", 30.0), ("classroom_far", 10.0)])
        func findsTheTVInFixtureFrames(_ name: String, _ time: Double) async throws {
            let image = try #require(try await frames(name, at: [time])[time])
            let calibrated = try VideoFixtures.calibration(name).screenQuad
            let candidates = try finder.candidates(in: image)
            let picked = try #require(
                QuadPicker.pick(candidates, near: nil, frameArea: Double(image.extent.width * image.extent.height)))
            #expect(picked.distance(to: calibrated) < 25, "picked \(picked)")
        }

        @Test(.enabled(if: VideoFixtures.available("academy-lobby_far")))
        func bezelMatchesAcrossScenesButNotAfterAMove() async throws {
            let quad = try VideoFixtures.calibration("academy-lobby_far").screenQuad
            let images = try await frames("academy-lobby_far", at: [10, 30])
            let early = try BezelThumbnail.make(from: try #require(images[10]), quad: quad, context: context)
            let late = try BezelThumbnail.make(from: try #require(images[30]), quad: quad, context: context)
            let moved = Quad(
                topLeft: Point(x: quad.topLeft.x + 60, y: quad.topLeft.y + 30),
                topRight: Point(x: quad.topRight.x + 60, y: quad.topRight.y + 30),
                bottomRight: Point(x: quad.bottomRight.x + 60, y: quad.bottomRight.y + 30),
                bottomLeft: Point(x: quad.bottomLeft.x + 60, y: quad.bottomLeft.y + 30))
            let shifted = try BezelThumbnail.make(from: try #require(images[30]), quad: moved, context: context)
            let matcher = BezelMatcher()
            print(
                "[bezel] same place \(matcher.difference(early, late)), moved \(matcher.difference(early, shifted))")
            #expect(matcher.matches(early, late), "a different scene on the TV is still the same place")
            #expect(!matcher.matches(early, shifted), "a phone moved by 60 px is not")
        }
    }
#endif
