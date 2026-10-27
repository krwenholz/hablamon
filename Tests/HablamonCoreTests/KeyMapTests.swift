import HablamonModels
import Testing

@testable import HablamonCore

@Suite struct KeyMapTests {
    let map = KeyMap(Keys.defaults)

    @Test func plainLettersMapToCommands() {
        #expect(map.command(for: "r", shift: false) == .repeatLast)
        #expect(map.command(for: "s", shift: false) == .toggleSpeed)
        #expect(map.command(for: "c", shift: false) == .recalibrate)
        #expect(map.command(for: "e", shift: false) == .holdForEnglish)
    }

    @Test func shiftAndSpace() {
        #expect(map.command(for: "R", shift: true) == .repeatLastSlowly)
        #expect(map.command(for: "r", shift: true) == .repeatLastSlowly)
        #expect(map.command(for: " ", shift: false) == .togglePause)
    }

    @Test func otherKeysPassThrough() {
        #expect(map.command(for: "x", shift: false) == nil)
        #expect(map.command(for: "s", shift: true) == nil)
    }

    @Test func labelsForHints() {
        #expect(KeyMap.label("shift+r") == "⇧R")
        #expect(KeyMap.label("space") == "␣")
        #expect(KeyMap.label("c") == "C")
    }
}
