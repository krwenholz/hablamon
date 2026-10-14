#if canImport(Vision)
    import Foundation
    import Testing

    @testable import HablamonCore

    /// Runs Vision on the real phone photos. Full-frame OCR without perspective correction,
    /// so this is a floor: calibrated crops should only do better.
    @Suite struct VisionOCRTests {
        static let photos = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/photos")

        func text(in name: String) throws -> String {
            let url = Self.photos.appendingPathComponent(name)
            try #require(FileManager.default.fileExists(atPath: url.path), "missing fixture \(name)")
            let lines = try VisionTextRecognizer().recognize(fileAt: url)
            for line in lines { print("[\(name)] \(String(format: "%.2f", line.confidence)) \(line.text)") }
            return DialogueText.normalize(lines: lines.map(\.text))
        }

        @Test(arguments: [
            "trainer-challenge_near_straight.jpeg",
            "trainer-challenge_near_straight-clipped-left.jpeg",
            "trainer-challenge_near_angled-glare.jpeg",
        ])
        func readsNearDialogue(photo: String) throws {
            let key = DialogueText.matchKey(try text(in: photo))
            #expect(key.contains(DialogueText.matchKey("combatir contra Entrenadores")))
            #expect(key.contains(DialogueText.matchKey("tan solo tienes que hablarnos")))
        }

        @Test func readsRolledDialogue() throws {
            let key = DialogueText.matchKey(try text(in: "pokemon-fuertes_near_rolled.jpeg"))
            #expect(key.contains(DialogueText.matchKey("que son fuertes tus Pokémon")))
        }
    }
#endif
