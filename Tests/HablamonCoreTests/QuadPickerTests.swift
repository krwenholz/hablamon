import HablamonModels
import Testing

@testable import HablamonCore

func rect(_ x: Double, _ y: Double, _ width: Double, _ height: Double) -> Quad {
    Quad(
        topLeft: Point(x: x, y: y), topRight: Point(x: x + width, y: y),
        bottomRight: Point(x: x + width, y: y + height), bottomLeft: Point(x: x, y: y + height))
}

@Suite struct QuadPickerTests {
    let frameArea = 1920.0 * 1080

    @Test func aspectOfWidescreenQuad() {
        let quad = rect(0, 0, 1600, 900)
        #expect(abs(quad.aspect - 16.0 / 9) < 0.001)
        #expect(quad.area == 1600 * 900)
        #expect(quad.center == Point(x: 800, y: 450))
    }

    @Test func distanceIsMeanCornerOffset() {
        #expect(rect(0, 0, 100, 50).distance(to: rect(10, 0, 100, 50)) == 10)
    }

    @Test func rejectsSquareAndTiny() {
        #expect(QuadPicker.pick([rect(0, 0, 600, 600), rect(0, 0, 160, 90)], near: nil, frameArea: frameArea) == nil)
    }

    @Test func prefersWidescreenNearPrevious() {
        let big = rect(100, 100, 1600, 900)
        let nearby = rect(410, 160, 1050, 600)
        let previous = rect(420, 165, 1040, 590)
        #expect(QuadPicker.pick([big, nearby], near: previous, frameArea: frameArea) == nearby)
    }

    @Test func largestWithoutPrevious() {
        let big = rect(100, 100, 1600, 900)
        let small = rect(410, 160, 1050, 600)
        #expect(QuadPicker.pick([small, big], near: nil, frameArea: frameArea) == big)
    }

    @Test func emptyGivesNil() {
        #expect(QuadPicker.pick([], near: nil, frameArea: frameArea) == nil)
    }
}
