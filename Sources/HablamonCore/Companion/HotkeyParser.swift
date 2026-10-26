/// A hotkey from `settings.json`, such as `opt+shift+cmd+R`.
public struct ParsedHotkey: Equatable, Sendable {
    public var key: Character
    public var control: Bool
    public var option: Bool
    public var shift: Bool
    public var command: Bool

    public init(key: Character, control: Bool, option: Bool, shift: Bool, command: Bool) {
        self.key = key
        self.control = control
        self.option = option
        self.shift = shift
        self.command = command
    }

    /// Nil unless there's at least one modifier and exactly one letter or digit at the end.
    public static func parse(_ text: String) -> ParsedHotkey? {
        var parts = text.split(separator: "+", omittingEmptySubsequences: false).map(String.init)
        guard parts.count >= 2, let last = parts.popLast(), last.count == 1, let key = last.first,
            key.isLetter || key.isNumber
        else { return nil }
        var hotkey = ParsedHotkey(
            key: Character(key.uppercased()), control: false, option: false, shift: false, command: false)
        for part in parts {
            switch part {
            case "ctrl": hotkey.control = true
            case "opt": hotkey.option = true
            case "shift": hotkey.shift = true
            case "cmd": hotkey.command = true
            default: return nil
            }
        }
        return hotkey
    }
}
