import Testing

@testable import HablamonCore

/// Synthetic text crops: a light panel with dark "glyph" columns revealed left to right, like the typewriter effect.
enum SyntheticPage {
    static let width = 160
    static let height = 40

    /// `revealed` is the fraction of the text drawn so far; `seed` varies the glyph pattern per page.
    static func crop(revealed: Double, seed: Int, noise: UInt8 = 0, frame: Int = 0, ink: UInt8 = 40) -> GrayImage {
        var image = GrayImage(width: width, height: height, fill: 220)
        let visibleColumns = Int(Double(width - 8) * revealed)
        for x in 4..<(4 + visibleColumns) where (x * 7 + seed * 13) % 5 < 2 {
            for y in 12..<28 { image[x, y] = ink }
        }
        if noise > 0 {
            // Deterministic sensor noise that differs per frame.
            for index in image.pixels.indices {
                let jitter = UInt8((index * 31 + frame * 17) % Int(noise))
                image.pixels[index] = image.pixels[index] &+ jitter
            }
        }
        return image
    }

    /// Typing frames, then `hold` identical frames of the finished page.
    static func typing(seed: Int, steps: Int = 8, hold: Int = 4, noise: UInt8 = 0, ink: UInt8 = 40) -> [GrayImage] {
        let typing = (1...steps).map {
            crop(revealed: Double($0) / Double(steps), seed: seed, noise: noise, frame: $0, ink: ink)
        }
        let held = (0..<hold).map { crop(revealed: 1, seed: seed, noise: noise, frame: steps + 1 + $0, ink: ink) }
        return typing + held
    }
}

@Suite struct SettleDetectorTests {
    func events(_ frames: [GrayImage], detector: SettleDetector = .init()) -> [SettleDetector.Event?] {
        var detector = detector
        return frames.map { detector.observe($0) }
    }

    @Test func settlesOnceAfterTypingStops() {
        let result = events(SyntheticPage.typing(seed: 1, hold: 6))
        #expect(result.compactMap { $0 } == [.settled])
        // Needs three still samples after the last typing frame.
        #expect(result.firstIndex(of: .settled) == 8 + 3 - 1)
    }

    @Test func doesNotSettleWhileTyping() {
        // About six letters per sample, like Scarlet's typewriter at 4 samples a second.
        let typingOnly = (1...20).map { SyntheticPage.crop(revealed: Double($0) / 20, seed: 2) }
        #expect(events(typingOnly).compactMap { $0 }.isEmpty)
    }

    @Test func detectsTheNextPage() {
        let frames = SyntheticPage.typing(seed: 1) + SyntheticPage.typing(seed: 2)
        #expect(events(frames).compactMap { $0 } == [.settled, .pageChanged, .settled])
    }

    @Test func toleratesCameraNoise() {
        let result = events(SyntheticPage.typing(seed: 3, hold: 5, noise: 4))
        #expect(result.compactMap { $0 } == [.settled])
    }

    /// Washed-out pages: text barely darker than the panel, as at the far placement.
    @Test func handlesFaintPages() {
        let frames = SyntheticPage.typing(seed: 1, ink: 190) + SyntheticPage.typing(seed: 2, ink: 190)
        #expect(events(frames).compactMap { $0 } == [.settled, .pageChanged, .settled])
    }

    @Test func contrastRangeIgnoresOutliers() {
        var image = GrayImage(width: 100, height: 1, fill: 200)
        image[0, 0] = 0  // one dark speck
        for x in 50..<100 { image[x, 0] = 150 }
        #expect(image.contrastRange == 50)
    }

    @Test func resetStartsOver() {
        var detector = SettleDetector()
        for frame in SyntheticPage.typing(seed: 1) { _ = detector.observe(frame) }
        detector.reset()
        let again = SyntheticPage.typing(seed: 1).map { detector.observe($0) }
        #expect(again.compactMap { $0 } == [.settled])
    }
}

@Suite struct GrayImageTests {
    @Test func downscaleAverages() {
        let image = GrayImage(width: 4, height: 2, pixels: [0, 100, 200, 200, 0, 100, 200, 200])
        let small = image.downscaled(width: 2, height: 1)
        #expect(small.pixels == [50, 200])
    }

    @Test func changedFractionIgnoresSmallNoise() {
        let base = GrayImage(width: 2, height: 2, pixels: [100, 100, 100, 100])
        let noisy = GrayImage(width: 2, height: 2, pixels: [110, 90, 100, 200])
        #expect(noisy.changedFraction(from: base) == 0.25)
    }
}
