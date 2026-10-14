import HablamonModels
import Testing

@testable import HablamonCore

@Suite struct BoxDetectorTests {
    let detection = BoxDetection(
        edgeStep: 0.04,
        maxMarginEdgeDensity: 0.012,
        minTextEdgeDensity: 0.003,
        tagSaturation: 0.3,
        minTagFraction: 0.5
    )
    let textRows = 8..<22

    func image(width: Int = 60, height: Int = 30, _ color: (Int, Int) -> (UInt8, UInt8, UInt8)) -> RGBAImage {
        var pixels: [UInt8] = []
        for y in 0..<height {
            for x in 0..<width {
                let (r, g, b) = color(x, y)
                pixels += [r, g, b, 255]
            }
        }
        return RGBAImage(width: width, height: height, pixels: pixels)
    }

    /// Washed-out panel (as the phone sees it) with faint text on two lines and blank margins.
    var panel: RGBAImage {
        image { x, y in
            let onText = (y == 11 || y == 12 || y == 17 || y == 18) && x % 4 != 0
            return onText ? (200, 200, 205) : (245, 245, 250)
        }
    }

    /// Railings and foliage: edges everywhere, including the margin rows.
    var scenery: RGBAImage {
        image { x, y in (x + y) % 5 == 0 ? (90, 140, 70) : (180, 210, 160) }
    }

    /// Overexposed scene: almost uniform bluish white.
    var washedOut: RGBAImage { image { _, _ in (238, 240, 252) } }

    var blueTag: RGBAImage { image(width: 40, height: 10) { x, _ in x > 34 ? (240, 240, 250) : (60, 80, 200) } }

    func features(body: RGBAImage, tag: RGBAImage? = nil) -> BoxFeatures {
        BoxFeatures(body: body, textRows: textRows, nameTag: tag ?? washedOut, detection: detection)
    }

    @Test func seesTheBoxThroughOverexposure() {
        let measured = features(body: panel)
        #expect(measured.marginEdgeDensity == 0)
        #expect(measured.isBoxVisible(detection))
    }

    @Test func rejectsScenery() {
        #expect(!features(body: scenery).isBoxVisible(detection))
    }

    @Test func rejectsAWashedOutScreen() {
        // Blank and bright with no text: no edges anywhere.
        #expect(!features(body: washedOut).isBoxVisible(detection))
    }

    @Test func nameTagShowsTheBoxEvenWithBusyMargins() {
        // Tall letters (¿, ¡, descenders) can reach the margin rows; the tag still says the box is up.
        #expect(features(body: scenery, tag: blueTag).isBoxVisible(detection))
    }

    @Test func detectsTheNameTag() {
        #expect(features(body: panel, tag: blueTag).hasNameTag(detection))
        // Bluish white from overexposure is not tag blue.
        #expect(!features(body: panel, tag: washedOut).hasNameTag(detection))
    }
}

@Suite struct DialoguePresenceTests {
    func changes(_ samples: [(Double, Bool)]) -> [DialoguePresence.Change?] {
        var presence = DialoguePresence()
        return samples.map { presence.observe(boxVisible: $0.1, at: $0.0) }
    }

    @Test func entersAfterTwoPositives() {
        #expect(changes([(0, true), (0.25, true)]) == [nil, .entered])
    }

    @Test func ignoresASingleFlash() {
        #expect(changes([(0, true), (0.25, false), (0.5, true)]).compactMap { $0 }.isEmpty)
    }

    @Test func exitsAfterThreeSecondsAbsent() {
        let result = changes([(0, true), (0.25, true), (1, false), (2, false), (3.25, false)])
        #expect(result.compactMap { $0 } == [.entered, .exited])
    }

    @Test func briefDropoutKeepsDialogue() {
        let result = changes([(0, true), (0.25, true), (1, false), (2, true), (5, true)])
        #expect(result.compactMap { $0 } == [.entered])
    }
}
