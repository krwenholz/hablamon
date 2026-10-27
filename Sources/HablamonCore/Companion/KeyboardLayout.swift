#if canImport(Carbon)
    import Carbon.HIToolbox
    import Foundation

    /// Finds which physical key types a character in a keyboard layout. Carbon hotkeys are
    /// registered by key code (a physical position), so "E" on Dvorak is a different key than on QWERTY.
    public struct KeyboardLayout {
        private let data: Data

        /// The layout the user is typing with now.
        public static func current() -> KeyboardLayout? {
            guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue() else { return nil }
            return KeyboardLayout(source: source)
        }

        /// An installed layout by input source ID, such as `com.apple.keylayout.Dvorak`.
        public init?(inputSourceID: String) {
            let filter = [kTISPropertyInputSourceID as String: inputSourceID] as CFDictionary
            guard let list = TISCreateInputSourceList(filter, true)?.takeRetainedValue() as? [TISInputSource],
                let source = list.first
            else { return nil }
            self.init(source: source)
        }

        init?(source: TISInputSource) {
            guard let pointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return nil }
            data = Unmanaged<CFData>.fromOpaque(pointer).takeUnretainedValue() as Data
        }

        /// The key code that types `character`, uppercase or lowercase. With `command`, layouts like
        /// "Dvorak – QWERTY ⌘" answer with the key they use while ⌘ is held.
        public func keyCode(for character: Character, command: Bool) -> Int? {
            let target = String(character).lowercased()
            let modifiers = UInt32(command ? (cmdKey >> 8) & 0xFF : 0)
            return data.withUnsafeBytes { buffer -> Int? in
                guard let layout = buffer.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else {
                    return nil
                }
                for code in 0..<128 {
                    var deadKeys: UInt32 = 0
                    var length = 0
                    var characters = [UniChar](repeating: 0, count: 4)
                    let status = UCKeyTranslate(
                        layout, UInt16(code), UInt16(kUCKeyActionDown), modifiers, UInt32(LMGetKbdType()),
                        OptionBits(kUCKeyTranslateNoDeadKeysBit), &deadKeys, characters.count, &length, &characters)
                    guard status == noErr, length > 0 else { continue }
                    if String(utf16CodeUnits: characters, count: length).lowercased() == target { return code }
                }
                return nil
            }
        }
    }
#endif
