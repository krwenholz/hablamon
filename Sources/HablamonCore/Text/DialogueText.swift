import Foundation

/// Cleans OCR output from a dialogue box into the text that gets spoken and logged.
public enum DialogueText {
    /// UI glyphs that are part of the box, not the dialogue (the advance arrow in its various OCR forms).
    static let uiGlyphs: Set<Character> = ["▼", "▽", "▾", "▿", "⏷", "⯆", "🔻"]

    static let quoteReplacements: [Character: Character] = [
        "“": "\"", "”": "\"", "„": "\"", "‘": "'", "’": "'", "‚": "'",
    ]

    /// Joins OCR lines (top to bottom) into one string.
    ///
    /// Wrapped lines are joined with a space, a word hyphenated across a line break is rejoined,
    /// UI glyphs are dropped, curly quotes are straightened, and whitespace is collapsed.
    /// Spanish punctuation and accents (¡ ¿ ñ á …) are kept.
    public static func normalize(lines: [String]) -> String {
        var joined = ""
        for line in lines {
            let cleaned = clean(line)
            guard !cleaned.isEmpty else { continue }
            if joined.isEmpty {
                joined = cleaned
            } else if joined.last == "-", let first = cleaned.first, first.isLowercase {
                joined.removeLast()
                joined += cleaned
            } else {
                joined += " " + cleaned
            }
        }
        return joined
    }

    public static func normalize(_ text: String) -> String {
        normalize(lines: text.components(separatedBy: .newlines))
    }

    static func clean(_ line: String) -> String {
        let mapped = String(
            line.precomposedStringWithCanonicalMapping.compactMap { character -> Character? in
                if uiGlyphs.contains(character) { return nil }
                return quoteReplacements[character] ?? character
            }
        )
        return mapped.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// A comparison key that ignores case, accents, punctuation, and spacing,
    /// so small OCR jitter between samples of the same page compares equal.
    public static func matchKey(_ text: String) -> String {
        let folded = text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        return String(folded.filter { $0.isLetter || $0.isNumber })
    }
}

/// Decides what to say for each settled page within one dialogue box session.
///
/// It skips repeats of the same page despite small OCR differences, and handles Scarlet's
/// scrolling: when a long message pushes its first line up, the next page starts with the previous
/// page's last line, and only the new lines should be spoken.
public struct PageSequencer: Sendable {
    /// Pages (or lines) at least this similar, by `DialogueText.matchKey`, count as the same.
    public var threshold: Double
    private var previousLines: [String] = []

    public init(threshold: Double = 0.85) {
        self.threshold = threshold
    }

    /// Returns the text to speak for a settled page's OCR lines, or nil when there's nothing new.
    public mutating func next(lines: [String]) -> String? {
        let lines = lines.map(DialogueText.clean).filter { !DialogueText.matchKey($0).isEmpty }
        guard !lines.isEmpty else { return nil }
        defer { previousLines = lines }
        guard !previousLines.isEmpty else { return DialogueText.normalize(lines: lines) }

        if same(lines.joined(separator: " "), previousLines.joined(separator: " ")) {
            return nil
        }
        if lines.count > 1, let last = previousLines.last, same(lines[0], last) {
            return DialogueText.normalize(lines: Array(lines.dropFirst()))
        }
        return DialogueText.normalize(lines: lines)
    }

    /// Call when the dialogue box goes away; the next box may legitimately repeat a line.
    public mutating func reset() {
        previousLines = []
    }

    private func same(_ a: String, _ b: String) -> Bool {
        similarity(DialogueText.matchKey(a), DialogueText.matchKey(b)) >= threshold
    }
}
