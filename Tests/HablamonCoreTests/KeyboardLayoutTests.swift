#if canImport(Carbon)
    import Carbon.HIToolbox
    import Testing

    @testable import HablamonCore

    /// Hotkeys name letters; Carbon wants physical key codes, which depend on the layout.
    @Suite struct KeyboardLayoutTests {
        func layout(_ id: String) throws -> KeyboardLayout {
            try #require(KeyboardLayout(inputSourceID: id), "\(id) isn't installed")
        }

        @Test func qwertyLettersMapToTheirOwnKeys() throws {
            let qwerty = try layout("com.apple.keylayout.US")
            #expect(qwerty.keyCode(for: "E", command: true) == kVK_ANSI_E)
            #expect(qwerty.keyCode(for: "R", command: true) == kVK_ANSI_R)
        }

        @Test func dvorakLettersMapToDvorakPositions() throws {
            let dvorak = try layout("com.apple.keylayout.Dvorak")
            // Dvorak's E sits where QWERTY has D; its R where QWERTY has O.
            #expect(dvorak.keyCode(for: "E", command: true) == kVK_ANSI_D)
            #expect(dvorak.keyCode(for: "R", command: true) == kVK_ANSI_O)
            #expect(dvorak.keyCode(for: "1", command: true) == kVK_ANSI_1)
        }

        @Test func dvorakQwertyCommandUsesQwertyWithCommand() throws {
            let layout = try layout("com.apple.keylayout.DVORAK-QWERTYCMD")
            #expect(layout.keyCode(for: "E", command: true) == kVK_ANSI_E)
        }
    }
#endif
