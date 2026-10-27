import HablamonModels
import Testing

@testable import HablamonCore

/// A scripted frame: box visibility, tag, typing progress, and what OCR would return.
struct FakeFrame: DialogueFrame {
    var visible: Bool
    var tag: String?
    var page: Int
    var revealed: Double
    var lines: [String]
    var reads: Counter? = nil

    final class Counter: @unchecked Sendable { var bodyReads = 0 }

    func boxFeatures(_ profile: GameProfile) -> BoxFeatures {
        BoxFeatures(
            textEdgeDensity: visible ? 0.05 : 0.04,
            marginEdgeDensity: visible ? 0 : 0.05,
            tagFraction: tag == nil ? 0 : 0.8
        )
    }

    func settleCrop(_ profile: GameProfile) -> GrayImage {
        SyntheticPage.crop(revealed: revealed, seed: page)
    }

    func readBody(_ profile: GameProfile) -> [RecognizedLine] {
        reads?.bodyReads += 1
        return lines.map {
            RecognizedLine(text: $0, confidence: 1, box: NormalizedRect(x: 0, y: 0, width: 1, height: 0.1))
        }
    }

    func readNameTag(_ profile: GameProfile) -> [RecognizedLine] {
        [tag].compactMap { $0 }.map {
            RecognizedLine(text: $0, confidence: 0.5, box: NormalizedRect(x: 0, y: 0, width: 1, height: 1))
        }
    }
}

@Suite struct DialoguePipelineTests {
    let pipeline: DialoguePipeline

    init() throws {
        pipeline = DialoguePipeline(
            profile: try BundledData.profile("scarlet"),
            characters: try BundledData.defaultCharacters()
        )
    }

    /// Frames for one page: typing over `steps` samples, then held.
    func page(_ number: Int, tag: String?, lines: [String], steps: Int = 6, hold: Int = 5) -> [FakeFrame] {
        (1...(steps + hold)).map { index in
            FakeFrame(
                visible: true, tag: tag, page: number, revealed: min(1, Double(index) / Double(steps)), lines: lines)
        }
    }

    func empty(_ count: Int) -> [FakeFrame] {
        Array(repeating: FakeFrame(visible: false, tag: nil, page: 0, revealed: 0, lines: []), count: count)
    }

    func run(_ frames: [FakeFrame]) throws -> [PipelineEvent] {
        var pipeline = pipeline
        var events: [PipelineEvent] = []
        for (index, frame) in frames.enumerated() {
            events += try pipeline.process(frame, at: Double(index) * 0.25)
        }
        return events
    }

    func spoken(_ events: [PipelineEvent]) -> [SpokenPage] {
        events.compactMap { if case .speak(let page) = $0 { page } else { nil } }
    }

    @Test func speaksEachPageOnceAfterItSettles() throws {
        let events = try run(
            empty(4)
                + page(1, tag: "Mencia", lines: ["¡Mira, Miguel! Eso de allí es Ciudad Meseta."])
                + page(2, tag: "Mencía", lines: ["Montañas, prados, bosques..."])
                + empty(16)
        )
        let pages = spoken(events)
        #expect(pages.map(\.text) == ["¡Mira, Miguel! Eso de allí es Ciudad Meseta.", "Montañas, prados, bosques..."])
        #expect(pages.allSatisfy { $0.speaker.name == "Mencía" })
        #expect(pages.first?.speakerRaw == "Mencia")
        #expect(events.first == .dialogueStarted)
        #expect(events.last == .dialogueEnded)
        #expect(events.contains(.pageChanged))
    }

    @Test func doesNotOCRWhileTyping() throws {
        let counter = FakeFrame.Counter()
        var frames = page(1, tag: nil, lines: ["¡Has obtenido el Bocadillo!"], steps: 10, hold: 0)
        for index in frames.indices { frames[index].reads = counter }
        _ = try run(frames)
        #expect(counter.bodyReads == 0)
    }

    @Test func noTagIsNarration() throws {
        let pages = spoken(try run(page(1, tag: nil, lines: ["¡Has obtenido el Bocadillo!"])))
        #expect(pages.first?.speaker == .narrator)
        #expect(pages.first?.speakerRaw == nil)
    }

    @Test func scrollingSpeaksOnlyTheNewLine() throws {
        let pages = spoken(
            try run(
                page(
                    1, tag: "Mencía",
                    lines: [
                        "Todos esos parajes están repletos de Pokémon,",
                        "y ¿sabes qué es lo mejor? ¡Que están deseando",
                    ])
                    + page(2, tag: "Mencía", lines: ["y ¿sabes qué es lo mejor? ¡Que están deseando", "conocerte!"])
            )
        )
        #expect(pages.map(\.text).last == "conocerte!")
    }

    @Test func ignoresBoxlessFrames() throws {
        #expect(try run(empty(20)).isEmpty)
    }

    @Test func updatedCharactersApplyToNextPage() throws {
        var pipeline = DialoguePipeline(
            profile: try BundledData.profile("scarlet"), characters: CharacterTable(characters: [:]))
        var events: [PipelineEvent] = []
        var time = 0.0
        func feed(_ frames: [FakeFrame]) throws {
            for frame in frames {
                events += try pipeline.process(frame, at: time)
                time += 0.25
            }
        }
        try feed(page(1, tag: "Clavel", lines: ["Hola, Miguel. Hola, Mencía."]))
        pipeline.updateCharacters(try BundledData.defaultCharacters())
        try feed(page(2, tag: "Clavel", lines: ["¿Qué tal ha ido tu primera travesía hasta la academia?"]))
        let speakers = spoken(events).map(\.speaker)
        #expect(speakers.first == .unknown(tag: "Clavel"))
        #expect(speakers.last?.name == "Clavel")
        if case .known = speakers.last {} else { Issue.record("expected Clavel to be known after the update") }
    }

    @Test func oneSightingAsksForFasterSampling() throws {
        var pipeline = pipeline
        _ = try pipeline.process(page(1, tag: "Mencía", lines: ["Hola"])[0], at: 0)
        #expect(!pipeline.isInDialogue, "one sample isn't enough to enter dialogue")
        #expect(pipeline.wantsFastSampling, "but it's enough to look again soon")
        _ = try pipeline.process(empty(1)[0], at: 2)
        #expect(!pipeline.wantsFastSampling)
    }
}
