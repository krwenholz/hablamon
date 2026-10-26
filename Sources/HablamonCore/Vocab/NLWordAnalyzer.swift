#if canImport(NaturalLanguage)
    import NaturalLanguage

    /// Tags Spanish words with Apple's on-device NaturalLanguage models. Lemmas come from the
    /// glossary's inflection table first and the tagger second; word classes the other way round.
    public struct NLWordAnalyzer: WordAnalyzer {
        let glossary: BundledGlossary

        public init(glossary: BundledGlossary) {
            self.glossary = glossary
        }

        public func analyze(_ text: String) -> [AnalyzedWord] {
            let tagger = NLTagger(tagSchemes: [.lemma, .lexicalClass])
            tagger.string = text
            tagger.setLanguage(.spanish, range: text.startIndex..<text.endIndex)
            var words: [AnalyzedWord] = []
            tagger.enumerateTags(
                in: text.startIndex..<text.endIndex, unit: .word, scheme: .lexicalClass,
                options: [.omitPunctuation, .omitWhitespace]
            ) { tag, range in
                let surface = String(text[range])
                guard surface.first?.isLetter == true else { return true }
                let tagged = tagger.tag(at: range.lowerBound, unit: .word, scheme: .lemma).0?.rawValue.lowercased()
                // The glossary's inflection table is more reliable than the tagger ("puedes" → "podar"),
                // unless it names a lemma of another class ("hemos" → "hemo", a noun, for a verb).
                let taggedClass = Self.wordClass(tag)
                let fromGlossary = glossary.lemma(forForm: surface)
                let fromTagger = tagged.flatMap { glossary.isLemma($0) ? $0 : nil }
                let candidates = [fromGlossary, fromTagger].compactMap { $0 }
                let lemma =
                    candidates.first { candidate in taggedClass.map { glossary.has(candidate, as: $0) } ?? true }
                    ?? candidates.first ?? tagged ?? surface.lowercased()
                let wordClass = taggedClass ?? glossary.wordClass(of: lemma) ?? .other
                words.append(AnalyzedWord(surface: surface, lemma: lemma, wordClass: wordClass))
                return true
            }
            return words
        }

        static func wordClass(_ tag: NLTag?) -> WordClass? {
            switch tag {
            case .noun?: .noun
            case .verb?: .verb
            case .adjective?: .adjective
            case .adverb?: .adverb
            case nil, .otherWord?: nil
            default: .other
            }
        }
    }
#endif
