import HablamonModels
import Testing

@testable import HablamonCore

@Suite struct BezelMatcherTests {
    let matcher = BezelMatcher()
    let size = BezelMatcher.size

    /// Vertical bars everywhere, so moving the picture changes the ring.
    func bars(offset: Int = 0, brightness: Int = 0, screen: UInt8? = nil) -> GrayImage {
        var image = GrayImage(width: size.width, height: size.height)
        let mask = BezelMatcher.ringMask()
        for y in 0..<size.height {
            for x in 0..<size.width {
                let base = ((x + offset) / 6) % 2 == 0 ? 60 : 180
                var value = base + brightness
                if let screen, !mask[y * size.width + x] { value = Int(screen) }
                image[x, y] = UInt8(clamping: value)
            }
        }
        return image
    }

    @Test func pgmRoundTrips() throws {
        let image = bars()
        #expect(try GrayImage(pgm: image.pgm) == image)
    }

    @Test func rejectsBadPGM() {
        #expect(throws: (any Error).self) { try GrayImage(pgm: Array("P6\n1 1\n255\n".utf8) + [0, 0, 0]) }
    }

    @Test func identicalImagesMatch() {
        #expect(matcher.matches(bars(), bars()))
    }

    @Test func brightnessShiftStillMatches() {
        #expect(matcher.matches(bars(), bars(brightness: 40)))
    }

    @Test func changedScreenContentStillMatches() {
        #expect(matcher.matches(bars(screen: 0), bars(screen: 255)))
    }

    @Test func shiftedBezelDoesNotMatch() {
        #expect(!matcher.matches(bars(), bars(offset: 6)))
    }

    @Test func largerImagesAreDownscaled() {
        let big = GrayImage(width: size.width * 2, height: size.height * 2, fill: 90)
        #expect(matcher.matches(GrayImage(width: size.width, height: size.height, fill: 90), big))
    }

    @Test func expandedQuadScalesAboutCenter() {
        let quad = rect(100, 100, 200, 100).expanded(by: 1.5)
        #expect(quad == rect(50, 75, 300, 150))
    }
}
