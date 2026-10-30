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
