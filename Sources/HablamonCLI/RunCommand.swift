import ArgumentParser
import Foundation
import HablamonCore
import HablamonModels

struct RunCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "run",
        abstract: "Read dialogue aloud. Only --replay of a recorded video is implemented so far (macOS only)."
    )

    @Option(help: "Recorded video to replay instead of the live camera.")
    var replay: String?

    @Option(help: "Calibration file with the screen corners for the video.")
    var calibration: String?

    @Option(help: "Game profile.")
    var profile = "scarlet"

    @Option(help: "Directory for session transcripts. Defaults to ~/Library/Application Support/Hablamon/sessions.")
    var sessions: String?

    @Option(help: "Seconds between sampled frames.")
    var every: Double = 0.25

    @Flag(help: "After replaying, read the pages aloud in order.")
    var speak = false

    @Option(help: "Speaking speed multiplier.")
    var speed: Double = 0.85

    func run() async throws {
        guard let replay, let calibration else {
            throw ValidationError("Live camera mode isn't implemented yet; use --replay <video> --calibration <file>.")
        }
        #if canImport(AVFoundation) && canImport(CoreImage) && canImport(Vision)
            let quad = try DocumentLoader.load(
                Calibration.self,
                from: try String(contentsOfFile: calibration, encoding: .utf8)
            )
            let sessionsDirectory =
                sessions.map { URL(fileURLWithPath: $0, isDirectory: true) }
                ?? FileManager.default.defaultSessionsDirectory()
            let start = Date()
            let transcript = try TranscriptWriter(
                sessionsDirectory: sessionsDirectory,
                session: TranscriptWriter.sessionName(startingAt: start)
            )
            var pages: [SpokenPage] = []
            try await Replay.run(
                video: URL(fileURLWithPath: replay),
                calibration: quad,
                profile: try BundledData.profile(profile),
                characters: try BundledData.defaultCharacters(),
                every: every,
                onProgress: { time, frames in
                    print(
                        String(
                            format: "  … %.0fs of video, %d frames, %.1fs elapsed", time, frames,
                            -start.timeIntervalSinceNow))
                },
                onEvent: { event, time in
                    switch event {
                    case .speak(let page):
                        pages.append(page)
                        print(String(format: "[%6.2fs] ", time) + "\(page.speaker.name): \(page.text)")
                    case .dialogueStarted, .dialogueEnded, .pageChanged:
                        print(String(format: "[%6.2fs] ", time) + "(\(event))")
                    }
                }
            )
            for page in pages {
                try await transcript.appendLine(
                    at: start.addingTimeInterval(page.time),
                    speaker: page.speaker.name,
                    speakerRaw: page.speakerRaw,
                    text: page.text,
                    ocrConfidence: page.confidence,
                    engine: .apple,
                    voice: page.voice.summary
                )
            }
            print("\(pages.count) pages; transcript: \(transcript.fileURL.path)")
            if speak {
                let apple = AppleSpeechEngine()
                let narrator = Narrator(engine: apple, fallback: apple, speed: speed)
                for page in pages {
                    print("speaking: \(page.speaker.name) [\(page.voice.summary)]: \(page.text)")
                    await narrator.say(page.text, voice: page.voice)
                    await narrator.finish()
                }
            }
        #else
            throw ValidationError("hablamon run needs AVFoundation, Core Image, and Vision, so it only runs on macOS.")
        #endif
    }
}

extension FileManager {
    fileprivate func defaultSessionsDirectory() -> URL {
        homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Hablamon/sessions", isDirectory: true)
    }
}
