import Foundation
import HablamonModels
import Testing

@testable import HablamonCore

/// The golden transcript drafted for a fixture video.
struct GoldenTranscript: Decodable {
    struct Line: Decodable {
        var at: Double
        var speaker: String
        var certain: Bool
        var text: String
    }

    var video: String
    var lines: [Line]
}

enum VideoFixtures {
    static let directory = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Fixtures/videos")

    static func url(_ name: String) -> URL { directory.appendingPathComponent(name) }

    static var farVideoAvailable: Bool { FileManager.default.fileExists(atPath: url("far.mp4").path) }
}

@Suite struct VideoFixtureFileTests {
    @Test func calibrationLoads() throws {
        let text = try String(contentsOf: VideoFixtures.url("far.calibration.json"), encoding: .utf8)
        let calibration = try DocumentLoader.load(Calibration.self, from: text)
        #expect(calibration.screenQuad.topLeft == Point(x: 185, y: 655))
    }

    @Test func goldenTranscriptParses() throws {
        let data = try Data(contentsOf: VideoFixtures.url("far.expected.json"))
        let golden = try JSONDecoder().decode(GoldenTranscript.self, from: data)
        #expect(golden.lines.count > 10)
        #expect(golden.lines.map(\.at) == golden.lines.map(\.at).sorted())
    }
}

#if canImport(AVFoundation) && canImport(CoreImage) && canImport(Vision)
    /// End-to-end: replay far.mp4 through correction, detection, settle, OCR, and speaker resolution,
    /// then compare against the golden transcript. Run `mise run fixtures` first; skipped without the video.
    @Suite struct ReplayTests {
        @Test(
            .enabled(if: VideoFixtures.farVideoAvailable, "run `mise run fixtures` to download far.mp4"),
            .timeLimit(.minutes(3))
        )
        func farVideoMatchesGoldenTranscript() async throws {
            let calibration = try DocumentLoader.load(
                Calibration.self,
                from: try String(contentsOf: VideoFixtures.url("far.calibration.json"), encoding: .utf8)
            )
            let golden = try JSONDecoder().decode(
                GoldenTranscript.self,
                from: try Data(contentsOf: VideoFixtures.url("far.expected.json"))
            )
            var pages: [SpokenPage] = []
            let started = Date()
            try await Replay.run(
                video: VideoFixtures.url("far.mp4"),
                calibration: calibration,
                profile: try BundledData.profile("scarlet"),
                characters: try BundledData.defaultCharacters(),
                onProgress: { time, frames in
                    print(
                        String(
                            format: "[replay] %.0fs of video, %d frames, %.1fs elapsed", time, frames,
                            -started.timeIntervalSinceNow))
                },
                onEvent: { event, _ in
                    if case .speak(let page) = event { pages.append(page) }
                }
            )
            for page in pages {
                print(
                    String(format: "[replay %6.2fs] ", page.time)
                        + "\(page.speaker.name) (\(page.speakerRaw ?? "-")): \(page.text)")
            }

            // A golden line counts as found when one to three consecutive pages, joined, match it closely.
            let keys = pages.map { DialogueText.matchKey($0.text) }
            func found(_ line: GoldenTranscript.Line) -> Bool {
                let target = DialogueText.matchKey(line.text)
                for start in keys.indices {
                    for length in 1...3 where start + length <= keys.count {
                        if similarity(keys[start..<(start + length)].joined(), target) >= 0.8 { return true }
                    }
                }
                return false
            }
            let certain = golden.lines.filter(\.certain)
            let missing = certain.filter { !found($0) }
            for line in missing { print("[replay] missing at \(line.at)s: \(line.text)") }
            print(
                "[replay] found \(certain.count - missing.count) of \(certain.count) certain lines in \(pages.count) pages"
            )

            #expect(Double(certain.count - missing.count) >= Double(certain.count) * 0.7)
            #expect(pages.filter { $0.speaker.name != "Mencía" }.count <= 1, "every line in this clip is Mencía's")
            #expect(pages.count <= golden.lines.count * 2, "too many pages suggests repeats")
        }
    }
#endif
