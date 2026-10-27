import HablamonModels
import Testing

@testable import HablamonCore

@Suite struct QualityGateTests {
    let profile: GameProfile

    init() throws {
        profile = try BundledData.profile("scarlet")
    }

    func body(_ value: UInt8) -> RGBAImage {
        RGBAImage(width: 10, height: 10, pixels: [UInt8](repeating: value, count: 400))
    }

    @Test func farQuadTextHeight() throws {
        let report = QualityGate.report(
            quad: try VideoFixtures.calibration("far").screenQuad, profile: profile, bodyCrop: nil)
        #expect((8...14).contains(report.textHeight))
        #expect(report.warnings.isEmpty)
    }

    @Test func smallQuadWarns() {
        let report = QualityGate.report(quad: rect(0, 0, 400, 225), profile: profile, bodyCrop: nil)
        #expect(report.textHeight < 8)
        #expect(report.warnings.count == 1)
    }

    @Test func clippedHighlightsWarn() {
        let quad = rect(0, 0, 1280, 720)
        #expect(QualityGate.report(quad: quad, profile: profile, bodyCrop: body(255)).clipped == 1)
        #expect(QualityGate.report(quad: quad, profile: profile, bodyCrop: body(255)).warnings.count == 1)
        #expect(QualityGate.report(quad: quad, profile: profile, bodyCrop: body(200)).warnings.isEmpty)
    }
}
