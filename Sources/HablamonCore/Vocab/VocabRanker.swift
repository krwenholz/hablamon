import Foundation

public enum WordClass: String, Sendable {
    case noun, verb, adjective, adverb, other
}

public struct AnalyzedWord: Equatable, Sendable {
    public var surface: String
    public var lemma: String
    public var wordClass: WordClass

    public init(surface: String, lemma: String, wordClass: WordClass) {
        self.surface = surface
        self.lemma = lemma
        self.wordClass = wordClass
    }
}

/// Splits a line into words with their lemma and word class.
public protocol WordAnalyzer: Sendable {
    func analyze(_ text: String) -> [AnalyzedWord]
}

/// Short English meanings for Spanish lemmas.
public protocol GlossProvider: Sendable {
    /// The meaning for that word class, or for another class when there's none.
    func gloss(for lemma: String, as wordClass: WordClass) -> String?
}

public struct VocabEntry: Equatable, Sendable, Identifiable {
    public var id: String { lemma }
    public var lemma: String
    public var surface: String
    public var wordClass: WordClass
    public var gloss: String?
    /// The most recent line the word appeared in.
    public var sentence: String
    public var score: Double
}

/// Picks the words worth showing from recent lines: new to the player, frequent in the game,
/// and carrying meaning (nouns and verbs over adverbs; names and function words never).
public struct VocabRanker: Sendable {
    /// How many recent lines supply candidates.
    public static let window = 20
    /// Content words that are too basic or too grammatical to be worth a card.
    static let stopLemmas: Set<String> = ["haber", "ser", "estar", "tener", "hacer", "ir", "poder", "decir"]
    static let classWeights: [WordClass: Double] = [.noun: 1.0, .verb: 1.0, .adjective: 0.8, .adverb: 0.5]

    private let analyzer: any WordAnalyzer
    private let glosses: any GlossProvider
    /// Lemma counts from earlier sessions.
    private let history: [String: Int]
    private var session: [String: Int] = [:]
    private var known: Set<String>
    /// Match keys of character names and aliases, which are never vocabulary.
    private let names: Set<String>
    private var recent: [(line: String, words: [AnalyzedWord])] = []

    public init(
        analyzer: any WordAnalyzer, glosses: any GlossProvider, history: [String], known: Set<String>,
        names: Set<String> = []
    ) {
        self.analyzer = analyzer
        self.glosses = glosses
        self.known = Set(known.map { $0.lowercased() })
        self.names = Set(names.map(DialogueText.matchKey))
        var counts: [String: Int] = [:]
        for line in history {
            for word in Self.contentWords(analyzer.analyze(line), in: line, names: self.names) {
                counts[word.lemma, default: 0] += 1
            }
        }
        self.history = counts
    }

    public mutating func add(line: String) {
        let words = Self.contentWords(analyzer.analyze(line), in: line, names: names)
        for word in words { session[word.lemma, default: 0] += 1 }
        recent.append((line, words))
        if recent.count > Self.window { recent.removeFirst(recent.count - Self.window) }
    }

    public mutating func markKnown(_ lemma: String) {
        known.insert(lemma.lowercased())
    }

    /// The words worth a card in one line, best first: new to the player, frequent in the game,
    /// and carrying meaning. Known words, names, and function words are left out.
    public func keyWords(in line: String, limit: Int = 4) -> [VocabEntry] {
        var seen = Set<String>()
        var entries: [VocabEntry] = []
        for word in Self.contentWords(analyzer.analyze(line), in: line, names: names)
        where !known.contains(word.lemma) && seen.insert(word.lemma).inserted {
            entries.append(entry(for: word, in: line))
        }
        return Array(
            entries.enumerated().sorted { a, b in
                a.element.score != b.element.score ? a.element.score > b.element.score : a.offset < b.offset
            }.map(\.element).prefix(limit))
    }

    private func entry(for word: AnalyzedWord, in line: String) -> VocabEntry {
        let seenBefore = history[word.lemma] != nil
        let frequency = (history[word.lemma] ?? 0) + (session[word.lemma] ?? 0)
        let score = (seenBefore ? 0 : 2.0) + log(1 + Double(frequency)) + (Self.classWeights[word.wordClass] ?? 0)
        return VocabEntry(
            lemma: word.lemma, surface: word.surface, wordClass: word.wordClass,
            gloss: glosses.gloss(for: word.lemma, as: word.wordClass), sentence: line, score: score)
    }

    public func top(_ count: Int = 5) -> [VocabEntry] {
        var entries: [String: VocabEntry] = [:]
        var lastSeen: [String: Int] = [:]
        for (index, (line, words)) in recent.enumerated() {
            for word in words where !known.contains(word.lemma) {
                // Later lines overwrite earlier ones, so the sentence is the most recent use.
                entries[word.lemma] = entry(for: word, in: line)
                lastSeen[word.lemma] = index
            }
        }
        return entries.values
            .sorted {
                if $0.score != $1.score { return $0.score > $1.score }
                let (first, second) = (lastSeen[$0.lemma] ?? 0, lastSeen[$1.lemma] ?? 0)
                return first != second ? first > second : $0.lemma < $1.lemma
            }
            .prefix(count)
            .map { $0 }
    }

    /// Nouns, verbs, adjectives, and adverbs, minus known names, other names (capitalized away from
    /// a sentence start), and stop lemmas.
    static func contentWords(_ words: [AnalyzedWord], in line: String, names: Set<String>) -> [AnalyzedWord] {
        var searchFrom = line.startIndex
        return words.compactMap { word in
            let range = line.range(of: word.surface, range: searchFrom..<line.endIndex)
            if let range { searchFrom = range.upperBound }
            guard word.wordClass != .other, word.surface.count >= 3 else { return nil }
            guard !names.contains(DialogueText.matchKey(word.surface)) else { return nil }
            if word.surface.first?.isUppercase == true, !startsSentence(line, at: range?.lowerBound) { return nil }
            var word = word
            word.lemma = word.lemma.lowercased()
            return stopLemmas.contains(word.lemma) ? nil : word
        }
    }

    /// True at the start of the line or after sentence punctuation (. ! ? … and Spanish ¡ ¿).
    static func startsSentence(_ line: String, at index: String.Index?) -> Bool {
        guard let index else { return false }
        let before = line[..<index].reversed().first { !$0.isWhitespace }
        return before.map { ".!?…¡¿".contains($0) } ?? true
    }
}
