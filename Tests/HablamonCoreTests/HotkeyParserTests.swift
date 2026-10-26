import Testing

@testable import HablamonCore

@Suite struct HotkeyParserTests {
    @Test func parsesModifiersAndKey() {
        let parsed = ParsedHotkey.parse("opt+shift+cmd+R")
        #expect(parsed == ParsedHotkey(key: "R", control: false, option: true, shift: true, command: true))
    }

    @Test func parsesDigits() {
        #expect(ParsedHotkey.parse("ctrl+1")?.key == "1")
    }

    @Test func rejectsMalformed() {
        #expect(ParsedHotkey.parse("cmd+") == nil)
        #expect(ParsedHotkey.parse("hyper+R") == nil)
        #expect(ParsedHotkey.parse("R") == nil, "a bare key would steal typing")
        #expect(ParsedHotkey.parse("cmd+RR") == nil)
    }
}
