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

    @Test func brokenFileIsKeptAsideOnSave() throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let broken = #"{"schemaVersion": 1, "characters": {"Robo": {"gender": "robot"}}}"#
        let url = root.appendingPathComponent("characters.json")
        try broken.write(to: url, atomically: true, encoding: .utf8)
        try store.save(CharacterTable(characters: ["Clavel": Speaker(gender: .male)]))
        let files = try FileManager.default.contentsOfDirectory(atPath: root.path)
        let kept = try #require(files.first { $0.hasPrefix("characters.broken-") })
        #expect(try String(contentsOf: root.appendingPathComponent(kept), encoding: .utf8) == broken)
        #expect(store.characters().value.characters.keys.sorted() == ["Clavel"])
    }

    @Test func unreadableFileIsAnIssue() throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data([0xFF, 0xFE, 0x00]).write(to: root.appendingPathComponent("known-words.json"))
        #expect(store.knownWords().issue != nil)
    }

    @Test func missingCalibrationIsNil() {
        #expect(store.calibration(for: .iphone).value == nil)
        #expect(store.reference(for: .iphone) == nil)
    }

    @Test func calibrationRoundTrips() throws {
        let calibration = Calibration(
            deviceID: "iphone-1", deviceName: "iPhone de Kyle", screenQuad: rect(10, 20, 1600, 900), zoomFactor: 1,
            referenceThumbnail: "reference.pgm", calibratedAt: "2026-10-26T12:00:00-07:00")
        try store.save(calibration, for: .iphone)
        #expect(store.calibration(for: .iphone).value == calibration)
    }

    @Test func referenceRoundTrips() throws {
        let image = GrayImage(width: 128, height: 72, fill: 77)
        try store.save(reference: image, for: .iphone)
        #expect(store.reference(for: .iphone) == image)
    }

    @Test func macCameraHasItsOwnCalibration() throws {
        let iphone = Calibration(
            deviceID: "iphone-1", screenQuad: rect(10, 20, 1600, 900), zoomFactor: 1,
            referenceThumbnail: "reference.pgm", calibratedAt: "2026-10-26T12:00:00-07:00")
        let mac = Calibration(
            deviceID: "facetime", screenQuad: rect(300, 200, 600, 340), zoomFactor: 1,
            referenceThumbnail: "reference-mac.pgm", calibratedAt: "2026-10-27T12:00:00-07:00")
        try store.save(iphone, for: .iphone)
        try store.save(mac, for: .mac)
        try store.save(reference: GrayImage(width: 128, height: 72, fill: 1), for: .iphone)
        try store.save(reference: GrayImage(width: 128, height: 72, fill: 2), for: .mac)
        #expect(store.calibration(for: .iphone).value == iphone)
        #expect(store.calibration(for: .mac).value == mac)
        #expect(store.reference(for: .mac)?.pixels.first == 2)
        #expect(store.reference(for: .iphone)?.pixels.first == 1)
    }
}
