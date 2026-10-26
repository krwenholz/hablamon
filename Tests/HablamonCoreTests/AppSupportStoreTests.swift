import Foundation
import HablamonModels
import Testing

@testable import HablamonCore

@Suite struct AppSupportStoreTests {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("hablamon-store-\(UUID().uuidString)", isDirectory: true)
    var store: AppSupportStore { AppSupportStore(root: root) }

    @Test func seedWritesDefaultsOnce() throws {
        try store.seedIfNeeded()
        let characters = store.characters()
        #expect(characters.issue == nil)
        #expect(characters.value.characters == (try BundledData.defaultCharacters()).characters)
        var settings = store.settings().value
        #expect(settings.schemaURI == "hablamon:settings")
        settings.schemaURI = nil
        #expect(settings == Settings.defaults)
        #expect(characters.value.schemaURI == "hablamon:characters")

        let edited = #"{"$schema": "hablamon:characters", "schemaVersion": 1, "characters": {}}"#
        try edited.write(to: root.appendingPathComponent("characters.json"), atomically: true, encoding: .utf8)
        try store.seedIfNeeded()
        #expect(store.characters().value.characters.isEmpty)
    }

    @Test func brokenFileFallsBackWithIssue() throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let broken = #"{"schemaVersion": 1, "characters": {"Robo": {"gender": "robot"}}}"#
        try broken.write(to: root.appendingPathComponent("characters.json"), atomically: true, encoding: .utf8)
        let loaded = store.characters()
        #expect(loaded.value.characters == (try BundledData.defaultCharacters()).characters)
        #expect(loaded.issue?.contains("gender") == true)
    }

    @Test func missingKnownWordsIsEmpty() {
        let loaded = store.knownWords()
        #expect(loaded.value.lemmas.isEmpty)
        #expect(loaded.issue == nil)
    }

    @Test func savedKnownWordsLoadBack() throws {
        try store.save(KnownWords(lemmas: ["travesía"]))
        #expect(store.knownWords().value.lemmas == ["travesía"])
    }

    @Test func emptySessionsDirectoryHasNoLines() {
        #expect(store.pastLines().isEmpty)
    }

    @Test func pastLinesReadsAllSessions() async throws {
        for session in ["a", "b"] {
            let writer = try TranscriptWriter(sessionsDirectory: store.sessionsDirectory, session: session)
            try await writer.appendLine(
                at: Date(), speaker: "Mencía", speakerRaw: nil, text: "Hola \(session)",
                ocrConfidence: OCRConfidence(mean: 1, min: 1), engine: .apple, voice: "v")
        }
        #expect(Set(store.pastLines().map(\.text)) == ["Hola a", "Hola b"])
    }

    @Test func logsLiveUnderTheRoot() {
        #expect(store.logsDirectory == root.appendingPathComponent("logs", isDirectory: true))
    }
}
