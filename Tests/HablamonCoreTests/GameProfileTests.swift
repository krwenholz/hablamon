import HablamonModels
import Testing

@testable import HablamonCore

@Suite struct GameProfileTests {
    @Test func scarletProfileLoads() throws {
        let profile = try BundledData.profile("scarlet")
        #expect(profile.frameSize == PixelSize(width: 1280, height: 720))
    }

    @Test func regionsSitInsideTheFrameAndBox() throws {
        let profile = try BundledData.profile("scarlet")
        let frame = PixelRect(x: 0, y: 0, width: profile.frameSize.width, height: profile.frameSize.height)
        let regions = profile.regions
        for rect in [regions.dialogueBox, regions.bodyText, regions.nameTag]
            + [regions.advanceIndicator].compactMap({ $0 })
        {
            #expect(contains(frame, rect))
        }
        #expect(contains(regions.dialogueBox, regions.bodyText))
        #expect(regions.nameTag.y < regions.dialogueBox.y, "the name tag sits above the box")
    }

    func contains(_ outer: PixelRect, _ inner: PixelRect) -> Bool {
        inner.x >= outer.x && inner.y >= outer.y
            && inner.x + inner.width <= outer.x + outer.width
            && inner.y + inner.height <= outer.y + outer.height
    }
}
