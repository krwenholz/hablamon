import Testing

@testable import HablamonCore

@Suite struct DialogueTextTests {
    @Test func joinsWrappedLines() {
        // From photos/trainer-challenge_near_straight.jpeg
        let text = DialogueText.normalize(lines: [
            "Si quieres combatir contra Entrenadores como",
            "yo, tan solo tienes que hablarnos. ▽",
        ])
        #expect(text == "Si quieres combatir contra Entrenadores como yo, tan solo tienes que hablarnos.")
    }

    @Test func keepsSpanishPunctuationAndAccents() {
        #expect(DialogueText.normalize("¡Sí que son fuertes tus Pokémon! ▼") == "¡Sí que son fuertes tus Pokémon!")
        #expect(DialogueText.normalize("¿A que impresiona?") == "¿A que impresiona?")
    }

    @Test func rejoinsHyphenatedWords() {
        #expect(DialogueText.normalize(lines: ["la acade-", "mia es grande"]) == "la academia es grande")
        // A dash before a capital is real punctuation, not a broken word.
        #expect(DialogueText.normalize(lines: ["Bueno -", "Mencía"]) == "Bueno - Mencía")
    }

    @Test func straightensQuotesAndCollapsesSpace() {
        #expect(DialogueText.normalize("  “Hola”   dijo  ") == "\"Hola\" dijo")
    }

    @Test func composesDecomposedAccents() {
        let decomposed = "Menci\u{301}a"
        #expect(DialogueText.normalize(decomposed).unicodeScalars.count == "Mencía".unicodeScalars.count)
    }

    @Test func matchKeyIgnoresCaseAccentsAndPunctuation() {
        #expect(DialogueText.matchKey("¡Sí que son fuertes!") == DialogueText.matchKey("si que son FUERTES"))
    }
}

@Suite struct PageSequencerTests {
    /// Feeds settled pages in order and returns what would be spoken for each.
    func spoken(_ pages: [[String]], resetBefore: Set<Int> = []) -> [String?] {
        var sequencer = PageSequencer()
        return pages.enumerated().map { index, page in
            if resetBefore.contains(index) { sequencer.reset() }
            return sequencer.next(lines: page)
        }
    }

    @Test func skipsRepeatsDespiteOCRJitter() {
        let result = spoken([
            ["¡Sí que son fuertes tus Pokémon!"],
            ["¡Sí que son fuertes tus Pokémon!"],
            ["¡Si que son fuertes tus Pokemon!"],
            ["¡Sí que son fuertes tus Pokérnon!"],
        ])
        #expect(result == ["¡Sí que son fuertes tus Pokémon!", nil, nil, nil])
    }

    /// Real pages from far.mp4 (78–84 s): the third line pushed the first one up.
    @Test func speaksOnlyTheNewLineWhenTextScrolls() {
        let result = spoken([
            ["Todos esos parajes están repletos de Pokémon,", "y ¿sabes qué es lo mejor? ¡Que están deseando"],
            ["y ¿sabes qué es lo mejor? ¡Que están deseando", "conocerte!"],
        ])
        #expect(
            result == [
                "Todos esos parajes están repletos de Pokémon, y ¿sabes qué es lo mejor? ¡Que están deseando",
                "conocerte!",
            ]
        )
    }

    @Test func scrollToleratesOCRDifferences() {
        // Same scroll, with the repeated line read slightly differently the second time (from the OCR report).
        let result = spoken([
            ["Todos esos parajes están repletos de Pokémon,", "y ¿sabes qué es lo mejor? ¡Que están deseando »"],
            ["y ¿sabes qué es lo mejor? ¡Que están deseando", "conocertel"],
        ])
        #expect(result.last == "conocertel")
    }

    @Test func speaksANewPage() {
        let result = spoken([
            ["¿A que te alegras de haberte mudado a Paldea?", "¡Bienvenido a tu nuevo hogar!"],
            ["Bueno, como ves, de aquí a la academia aún hay", "un buen trecho."],
        ])
        #expect(result[1] == "Bueno, como ves, de aquí a la academia aún hay un buen trecho.")
    }

    @Test func resetAllowsTheSameLineInANewBox() {
        #expect(spoken([["¡Hola!"], ["¡Hola!"]], resetBefore: [1]) == ["¡Hola!", "¡Hola!"])
    }

    @Test func ignoresEmptyPages() {
        #expect(spoken([["  ▼ "]]) == [nil])
    }
}
