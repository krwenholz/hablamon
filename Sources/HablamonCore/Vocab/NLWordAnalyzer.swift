#if canImport(NaturalLanguage)
    import NaturalLanguage

    /// Tags Spanish words with Apple's on-device NaturalLanguage models. When the tagger has no
    /// lemma, or one the glossary doesn't know, the glossary's inflection table decides.
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
                let lemma =
                    tagged.flatMap { glossary.isLemma($0) ? $0 : nil }
                    ?? glossary.lemma(forForm: surface) ?? tagged ?? surface.lowercased()
                let wordClass = Self.wordClass(tag) ?? glossary.wordClass(of: lemma) ?? .other
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
