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

/// Suppresses repeats of the same page within one box session, tolerating small OCR differences.
public struct PageDeduplicator: Sendable {
    /// Pages at least this similar (by `DialogueText.matchKey`) count as the same page.
    public var threshold: Double
    private var lastKey: String?

    public init(threshold: Double = 0.9) {
        self.threshold = threshold
    }

    /// Returns whether `text` is a new page worth speaking, and remembers it if so.
    public mutating func shouldSpeak(_ text: String) -> Bool {
        let key = DialogueText.matchKey(text)
        guard !key.isEmpty else { return false }
        if let lastKey, similarity(lastKey, key) >= threshold {
            return false
        }
        lastKey = key
        return true
    }

    /// Call when the dialogue box goes away; the next box may legitimately repeat a line.
    public mutating func reset() {
        lastKey = nil
    }
}
