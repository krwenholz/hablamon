import Testing

@testable import HablamonCore

@Suite struct FreeSpeechTests {
    func block(_ id: Int, _ text: String, x: Double, y: Double, width: Double, height: Double = 0.05) -> TextBlock {
        TextBlock(id: id, text: text, box: NormalizedRect(x: x, y: y, width: width, height: height))
    }

    @Test func subtitlesAreLowAndCentered() {
        let found = FreeSpeech.find(
            in: [block(0, "Os voy a explicar en qué va a consistir el proyecto.", x: 0.32, y: 0.78, width: 0.36)],
            brightness: { _ in 0.5 })
        #expect(
            found == [
                FreeSpeech(text: "Os voy a explicar en qué va a consistir el proyecto.", speaker: nil, kind: .subtitle)
            ])
    }

    @Test func bubblesSitOnALightBackground() {
        let found = FreeSpeech.find(
            in: [block(0, "¿Se acabaron las clases por hoy?", x: 0.62, y: 0.25, width: 0.11)], brightness: { _ in 0.75 }
        )
        #expect(found.map(\.kind) == [.bubble])
    }

    @Test func notificationsBannersAndMenusAreNotSpeech() {
        let blocks = [
            block(0, "¡Hay una clase de Historia disponible!", x: 0.73, y: 0.21, width: 0.2),
            block(1, "¡Usa la aplicación mapa para ver adónde ir!", x: 0.28, y: 0.07, width: 0.27),
            block(2, "Luchar", x: 0.78, y: 0.77, width: 0.06),
            block(3, "Rotar mapa", x: 0.67, y: 0.85, width: 0.07),
        ]
        #expect(FreeSpeech.find(in: blocks, brightness: { $0.x > 0.7 ? 0.4 : 0.55 }).isEmpty)
    }

    @Test func lightNotificationsInTheUpperRightAreNotBubbles() {
        // As read on the phone: light cards that would otherwise pass as speech bubbles.
        let blocks = [
            block(0, "¡¡La Pokédex se ha actualizado!", x: 0.71, y: 0.18, width: 0.22),
            block(1, "¡Hay una clase de Arte disponible!", x: 0.72, y: 0.26, width: 0.21),
        ]
        #expect(FreeSpeech.find(in: blocks, brightness: { _ in 0.8 }).isEmpty)
    }

    @Test func dialogueModeReadsTheBoxWhateverItsColours() {
        // Mencía's green-on-black call box: no white panel to detect, just text.
        let found = FreeSpeech.find(
            in: [
                block(0, "Mencía", x: 0.33, y: 0.64, width: 0.08, height: 0.04),
                block(1, "¡Hola, Miguel! Soy yo, ¿quién si no?", x: 0.29, y: 0.70, width: 0.30),
            ], dialogue: true, brightness: { _ in 0.1 })
        #expect(found == [FreeSpeech(text: "¡Hola, Miguel! Soy yo, ¿quién si no?", speaker: "Mencía", kind: .dialogue)])
    }

    @Test func aShortExclamationIsDialogue() {
        let found = FreeSpeech.find(
            in: [block(0, "¿Cómo? ¡¿Dónde?!", x: 0.29, y: 0.72, width: 0.12)], dialogue: true, brightness: { _ in 0.9 })
        #expect(found.map(\.kind) == [.dialogue])
    }

    @Test func aLineStillTypingOutIsNotDialogueYet() {
        let typing = block(
            0, "¿Qué tal te va con los gimnasios? ¿Bien? ¿Cuál tienes en el pu", x: 0.29, y: 0.70, width: 0.4)
        #expect(FreeSpeech.find(in: [typing], dialogue: true, brightness: { _ in 0.9 }).isEmpty)
    }

    @Test func dialogueModeStillSkipsNotifications() {
        let card = block(0, "¡Hay una clase de Arte disponible!", x: 0.72, y: 0.26, width: 0.21)
        #expect(FreeSpeech.find(in: [card], dialogue: true, brightness: { _ in 0.8 }).isEmpty)
    }

    @Test func aWhiteDialogueBoxIsLeftToTheDialogueReader() {
        let box = block(0, "Menuda estampa se ve desde aquí arriba, ¿eh?", x: 0.29, y: 0.76, width: 0.40)
        #expect(FreeSpeech.find(in: [box], brightness: { _ in 0.86 }).isEmpty)
    }

    @Test func linesAlreadyReadFromADialogueBoxAreSkipped() {
        var tracker = FreeSpeechTracker()
        tracker.alreadySaid("¡Mira, Miguel! Eso de allí es Ciudad Meseta.")
        let line = FreeSpeech(text: "¡Mira, Miguel! Eso de allí es Ciudad Meseta.", speaker: nil, kind: .subtitle)
        _ = tracker.observe([line], at: 0)
        #expect(tracker.observe([line], at: 1.5).isEmpty)
    }

    @Test func aNameJustAboveIsTheSpeaker() {
        let found = FreeSpeech.find(
            in: [
                block(0, "Casiopea", x: 0.30, y: 0.67, width: 0.06, height: 0.04),
                block(1, "Es sobre la Operación Stardust, ¿te acuerdas?", x: 0.29, y: 0.74, width: 0.37),
            ], brightness: { _ in 0.3 })
        #expect(found.map(\.speaker) == ["Casiopea"])
    }

    @Test func speaksOnceAfterTwoSightings() {
        var tracker = FreeSpeechTracker()
        let line = FreeSpeech(text: "¿Se acabaron las clases por hoy?", speaker: nil, kind: .bubble)
        #expect(tracker.observe([line], at: 0).isEmpty, "seen once could be a misread")
        #expect(tracker.observe([line], at: 1.5) == [line])
        #expect(tracker.observe([line], at: 3).isEmpty, "already spoken while it stays on screen")
        #expect(tracker.observe([], at: 4.5).isEmpty)
        #expect(tracker.observe([], at: 7).isEmpty)
        #expect(tracker.observe([line], at: 8).isEmpty)
        #expect(tracker.observe([line], at: 9.5) == [line], "after it went away, it can be said again")
    }

    @Test func waitsUntilALineStopsTypingOut() {
        var tracker = FreeSpeechTracker()
        func line(_ text: String) -> FreeSpeech { FreeSpeech(text: text, speaker: "Mencía", kind: .dialogue) }
        let full = line("Antes de afrontar un gimnasio, siempre visitaba la arena de combate local.")
        #expect(
            tracker.observe([line("Antes de afrontar un gimnasio, siempre visitaba la arena de combate.")], at: 0)
                .isEmpty)
        #expect(tracker.observe([full], at: 0.5).isEmpty, "still growing")
        #expect(tracker.observe([full], at: 1) == [full], "two reads agree")
        #expect(tracker.observe([full], at: 1.5).isEmpty)
    }

    @Test func smallOCRJitterCountsAsTheSameLine() {
        var tracker = FreeSpeechTracker()
        _ = tracker.observe(
            [FreeSpeech(text: "Mi objetivo es que este proyecto os sirva.", speaker: nil, kind: .subtitle)], at: 0)
        let second = FreeSpeech(text: "Mi objetivo es que este proyecto los sirva.", speaker: nil, kind: .subtitle)
        #expect(tracker.observe([second], at: 1.5) == [second])
    }
}
