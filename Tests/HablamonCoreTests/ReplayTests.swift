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

    /// Videos with a calibration and a golden transcript next to them.
    static let names = ["far", "academy-lobby_far", "classroom_far"]

    static func available(_ name: String) -> Bool {
        FileManager.default.fileExists(atPath: url("\(name).mp4").path)
    }

    static func calibration(_ name: String) throws -> Calibration {
        try DocumentLoader.load(
            Calibration.self, from: try String(contentsOf: url("\(name).calibration.json"), encoding: .utf8))
    }

    static func golden(_ name: String) throws -> GoldenTranscript {
        try JSONDecoder().decode(GoldenTranscript.self, from: try Data(contentsOf: url("\(name).expected.json")))
    }
}

@Suite struct VideoFixtureFileTests {
    @Test func calibrationLoads() throws {
        #expect(try VideoFixtures.calibration("far").screenQuad.topLeft == Point(x: 185, y: 655))
    }

    @Test(arguments: VideoFixtures.names)
    func fixtureFilesParse(_ name: String) throws {
        _ = try VideoFixtures.calibration(name)
        let golden = try VideoFixtures.golden(name)
        #expect(golden.video == "\(name).mp4")
        #expect(golden.lines.count >= 5)
        #expect(golden.lines.map(\.at) == golden.lines.map(\.at).sorted())
    }
}

#if canImport(AVFoundation) && canImport(CoreImage) && canImport(Vision)
    /// End-to-end: replay each fixture video through correction, detection, settle, OCR, and speaker
    /// resolution, then compare against its golden transcript. Run `mise run fixtures` first; a video
    /// that isn't downloaded is skipped.
    @Suite struct ReplayTests {
        final class Latest: @unchecked Sendable {
            var time = 0.0
            var frames = 0
            var screens = 0
        }

        @Test(
            .enabled(if: VideoFixtures.available("academy-lobby_far"), "run `mise run fixtures`"),
            .timeLimit(.minutes(2))
        )
        func realTimeReplayTracksTheClock() async throws {
            let latest = Latest()
            let started = ContinuousClock.now
            let replay = Task {
                try await Replay.run(
                    video: VideoFixtures.url("academy-lobby_far.mp4"),
                    calibration: try VideoFixtures.calibration("academy-lobby_far"),
                    profile: try BundledData.profile("scarlet"),
                    characters: try BundledData.defaultCharacters(),
                    realTime: true,
                    onFrame: { screenFound, time in
                        latest.time = time
                        latest.frames += 1
                        if screenFound { latest.screens += 1 }
                    },
                    onEvent: { _, _ in }
                )
            }
            while latest.time < 6 { try await Task.sleep(for: .milliseconds(50)) }
            replay.cancel()
            _ = await replay.result
            let elapsed = ContinuousClock.now - started
            #expect(elapsed >= .seconds(5.5), "6 s of video should take about 6 s")
            #expect(abs(latest.frames - Int(latest.time / 0.25)) <= 3, "one onFrame per sample")
            #expect(latest.screens == latest.frames, "the calibrated screen is found in every frame")
        }

        /// Videos whose misses are understood but not fixed yet.
        static let knownMisses = ["classroom_far": "boxes without a name tag aren't detected yet"]

        @Test(.timeLimit(.minutes(3)), arguments: VideoFixtures.names)
        func videoMatchesGoldenTranscript(_ name: String) async throws {
            try #require(VideoFixtures.available(name), "run `mise run fixtures` to download \(name).mp4")
            let golden = try VideoFixtures.golden(name)
            var pages: [SpokenPage] = []
            let started = Date()
            try await Replay.run(
                video: VideoFixtures.url("\(name).mp4"),
                calibration: try VideoFixtures.calibration(name),
                profile: try BundledData.profile("scarlet"),
                characters: try BundledData.defaultCharacters(),
                onProgress: { time, frames in
                    print(
                        String(
                            format: "[replay %@] %.0fs of video, %d frames, %.1fs elapsed", name, time, frames,
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
            // Returns the first matching page so its speaker can be checked.
            let keys = pages.map { DialogueText.matchKey($0.text) }
            func match(_ line: GoldenTranscript.Line) -> SpokenPage? {
                let target = DialogueText.matchKey(line.text)
                for start in keys.indices {
                    for length in 1...3 where start + length <= keys.count {
                        if similarity(keys[start..<(start + length)].joined(), target) >= 0.8 { return pages[start] }
                    }
                }
                return nil
            }
            let certain = golden.lines.filter(\.certain)
            let matches = certain.map { ($0, match($0)) }
            let found = matches.compactMap { line, page in page.map { (line, $0) } }
            for (line, page) in matches where page == nil { print("[replay] missing at \(line.at)s: \(line.text)") }
            print("[replay] found \(found.count) of \(certain.count) certain lines in \(pages.count) pages")

            let rightSpeaker = found.filter { line, page in page.speaker.name == line.speaker }.count
            #expect(Double(rightSpeaker) >= Double(found.count) * 0.7, "speakers should match the name tags")
            #expect(pages.count <= golden.lines.count * 2, "too many pages suggests repeats")
            withKnownIssue(Comment(rawValue: Self.knownMisses[name] ?? "")) {
                #expect(Double(found.count) >= Double(certain.count) * 0.7)
            } when: {
                Self.knownMisses[name] != nil
            }
        }
    }
#endif
