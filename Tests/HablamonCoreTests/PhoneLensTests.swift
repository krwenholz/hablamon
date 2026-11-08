import Foundation
import Testing

@testable import HablamonCore

@Suite struct PhoneLensTests {
    @Test func mainCameraIsOneX() {
        #expect(PhoneLens.magnification(fieldOfView: 70, mainFieldOfView: 70) == 1)
        #expect(PhoneLens(id: "wide", magnification: 1).name == "1×")
    }

    @Test func telephotoFromFieldOfView() {
        // A 5× telephoto sees about a fifth of the main camera's width.
        let main = 69.4
        let tele = 2 * atan(tan(main / 2 * .pi / 180) / 5) * 180 / .pi
        let magnification = PhoneLens.magnification(fieldOfView: tele, mainFieldOfView: main)
        #expect(abs(magnification - 5) < 0.001)
        #expect(PhoneLens(id: "tele", magnification: magnification).name == "5×")
    }

    @Test func ultraWideIsHalf() {
        let magnification = PhoneLens.magnification(fieldOfView: 106, mainFieldOfView: 69.4)
        #expect(magnification < 0.8)
        #expect(PhoneLens(id: "ultra", magnification: magnification).name == "0.5×")
    }

    @Test func nonsenseFieldOfViewIsOneX() {
        #expect(PhoneLens.magnification(fieldOfView: 0, mainFieldOfView: 70) == 1)
    }

    @Test func captureRotationFollowsTheScreen() {
        // The angles AVCaptureDevice.RotationCoordinator gives for the back camera held each way.
        #expect(PhoneLens.captureRotation(for: .landscapeRight) == 0)
        #expect(PhoneLens.captureRotation(for: .portrait) == 90)
        #expect(PhoneLens.captureRotation(for: .landscapeLeft) == 180)
        #expect(PhoneLens.captureRotation(for: .portraitUpsideDown) == 270)
    }

    @Test func portraitMetersTheRightSensorPoint() {
        // In portrait the upright frame's top edge is the sensor's right edge.
        let rotation = PhoneLens.captureRotation(for: .portrait)
        let top = PhoneLens.sensorPoint(x: 0.5, y: 0, rotation: rotation)
        #expect(top.x == 0 && top.y == 0.5)
    }

    @Test func sensorPointUnrotated() {
        let point = PhoneLens.sensorPoint(x: 0.2, y: 0.7, rotation: 0)
        #expect(point.x == 0.2 && point.y == 0.7)
    }

    @Test func sensorPointUpsideDown() {
        let point = PhoneLens.sensorPoint(x: 0.25, y: 0.75, rotation: 180)
        #expect(point.x == 0.75 && point.y == 0.25)
    }

    @Test func sensorPointPortrait() {
        // Turned 90° clockwise, the upright frame's top-left corner is the sensor's bottom-left.
        let corner = PhoneLens.sensorPoint(x: 0, y: 0, rotation: 90)
        #expect(corner.x == 0 && corner.y == 1)
        let other = PhoneLens.sensorPoint(x: 0, y: 0, rotation: 270)
        #expect(other.x == 1 && other.y == 0)
    }
}

@Suite struct PhoneZoomTests {
    // Magnifications as `PhoneCamera.lenses()` works them out from fields of view, slightly off.
    let ultraWide = PhoneLens(id: "ultra", magnification: 0.52)
    let wide = PhoneLens(id: "wide", magnification: 1)
    let threeX = PhoneLens(id: "tele3", magnification: 3.02)
    let fourX = PhoneLens(id: "tele4", magnification: 4.03)
    let fiveX = PhoneLens(id: "tele5", magnification: 5.01)

    @Test func halfIsTheUltraWideUnzoomed() {
        let zoom = PhoneZoom.choose(0.5, from: [ultraWide, wide, threeX])
        #expect(zoom?.lensID == "ultra")
        #expect(zoom?.zoom == 1)
        #expect(zoom?.name == "0.5×")
    }

    @Test func oneAndTwoAreTheWide() {
        let lenses = [ultraWide, wide, threeX]
        #expect(PhoneZoom.choose(1, from: lenses) == PhoneZoom(magnification: 1, lensID: "wide", zoom: 1))
        #expect(PhoneZoom.choose(2, from: lenses) == PhoneZoom(magnification: 2, lensID: "wide", zoom: 2))
    }

    @Test func fourUsesAThreeXTelephotoZoomedIn() {
        let zoom = PhoneZoom.choose(4, from: [ultraWide, wide, threeX])
        #expect(zoom?.lensID == "tele3")
        #expect(abs((zoom?.zoom ?? 0) - 4 / 3.02) < 0.001)
    }

    @Test func fourUsesAFourXTelephotoUnzoomed() {
        // 4.03 is the 4× lens measured a little long, not a lens that overshoots.
        let zoom = PhoneZoom.choose(4, from: [ultraWide, wide, fourX])
        #expect(zoom?.lensID == "tele4")
        #expect(zoom?.zoom == 1)
    }

    @Test func fourZoomsTheWideWhenTheTelephotoOvershoots() {
        let zoom = PhoneZoom.choose(4, from: [ultraWide, wide, fiveX])
        #expect(zoom?.lensID == "wide")
        #expect(zoom?.zoom == 4)
    }

    @Test func noUltraWideMeansNoHalf() {
        #expect(PhoneZoom.choose(0.5, from: [wide, threeX]) == nil)
        #expect(PhoneZoom.options(for: [wide, threeX]).map(\.name) == ["1×", "2×", "4×"])
    }

    @Test func everyButtonOnAProPhone() {
        let options = PhoneZoom.options(for: [ultraWide, wide, fiveX])
        #expect(options.map(\.name) == ["0.5×", "1×", "2×", "4×"])
        #expect(options.map(\.lensID) == ["ultra", "wide", "wide", "wide"])
    }

    @Test func noLensesMeansNoButtons() {
        #expect(PhoneZoom.options(for: []).isEmpty)
    }

    @Test func matchesTheCameraSetting() {
        let two = PhoneZoom(magnification: 2, lensID: "wide", zoom: 2)
        #expect(two.matches(lensID: "wide", zoom: 2.01))
        #expect(!two.matches(lensID: "wide", zoom: 1))
        #expect(!two.matches(lensID: "tele3", zoom: 2))
        #expect(!two.matches(lensID: nil, zoom: 2))
    }
}
