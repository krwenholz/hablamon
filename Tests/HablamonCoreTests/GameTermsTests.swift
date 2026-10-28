import Testing

@testable import HablamonCore

@Suite struct GameTermsTests {
    let terms: GameTerms

    init() throws {
        terms = try GameTerms.bundled()
    }

    @Test func officialNamesBeatTranslation() {
        #expect(terms.english(for: "Arañazo") == "Scratch")
        #expect(terms.english(for: "Poción") == "Potion")
        #expect(terms.english(for: "Planta") == "Grass")
    }

    @Test func ignoresCaseAccentsAndSpacing() {
        #expect(terms.english(for: "ARAÑAZO") == "Scratch")
        #expect(terms.english(for: "  pocion ") == "Potion")
    }

    @Test func stripsCountersFromMenuRows() {
        #expect(terms.english(for: "Arañazo PP 35/35") == "Scratch")
        #expect(terms.english(for: "Poción x3") == "Potion")
    }

    @Test func unknownTextIsNil() {
        #expect(terms.english(for: "¿Qué debería hacer Sprigatito?") == nil)
        #expect(terms.english(for: "zzzz") == nil)
    }
}
