import HablamonModels

/// What a key does in the window.
public enum KeyCommand: Equatable, Sendable {
    case repeatLast, repeatLastSlowly, toggleSpeed, togglePause, recalibrate, holdForEnglish
}

/// Matches typed keys against `settings.json`'s `keys`. Keys arrive as typed characters, so they
/// follow the keyboard layout (Dvorak's E is E).
public struct KeyMap: Sendable {
    private let bindings: [(key: String, shift: Bool, command: KeyCommand)]

    public init(_ keys: Keys) {
        func parse(_ text: String, _ command: KeyCommand) -> (String, Bool, KeyCommand) {
            let shift = text.hasPrefix("shift+")
            let key = shift ? String(text.dropFirst("shift+".count)) : text
            return (key == "space" ? " " : key, shift, command)
        }
        bindings = [
            parse(keys.repeatLast, .repeatLast), parse(keys.repeatLastSlowly, .repeatLastSlowly),
            parse(keys.toggleSpeed, .toggleSpeed), parse(keys.togglePause, .togglePause),
            parse(keys.recalibrate, .recalibrate), parse(keys.holdForEnglish, .holdForEnglish),
        ]
    }

    /// `characters` is the key as typed without modifiers; `shift` whether shift was held.
    public func command(for characters: String, shift: Bool) -> KeyCommand? {
        let key = characters.lowercased()
        return bindings.first { $0.key == key && $0.shift == shift }?.command
    }

    /// How a key is shown in hints: `shift+r` → `⇧R`, `space` → `␣`.
    public static func label(_ key: String) -> String {
        let shift = key.hasPrefix("shift+")
        let base = shift ? String(key.dropFirst("shift+".count)) : key
        return (shift ? "⇧" : "") + (base == "space" ? "␣" : base.uppercased())
    }
}
