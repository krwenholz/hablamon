import Foundation

/// Official English names for Spanish game terms (moves, items, Pokémon, abilities, types…),
/// built from PokéAPI by `scripts/build-game-terms.py`. Exact names, so menus read as the English
/// game would show them.
public struct GameTerms: Sendable {
    private let english: [String: String]

    init(english: [String: String]) {
        self.english = english
    }

    public static func bundled() throws -> GameTerms {
        guard
            let url = Bundle.module.url(forResource: "terms", withExtension: "tsv", subdirectory: "game-terms")
        else { throw CocoaError(.fileNoSuchFile) }
        var english: [String: String] = [:]
        for line in try String(contentsOf: url, encoding: .utf8).split(separator: "\n") {
            let fields = line.split(separator: "\t")
            guard fields.count >= 2 else { continue }
            let key = DialogueText.matchKey(String(fields[0]))
            if english[key] == nil { english[key] = String(fields[1]) }
        }
        return GameTerms(english: english)
    }

    /// The official English for a block of on-screen text, if the whole block is one game term,
    /// ignoring counters like "PP 35/35" or "x3".
    public func english(for text: String) -> String? {
        if let exact = english[DialogueText.matchKey(text)] { return exact }
        let words = text.split(separator: " ").filter { word in
            let letters = word.filter(\.isLetter)
            return letters.count >= 2 && !(letters.count <= 2 && letters.allSatisfy(\.isUppercase))
        }
        guard !words.isEmpty, words.count < text.split(separator: " ").count else { return nil }
        return english[DialogueText.matchKey(words.joined(separator: " "))]
    }
}
