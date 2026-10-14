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

@Suite struct PageDeduplicatorTests {
    /// Feeds pages in order and returns which ones would be spoken.
    func spoken(_ pages: [String], resetBefore: Set<Int> = []) -> [Bool] {
        var dedupe = PageDeduplicator()
        return pages.enumerated().map { index, page in
            if resetBefore.contains(index) { dedupe.reset() }
            return dedupe.shouldSpeak(page)
        }
    }

    @Test func skipsRepeatsOfTheSamePage() {
        let result = spoken([
            "¡Sí que son fuertes tus Pokémon!",
            "¡Sí que son fuertes tus Pokémon!",
            // Misreads from camera jitter are still the same page.
            "¡Si que son fuertes tus Pokemon!",
            "¡Sí que son fuertes tus Pokérnon!",
        ])
        #expect(result == [true, false, false, false])
    }

    @Test func speaksANewPage() {
        let result = spoken(["Si quieres combatir contra Entrenadores como yo.", "¡Sí que son fuertes tus Pokémon!"])
        #expect(result == [true, true])
    }

    @Test func resetAllowsTheSameLineInANewBox() {
        #expect(spoken(["¡Hola!", "¡Hola!"], resetBefore: [1]) == [true, true])
    }

    @Test func ignoresEmptyText() {
        #expect(spoken(["  ▼ "]) == [false])
    }
}
