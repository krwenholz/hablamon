import Foundation
import Testing

@testable import HablamonCore

/// Splits on spaces; lemmas and classes come from a fixed table, everything else is `.other`.
struct FakeAnalyzer: WordAnalyzer {
    var table: [String: (String, WordClass)]

    func analyze(_ text: String) -> [AnalyzedWord] {
        text.split(separator: " ").map { raw in
            let surface = raw.trimmingCharacters(in: .punctuationCharacters)
            let (lemma, wordClass) = table[surface.lowercased()] ?? (surface.lowercased(), .other)
            return AnalyzedWord(surface: surface, lemma: lemma, wordClass: wordClass)
        }
    }
}

struct FakeGlosses: GlossProvider {
    var glosses: [String: String] = [:]
    func gloss(for lemma: String, as wordClass: WordClass) -> String? { glosses[lemma] }
}

@Suite struct VocabRankerTests {
    let analyzer = FakeAnalyzer(table: [
        "travesía": ("travesía", .noun), "academia": ("academia", .noun), "combatir": ("combatir", .verb),
        "combatimos": ("combatir", .verb), "vestíbulo": ("vestíbulo", .noun), "rápido": ("rápido", .adverb),
        "mencía": ("mencía", .noun), "hemos": ("haber", .verb),
    ])

    func ranker(history: [String] = [], known: Set<String> = [], glosses: [String: String] = [:]) -> VocabRanker {
        VocabRanker(analyzer: analyzer, glosses: FakeGlosses(glosses: glosses), history: history, known: known)
    }

    @Test func functionWordsAndNamesNeverShow() {
        var vocab = ranker()
        vocab.add(line: "Hola Mencía la travesía")
        #expect(vocab.top().map(\.lemma) == ["travesía"])
    }

    @Test func knownNamesNeverShow() {
        var vocab = VocabRanker(
            analyzer: analyzer, glosses: FakeGlosses(), history: [], known: [], names: ["Mencía"])
        vocab.add(line: "mencía travesía")
        #expect(vocab.top().map(\.lemma) == ["travesía"])
    }

    @Test func wordsAfterSentenceEndsCountAsSentenceStarts() {
        var vocab = ranker()
        vocab.add(line: "¡Ah! Travesía larga.")
        #expect(vocab.top().map(\.lemma) == ["travesía"])
    }

    @Test func auxiliariesNeverShow() {
        var vocab = ranker()
        vocab.add(line: "hemos combatimos")
        #expect(vocab.top().map(\.lemma) == ["combatir"])
    }

    @Test func knownWordsNeverShow() {
        var vocab = ranker(known: ["academia"])
        vocab.add(line: "la academia y la travesía")
        #expect(vocab.top().map(\.lemma) == ["travesía"])
        vocab.markKnown("travesía")
        #expect(vocab.top().isEmpty)
    }

    @Test func frequentLemmaOutranksRareOne() {
        var vocab = ranker(history: Array(repeating: "la academia", count: 5) + ["la travesía"])
        vocab.add(line: "travesía academia")
        #expect(vocab.top().map(\.lemma) == ["academia", "travesía"])
    }

    @Test func newLemmaOutranksSeenOne() {
        var vocab = ranker(history: ["la academia", "la academia"])
        vocab.add(line: "academia travesía")
        #expect(vocab.top().first?.lemma == "travesía")
    }

    @Test func classWeightsBreakTies() {
        var vocab = ranker()
        vocab.add(line: "rápido vestíbulo")
        #expect(vocab.top().map(\.lemma) == ["vestíbulo", "rápido"])
    }

    @Test func inflectionsCollapseByLemma() {
        var vocab = ranker()
        vocab.add(line: "combatir y combatimos")
        #expect(vocab.top().map(\.lemma) == ["combatir"])
    }

    @Test func missingGlossStillRanks() {
        var vocab = ranker(glosses: ["vestíbulo": "lobby"])
        vocab.add(line: "vestíbulo travesía")
        let entries = vocab.top()
        #expect(entries.count == 2)
        #expect(entries.first { $0.lemma == "vestíbulo" }?.gloss == "lobby")
        #expect(entries.first { $0.lemma == "travesía" }?.gloss == nil)
    }

    @Test func sentenceIsMostRecentUse() {
        var vocab = ranker()
        vocab.add(line: "una travesía")
        vocab.add(line: "otra travesía larga")
        #expect(vocab.top().first?.sentence == "otra travesía larga")
    }

    @Test func onlyRecentLinesAreCandidates() {
        var vocab = ranker()
        vocab.add(line: "vestíbulo")
        for _ in 0..<VocabRanker.window { vocab.add(line: "travesía") }
        #expect(vocab.top().map(\.lemma) == ["travesía"])
    }

    @Test func tiesGoToTheMostRecentWord() {
        var vocab = ranker()
        vocab.add(line: "vestíbulo")
        vocab.add(line: "travesía")
        #expect(vocab.top().map(\.lemma) == ["travesía", "vestíbulo"])
    }

    @Test func topLimitsCount() {
        var vocab = ranker()
        vocab.add(line: "travesía academia vestíbulo combatir rápido")
        #expect(vocab.top(3).count == 3)
    }
}

@Suite struct BundledGlossaryTests {
    @Test func looksUpLemmasAndForms() throws {
        let glossary = try BundledGlossary.load()
        #expect(glossary.gloss(for: "vestíbulo", as: .noun)?.contains("lobby") == true)
        #expect(glossary.lemma(forForm: "combatimos") == "combatir")
        #expect(glossary.lemma(forForm: "combatir") == "combatir")
        #expect(glossary.wordClass(of: "combatir") == .verb)
        #expect(glossary.gloss(for: "zzzz", as: .noun) == nil)
        #expect(glossary.lemma(forForm: "lios") == "lío", "OCR often drops accents")
        #expect(glossary.gloss(for: "deber", as: .verb) != glossary.gloss(for: "deber", as: .noun))
        #expect(glossary.gloss(for: "deber", as: .adverb) != nil, "falls back to another class")
    }
}
