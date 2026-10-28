import Testing

@testable import HablamonCore

@Suite struct PlaybackProgressTests {
    let text = "Hola, Miguel. ¿Qué tal?"

    @Test func startAndEnd() {
        #expect(PlaybackProgress.offset(fraction: 0, in: text) == 0)
        #expect(PlaybackProgress.offset(fraction: 1, in: text) == text.utf16.count)
        #expect(PlaybackProgress.offset(fraction: 1.4, in: text) == text.utf16.count)
    }

    @Test func snapsToTheStartOfTheCurrentWord() {
        // Halfway lands inside "Miguel." or the following space; the offset is a word start.
        let offset = PlaybackProgress.offset(fraction: 0.5, in: text)
        let starts = [0, 6, 14, 19]  // "Hola,", "Miguel.", "¿Qué", "tal?"
        #expect(starts.contains(offset))
        #expect(offset > 0 && offset < text.utf16.count)
    }

    @Test func neverGoesBackwardsAsPlaybackAdvances() {
        var last = 0
        for step in 0...20 {
            let offset = PlaybackProgress.offset(fraction: Double(step) / 20, in: text)
            #expect(offset >= last)
            last = offset
        }
    }
}

@Suite struct SpeechBudgetTests {
    @Test func capGrowsWithTextAndLeavesRoom() {
        let short = SpeechBudget.maxFrames(for: "¿Cómo?")
        let long = SpeechBudget.maxFrames(for: String(repeating: "palabra ", count: 20))
        #expect(short >= 24 + 12, "even a one-word line gets a couple of seconds")
        #expect(long > short)
        // ~160 characters is about 13 s spoken; the cap allows double plus two seconds, not minutes.
        #expect(long < 12 * 40)
    }
}

@Suite struct SpeechChunkerTests {
    @Test func splitsSentences() {
        #expect(
            SpeechChunker.chunks("¡Ah! Antes de que se me olvide... Nos hemos cruzado con dos miembros del Team Star.")
                == ["¡Ah! Antes de que se me olvide...", "Nos hemos cruzado con dos miembros del Team Star."])
        #expect(SpeechChunker.chunks("¿Cómo? ¡¿Dónde?!") == ["¿Cómo? ¡¿Dónde?!"], "tiny sentences stay together")
    }

    @Test func splitsLongSentencesAtACommaNearTheMiddle() {
        let line =
            "Está muy bien que quieras ayudar a los demás, pero no puedes meterte en líos ya en tu primer día, Miguel."
        let chunks = SpeechChunker.chunks(line)
        #expect(chunks.count == 2)
        #expect(chunks[0] == "Está muy bien que quieras ayudar a los demás,")
    }

    @Test func shortLinesAreOneChunk() {
        #expect(SpeechChunker.chunks("Hola, Miguel.") == ["Hola, Miguel."])
    }

    @Test func chunksRebuildTheLine() {
        let line =
            "Gracias por avisarme de algo tan grave. ¿Sabes si siguen ahí? Bueno, como ves, de aquí a la academia aún hay un buen trecho."
        #expect(SpeechChunker.chunks(line).joined(separator: " ") == line)
        #expect(SpeechChunker.offsets(of: SpeechChunker.chunks(line), in: line).first == 0)
    }
}
