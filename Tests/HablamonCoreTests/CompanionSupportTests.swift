import Foundation
import HablamonModels
import Testing

@testable import HablamonCore

@Suite struct CompanionSupportTests {
    @Test func reresolvingPicksUpNewlyTaggedSpeakers() {
        let page = spokenPage("Hola", speaker: .unknown(tag: "Recepcionista"))
        let table = CharacterTable(characters: ["Recepcionista": Speaker(gender: .male)])
        let updated = page.reresolved(with: SpeakerResolver(table: table), voices: VoiceSelector())
        #expect(updated.speaker.name == "Recepcionista")
        #expect(updated.voice.register == .male)
        #expect(updated.text == "Hola")
    }

    @Test func reresolvingLeavesKnownAndNarratorAlone() {
        let narration = spokenPage("¡Has obtenido algo!")
        let resolver = SpeakerResolver(table: CharacterTable(characters: [:]))
        #expect(narration.reresolved(with: resolver, voices: VoiceSelector()) == narration)
    }

    @Test func fileLogAppendsTimestampedLines() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("hablamon-log-\(UUID().uuidString)", isDirectory: true)
        let log = try FileLog(directory: directory, name: "s1")
        log.write("started")
        log.write("second")
        let text = try String(contentsOf: directory.appendingPathComponent("s1.log"), encoding: .utf8)
        let lines = text.split(separator: "\n")
        #expect(lines.count == 2)
        #expect(lines[0].hasSuffix(" started"))
        #expect(lines[1].hasSuffix(" second"))
    }
}
