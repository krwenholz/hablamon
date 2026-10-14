import Foundation
import HablamonModels
import Testing

@testable import HablamonCore

@Suite struct TranscriptExporterTests {
    let utc = TimeZone(secondsFromGMT: 0)!

    func makeSessions(_ names: [String]) async throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("export-\(UUID().uuidString)")
        for (index, name) in names.enumerated() {
            let writer = try TranscriptWriter(sessionsDirectory: directory, session: name, timeZone: utc)
            try await writer.appendGap(at: Date(), reason: .cameraPaused, duration: 3)
            try await writer.appendLine(
                at: Date(), speaker: "Mencía", speakerRaw: "Mencia",
                text: index == 0 ? "Montañas, prados, bosques..." : "Dijo \"¡hola!\", y se fue.",
                ocrConfidence: OCRConfidence(mean: 1, min: 1), engine: .apple, voice: "v"
            )
        }
        return directory
    }

    @Test func exportsOnlyLinesAsCSV() async throws {
        let directory = try await makeSessions(["2026-10-11T19-30-00", "2026-10-13T20-00-00"])
        let lines = try TranscriptExporter.lines(in: directory, timeZone: utc)
        #expect(lines.count == 2, "gaps are not exported")
        let csv = TranscriptExporter.csv(lines).split(separator: "\n")
        #expect(csv[0] == "session,seq,ts,speaker,text,translation")
        #expect(csv[1].hasSuffix(",Mencía,\"Montañas, prados, bosques...\","))
        #expect(csv[2].hasSuffix(",Mencía,\"Dijo \"\"¡hola!\"\", y se fue.\","))
    }

    @Test func filtersBySessionStart() async throws {
        let directory = try await makeSessions(["2026-10-11T19-30-00", "2026-10-13T20-00-00"])
        let cutoff = TranscriptExporter.sessionStart("2026-10-12T00-00-00", timeZone: utc)!
        let lines = try TranscriptExporter.lines(in: directory, since: cutoff, timeZone: utc)
        #expect(lines.map(\.session) == ["2026-10-13T20-00-00"])
    }

    @Test func parsesDurations() {
        #expect(TranscriptExporter.duration("7d") == 604_800)
        #expect(TranscriptExporter.duration("12h") == 43_200)
        #expect(TranscriptExporter.duration("30m") == 1_800)
        #expect(TranscriptExporter.duration("7w") == nil)
        #expect(TranscriptExporter.duration("d") == nil)
    }
}
