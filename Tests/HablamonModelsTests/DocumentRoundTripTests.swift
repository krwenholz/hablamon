import Foundation
import HablamonModels
import Testing

/// Encoding a value and loading it back through validation gives the same value.
@Suite struct DocumentRoundTripTests {
    func roundTrip<T: VersionedDocument & Equatable>(_ value: T) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let text = String(decoding: try encoder.encode(value), as: UTF8.self)
        let loaded = try DocumentLoader.load(T.self, from: text)
        #expect(loaded == value)
    }

    @Test func characterTable() throws {
        try roundTrip(
            CharacterTable(
                schemaURI: "schemas/characters.schema.json",
                characters: [
                    "Clavel": Speaker(
                        englishName: "Clavell",
                        gender: .male,
                        ageGroup: .adult,
                        role: "Director",
                        description: "theatrical",
                        aliases: ["Cael"],
                        voices: VoiceAssignments(
                            apple: AppleVoice(voice: "com.apple.voice.compact.es-ES.Monica", pitch: 0.9, rate: 0.95),
                            qwen3: ClonedVoice(referenceClip: "voices/clavel.wav"),
                            kokoro: KokoroVoice(voice: "em_alex")
                        )
                    ),
                    "Albora": Speaker(gender: .female, version: .scarlet),
                ]
            )
        )
    }

    @Test func gameProfile() throws {
        try roundTrip(
            GameProfile(
                schemaURI: nil,
                schemaVersion: 1,
                id: "scarlet",
                name: "Pokémon Scarlet",
                frameSize: PixelSize(width: 1280, height: 720),
                regions: ProfileRegions(
                    dialogueBox: PixelRect(x: 10, y: 500, width: 1200, height: 200),
                    bodyText: PixelRect(x: 40, y: 540, width: 1100, height: 120),
                    textLines: PixelRect(x: 40, y: 550, width: 1100, height: 100),
                    nameTag: PixelRect(x: 40, y: 470, width: 300, height: 50),
                    advanceIndicator: nil
                ),
                detection: BoxDetection(
                    edgeStep: 0.04,
                    maxMarginEdgeDensity: 0.012,
                    minTextEdgeDensity: 0.003,
                    tagSaturation: 0.3,
                    minTagFraction: 0.5
                )
            )
        )
    }

    @Test func calibration() throws {
        try roundTrip(
            Calibration(
                schemaVersion: 1,
                deviceID: "ABC-123",
                deviceName: "iPhone",
                screenQuad: Quad(
                    topLeft: Point(x: 100, y: 80),
                    topRight: Point(x: 1800, y: 90),
                    bottomRight: Point(x: 1790, y: 1000),
                    bottomLeft: Point(x: 110, y: 990)
                ),
                zoomFactor: 1.5,
                referenceThumbnail: "calibration/bezel.png",
                calibratedAt: "2026-10-11T19:30:00-07:00"
            )
        )
    }

    @Test func settingsDefaults() throws {
        try roundTrip(Settings.defaults)
    }

    @Test func voiceManifest() throws {
        try roundTrip(
            VoiceManifest(
                schemaVersion: 1,
                voices: [
                    "Clavel": DesignedVoice(
                        engine: .qwen3,
                        referenceClip: "voices/clavel.wav",
                        prompt: "theatrical academy director",
                        createdAt: "2026-10-11T19:30:00-07:00"
                    )
                ]
            )
        )
    }

    @Test func transcriptEntries() throws {
        try roundTrip(
            TranscriptEntry.line(
                TranscriptLine(
                    ts: "2026-10-11T19:42:07.512-07:00",
                    session: "2026-10-11T19-30-00",
                    seq: 42,
                    speaker: "Clavel",
                    speakerRaw: "Clavel",
                    text: "¿Cómo? ¡Me dejas atónito!",
                    ocrConfidence: OCRConfidence(mean: 0.94, min: 0.81),
                    crop: "crops/000042.png",
                    engine: .apple,
                    voice: "es-ES male p0.9 r0.95"
                )
            )
        )
        try roundTrip(
            TranscriptEntry.gap(
                TranscriptGap(ts: "2026-10-11T19:44:30-07:00", session: "s", reason: .cameraPaused, durationSec: 48)
            )
        )
        try roundTrip(
            TranscriptEntry.recalibrated(
                TranscriptRecalibration(ts: "2026-10-11T19:45:00-07:00", session: "s", trigger: .automatic)
            )
        )
    }

    @Test func knownWords() throws {
        try roundTrip(KnownWords(schemaURI: "hablamon:known-words", lemmas: ["travesía", "vestíbulo"]))
    }

    @Test func knownWordsRejectsUnknownKeys() {
        #expect(throws: DocumentError.self) {
            try DocumentLoader.load(KnownWords.self, from: #"{"schemaVersion": 1, "lemmas": [], "extra": 1}"#)
        }
    }

    @Test func defaultKeysArePlain() {
        let keys = Settings.defaults.keys
        #expect([keys.repeatLast, keys.repeatLastSlowly, keys.toggleSpeed] == ["r", "shift+r", "s"])
        #expect([keys.togglePause, keys.recalibrate, keys.holdForEnglish] == ["space", "c", "e"])
    }
}
