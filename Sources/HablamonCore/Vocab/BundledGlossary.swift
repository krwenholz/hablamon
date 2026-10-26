import Foundation

/// The Spanish-English glossary shipped in the app, built from Wiktionary by
/// `scripts/build-dictionary.py`. Lookups are exact, lowercased.
public struct BundledGlossary: GlossProvider, Sendable {
    struct Entry: Sendable {
        /// The first class listed, used when a word's class is unknown.
        var wordClass: WordClass
        var glosses: [WordClass: String]
    }

    private let lemmas: [String: Entry]
    private let forms: [String: String]

    init(lemmas: [String: Entry], forms: [String: String]) {
        self.lemmas = lemmas
        self.forms = forms
    }

    /// Parses the bundled table; takes about a second, so call it off the main thread.
    public static func load() throws -> BundledGlossary {
        guard let url = Bundle.module.url(forResource: "es-en", withExtension: "tsv", subdirectory: "dictionary")
        else { throw CocoaError(.fileNoSuchFile) }
        return parse(try String(contentsOf: url, encoding: .utf8))
    }

    static func parse(_ text: String) -> BundledGlossary {
        var lemmas: [String: Entry] = [:]
        var forms: [String: String] = [:]
        for line in text.split(separator: "\n") {
            let fields = line.split(separator: "\t", omittingEmptySubsequences: false)
            guard fields.count >= 3, let wordClass = WordClass(rawValue: String(fields[1])) else { continue }
            let lemma = String(fields[0])
            lemmas[lemma, default: Entry(wordClass: wordClass, glosses: [:])].glosses[wordClass] = String(fields[2])
            if fields.count > 3 {
                for form in fields[3].split(separator: ",") where forms[String(form)] == nil {
                    forms[String(form)] = lemma
                }
            }
        }
        return BundledGlossary(lemmas: lemmas, forms: forms)
    }

    public func gloss(for lemma: String, as wordClass: WordClass) -> String? {
        guard let entry = lemmas[lemma.lowercased()] else { return nil }
        return entry.glosses[wordClass] ?? entry.glosses[entry.wordClass]
    }

    public func isLemma(_ word: String) -> Bool {
        lemmas[word.lowercased()] != nil
    }

    /// The lemma for a word as written, or nil if the glossary doesn't know it.
    public func lemma(forForm form: String) -> String? {
        let form = form.lowercased()
        return lemmas[form] != nil ? form : forms[form]
    }

    public func wordClass(of lemma: String) -> WordClass? {
        lemmas[lemma.lowercased()]?.wordClass
    }
}
