#if canImport(NaturalLanguage)
    import Testing

    @testable import HablamonCore

    @Suite struct NLWordAnalyzerTests {
        let analyzer: NLWordAnalyzer

        init() throws {
            analyzer = NLWordAnalyzer(glossary: try BundledGlossary.load())
        }

        @Test func lemmatizesSpanishVerbs() {
            let words = analyzer.analyze("Hemos combatido en el vestíbulo.")
            let combatido = words.first { $0.surface == "combatido" }
            #expect(combatido?.lemma == "combatir")
            #expect(combatido?.wordClass == .verb)
            #expect(words.first { $0.surface == "vestíbulo" }?.wordClass == .noun)
            #expect(words.first { $0.surface == "el" }?.wordClass == .other)
        }

        @Test func fallsBackToGlossaryForms() {
            // "líos" should come back to "lío" even if the tagger has no lemma for it.
            #expect(analyzer.analyze("en líos").first { $0.surface == "líos" }?.lemma == "lío")
        }

        @Test func glossaryFormsBeatTheTagger() {
            // The tagger lemmatizes "puedes" as "podar" (to prune); the glossary knows it's "poder".
            #expect(analyzer.analyze("no puedes").first { $0.surface == "puedes" }?.lemma == "poder")
        }

        @Test func lemmaMustMatchTheTaggedClass() {
            // The glossary lists "hemos" as a plural of "hemo" (noun); as a verb it's "haber".
            #expect(analyzer.analyze("Nos hemos cruzado").first { $0.surface == "hemos" }?.lemma == "haber")
        }

        @Test func personalNamesAreNotVocabulary() {
            #expect(analyzer.analyze("Miguel los ha espantado.").first?.wordClass == .other)
        }

        @Test func skipsPunctuation() {
            #expect(analyzer.analyze("¡¿Qué es?!").allSatisfy { !$0.surface.isEmpty && $0.surface.first!.isLetter })
        }
    }
#endif
