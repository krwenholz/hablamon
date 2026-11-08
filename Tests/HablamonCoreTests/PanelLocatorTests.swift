import HablamonModels
import Testing

@testable import HablamonCore

@Suite struct PanelLocatorTests {
    let expected = PixelRect(x: 296, y: 512, width: 690, height: 144)

    /// Row medians from 440 down: scenery at `background`, then a panel at `panel` brightness over
    /// `rows`, with the two text lines dipping the median for a few rows each.
    func medians(background: Double, panel: Double = 0.95, rows: Range<Int>) -> [Double] {
        (440..<720).map { row in
            guard rows.contains(row) else { return background }
            let line = row - rows.lowerBound
            return (34...37).contains(line) || (46...48).contains(line) ? panel - 0.15 : panel
        }
    }

    @Test func findsAPanelSmallerAndHigherThanExpected() throws {
        // Corners on the bezel: the box comes out about 20% smaller and a little higher.
        let found = try #require(
            PanelLocator.locate(
                rowMedians: medians(background: 0.6, rows: 501..<615), firstRow: 440, expected: expected))
        #expect(found.top == 501 && found.height == 114)
    }

    @Test func picksTheBandNearTheBoxOverBrightSkyAbove() throws {
        var rows = medians(background: 0.68, rows: 520..<648)
        for row in 440..<490 { rows[row - 440] = 0.94 }
        let found = try #require(PanelLocator.locate(rowMedians: rows, firstRow: 440, expected: expected))
        #expect(found.top == 520 && found.height == 128)
    }

    @Test func noPanelInDarkScenery() {
        #expect(
            PanelLocator.locate(
                rowMedians: medians(background: 0.4, panel: 0.45, rows: 0..<0), firstRow: 440, expected: expected)
                == nil)
    }

    @Test func alignedRegionsFollowTheBox() {
        let regions = ProfileRegions(
            dialogueBox: expected, bodyText: PixelRect(x: 330, y: 536, width: 630, height: 96),
            textLines: PixelRect(x: 330, y: 544, width: 630, height: 76),
            nameTag: PixelRect(x: 292, y: 495, width: 180, height: 34))
        let moved = regions.aligned(boxTop: 500, boxHeight: 72, frameHeight: 720)
        #expect(moved.dialogueBox == PixelRect(x: 296, y: 500, width: 690, height: 72))
        #expect(moved.bodyText == PixelRect(x: 330, y: 512, width: 630, height: 48))
        #expect(moved.nameTag.y == 492)
    }
}

#if canImport(CoreImage) && canImport(Vision)
    import CoreImage
    import Foundation

    /// Corrected screens saved by the iPhone app's Guardar captura, with corners on the TV's bezel:
    /// the box sits higher and smaller than the profile expects, and must still be read.
    @Suite struct PhoneCaptureTests {
        static let directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Fixtures/phone-captures")

        @Test(
            arguments: [
                ("enhorabuena-gimnasio_far_bezel-corners.png", "Pueblo Altamía", nil),
                ("enhorabuena-gimnasio_far_bezel-corners-pink.png", "Pueblo Altamía", nil),
                ("helado-fresquitos_far_bezel-corners.png", "¿Te apetece uno?", nil),
                ("hesperio-clase-arte_far_bezel-corners.png", "de Arte.", "Hesperio"),
            ] as [(String, String, String?)])
        func readsTheBox(_ name: String, _ secondLine: String, _ speaker: String?) throws {
            let url = Self.directory.appendingPathComponent(name)
            let image = try #require(CIImage(contentsOf: url), "missing fixture \(name)")
            let profile = try BundledData.profile("scarlet")
            let frame = CorrectedFrame(
                image: image, context: CIContext(), recognizer: VisionTextRecognizer(), alignsToPanel: true)
            let features = try frame.boxFeatures(profile)
            #expect(features.isBoxVisible(profile.detection), "\(features.summary(profile.detection))")
            let lines = try frame.readBody(profile).map(\.text)
            #expect(lines.count == 2 && lines.last?.contains(secondLine) == true, "\(lines)")
            if speaker != nil {
                #expect(features.hasNameTag(profile.detection))
            }
        }
    }
#endif
