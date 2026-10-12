import HablamonModels
import Testing

@Suite struct TranscriptEntryTests {
    /// Lines in the exact shape the design doc shows.
    @Test func parsesDesignDocExamples() throws {
        let line = try DocumentLoader.load(
            TranscriptEntry.self,
            from: #"""
                {"v":1,"type":"line","ts":"2026-10-11T19:42:07.512-07:00","session":"2026-10-11T19-30-00","seq":42,"speaker":"Clavel","speakerRaw":"Clavel","text":"Al fin y al cabo, debo hacerme responsable de las torpezas en que incurra mi academia.","ocrConfidence":{"mean":0.94,"min":0.81},"crop":"crops/000042.png","engine":"apple","voice":"es-ES male p0.9 r0.95","translation":null,"translationSource":null}
                """#
        )
        guard case .line(let parsed) = line else {
            Issue.record("expected a line, got \(line)")
            return
        }
        #expect(parsed.seq == 42)
        #expect(parsed.translation == nil)

        let gap = try DocumentLoader.load(
            TranscriptEntry.self,
            from: #"""
                {"v":1,"type":"gap","ts":"2026-10-11T19:44:30.000-07:00","session":"2026-10-11T19-30-00","reason":"camera_paused","durationSec":48}
                """#
        )
        #expect(
            gap
                == .gap(
                    TranscriptGap(
                        ts: "2026-10-11T19:44:30.000-07:00", session: "2026-10-11T19-30-00", reason: .cameraPaused,
                        durationSec: 48)))
    }

    @Test func rejectsUnknownType() {
        #expect(throws: DocumentError.self) {
            try DocumentLoader.load(TranscriptEntry.self, from: #"{"v":1,"type":"menu","ts":"x","session":"s"}"#)
        }
    }

    @Test func usesShortVersionKey() {
        #expect(throws: DocumentError.missingVersion(key: "v")) {
            try DocumentLoader.load(TranscriptEntry.self, from: #"{"type":"gap"}"#)
        }
    }
}
