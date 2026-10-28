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

    @Test func smallOCRJitterCountsAsTheSameLine() {
        var tracker = FreeSpeechTracker()
        _ = tracker.observe(
            [FreeSpeech(text: "Mi objetivo es que este proyecto os sirva.", speaker: nil, kind: .subtitle)], at: 0)
        let second = FreeSpeech(text: "Mi objetivo es que este proyecto los sirva.", speaker: nil, kind: .subtitle)
        #expect(tracker.observe([second], at: 1.5) == [second])
    }
}
