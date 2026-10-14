import Foundation
import HablamonModels
import Testing

@testable import HablamonCore

@Suite struct TranscriptWriterTests {
    let directory: URL
    let pacific = TimeZone(secondsFromGMT: -7 * 3600)!
    let start = Date(timeIntervalSince1970: 1_791_772_200)  // 2026-10-11T19:30:00-07:00

    init() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("hablamon-tests-\(UUID().uuidString)", isDirectory: true)
    }

    func writer(session: String = "s") throws -> TranscriptWriter {
        try TranscriptWriter(sessionsDirectory: directory, session: session, timeZone: pacific)
    }

    @Test func namesSessionsByStartTime() {
        #expect(TranscriptWriter.sessionName(startingAt: start, timeZone: pacific) == "2026-10-11T19-30-00")
        #expect(
            TranscriptWriter.timestamp(start.addingTimeInterval(7.512), timeZone: pacific)
                == "2026-10-11T19:30:07.512-07:00"
        )
    }

    @Test func writesOneValidatedEntryPerLine() async throws {
        let transcript = try writer()
        let first = try await transcript.appendLine(
            at: start,
            speaker: "Mencía",
            speakerRaw: "Mencia",
            text: "¿A que impresiona?",
            ocrConfidence: OCRConfidence(mean: 0.9, min: 0.8),
            crop: "crops/000001.png",
            engine: .apple,
            voice: "es-ES female p1.1 r1.0"
        )
        try await transcript.appendGap(at: start.addingTimeInterval(60), reason: .cameraPaused, duration: 48.04)
        try await transcript.appendRecalibration(at: start.addingTimeInterval(61), trigger: .automatic)
        let second = try await transcript.appendLine(
            at: start.addingTimeInterval(70),
            speaker: "narrator",
            speakerRaw: nil,
            text: "¡Has obtenido el Bocadillo!",
            ocrConfidence: OCRConfidence(mean: 0.95, min: 0.9),
            engine: .apple,
            voice: "es-ES"
        )
        #expect(first.seq == 1)
        #expect(second.seq == 2)

        let raw = try String(contentsOf: transcript.fileURL, encoding: .utf8)
        #expect(raw.split(separator: "\n").count == 4)
        #expect(raw.contains("crops/000001.png"), "slashes stay unescaped")
        #expect(raw.contains("¿A que impresiona?"), "Spanish text stays readable")

        let entries = try TranscriptReader.entries(at: transcript.fileURL)
        #expect(entries.count == 4)
        #expect(entries[0] == .line(first))
        #expect(
            entries[1]
                == .gap(
                    TranscriptGap(
                        ts: "2026-10-11T19:31:00.000-07:00", session: "s", reason: .cameraPaused, durationSec: 48)))
    }

    @Test func reopeningContinuesSequence() async throws {
        let firstRun = try writer()
        try await firstRun.appendLine(
            at: start, speaker: "Clavel", speakerRaw: "Clavel", text: "Uno.",
            ocrConfidence: OCRConfidence(mean: 1, min: 1), engine: .apple, voice: "v"
        )
        let secondRun = try writer()
        let line = try await secondRun.appendLine(
            at: start, speaker: "Clavel", speakerRaw: "Clavel", text: "Dos.",
            ocrConfidence: OCRConfidence(mean: 1, min: 1), engine: .apple, voice: "v"
        )
        #expect(line.seq == 2)
    }

    @Test func reportsTheBadLine() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("bad.jsonl")
        try Data(
            "{\"v\":1,\"type\":\"gap\",\"ts\":\"x\",\"session\":\"s\",\"reason\":\"camera_paused\",\"durationSec\":1}\n{\"v\":1}\n"
                .utf8
        )
        .write(to: url)
        #expect {
            try TranscriptReader.entries(at: url)
        } throws: { error in
            (error as? TranscriptReadError)?.line == 2
        }
    }
}
