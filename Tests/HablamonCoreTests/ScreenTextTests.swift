import Testing

@testable import HablamonCore

@Suite struct ScreenTextTests {
    func line(_ text: String, x: Double, y: Double, width: Double, height: Double = 0.04, confidence: Double = 0.9)
        -> RecognizedLine
    {
        RecognizedLine(
            text: text, confidence: confidence, box: NormalizedRect(x: x, y: y, width: width, height: height))
    }

    @Test func wrappedParagraphBecomesOneBlock() {
        let blocks = ScreenText.blocks(from: [
            line("Un ataque que araña al objetivo con", x: 0.55, y: 0.60, width: 0.38),
            line("garras afiladas.", x: 0.55, y: 0.645, width: 0.16),
        ])
        #expect(blocks.map(\.text) == ["Un ataque que araña al objetivo con garras afiladas."])
        #expect(abs(blocks[0].box.y - 0.60) < 0.001)
        #expect(abs(blocks[0].box.height - 0.085) < 0.001)
    }

    @Test func shortBubbleLinesJoinWhenTheSentenceContinues() {
        let blocks = ScreenText.blocks(from: [
            line("¿Se acabaron las", x: 0.47, y: 0.30, width: 0.12),
            line("clases por hoy?", x: 0.47, y: 0.345, width: 0.12),
        ])
        #expect(blocks.map(\.text) == ["¿Se acabaron las clases por hoy?"])
    }

    @Test func menuRowsStaySeparate() {
        let blocks = ScreenText.blocks(from: [
            line("Arañazo", x: 0.70, y: 0.50, width: 0.10),
            line("Gruñido", x: 0.70, y: 0.545, width: 0.10),
            line("Látigo", x: 0.70, y: 0.59, width: 0.09),
        ])
        #expect(blocks.map(\.text) == ["Arañazo", "Gruñido", "Látigo"])
    }

    @Test func columnsSideBySideStaySeparate() {
        let blocks = ScreenText.blocks(from: [
            line("Ataque físico muy potente que", x: 0.05, y: 0.30, width: 0.30),
            line("Nivel 12", x: 0.60, y: 0.335, width: 0.10),
        ])
        #expect(blocks.count == 2)
    }

    @Test func farApartLinesStaySeparate() {
        let blocks = ScreenText.blocks(from: [
            line("¿Qué debería hacer Sprigatito?", x: 0.10, y: 0.80, width: 0.40),
            line("Mochila", x: 0.10, y: 0.20, width: 0.40),
        ])
        #expect(blocks.map(\.text) == ["Mochila", "¿Qué debería hacer Sprigatito?"], "top to bottom")
    }

    @Test func junkIsDropped() {
        let blocks = ScreenText.blocks(from: [
            line("35/35", x: 0.1, y: 0.1, width: 0.05),
            line("PP", x: 0.2, y: 0.1, width: 0.03),
            line("x", x: 0.3, y: 0.1, width: 0.01),
            line("Pociones", x: 0.4, y: 0.1, width: 0.1, confidence: 0.2),
            line("Bayas", x: 0.5, y: 0.3, width: 0.06),
        ])
        #expect(blocks.map(\.text) == ["Bayas"])
    }

    @Test func scenerySymbolsAndOtherScriptsAreDropped() {
        let blocks = ScreenText.blocks(from: [
            line("= =)09s A", x: 0.1, y: 0.1, width: 0.1),
            line("МА ЛЕо", x: 0.3, y: 0.1, width: 0.1),
            line("¿Sabes si siguen ahí?", x: 0.1, y: 0.5, width: 0.3),
            line("Poción x3", x: 0.1, y: 0.7, width: 0.1),
        ])
        #expect(blocks.map(\.text) == ["¿Sabes si siguen ahí?", "Poción x3"])
    }

    @Test func blocksExcludingARegionSkipTheDialogueBox() {
        let box = NormalizedRect(x: 0.2, y: 0.7, width: 0.6, height: 0.2)
        let blocks = ScreenText.blocks(
            from: [line("¡Hola, Miguel!", x: 0.25, y: 0.75, width: 0.3), line("Mochila", x: 0.1, y: 0.1, width: 0.1)],
            excluding: box)
        #expect(blocks.map(\.text) == ["Mochila"])
    }
}

@Suite struct ScreenTranslationTests {
    let terms = GameTerms(english: ["aranazo": "Scratch", "pocion": "Potion"])
    func block(_ id: Int, _ text: String) -> TextBlock {
        TextBlock(id: id, text: text, box: NormalizedRect(x: 0, y: Double(id) * 0.1, width: 0.2, height: 0.05))
    }

    @Test func gameTermsAreTranslatedRightAway() {
        let translation = ScreenTranslation(
            blocks: [block(0, "Arañazo"), block(1, "¿Qué hará Sprigatito?")], terms: terms)
        #expect(translation.english(for: 0) == "Scratch")
        #expect(translation.english(for: 1) == nil)
        #expect(translation.pending.map(\.text) == ["¿Qué hará Sprigatito?"])
    }

    @Test func machineTranslationsFillIn() {
        var translation = ScreenTranslation(blocks: [block(0, "Mochila"), block(1, "Pokémon")], terms: terms)
        translation.translated(id: 0, english: "Bag")
        #expect(translation.english(for: 0) == "Bag")
        #expect(translation.pending.map(\.id) == [1])
        #expect(!translation.isComplete)
        translation.translated(id: 1, english: "Pokémon")
        #expect(translation.isComplete)
    }
}

@Suite struct TranslateKeyTests {
    @Test func tOpensTheScreenTranslation() {
        #expect(KeyMap(.defaults).command(for: "t", shift: false) == .translateScreen)
    }
}
