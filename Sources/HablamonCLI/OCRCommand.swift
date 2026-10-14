import ArgumentParser
import Foundation
import HablamonCore

#if canImport(AVFoundation)
    import AVFoundation
#endif

struct OCRCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "ocr",
        abstract: "Print the text Vision finds in images, or in sampled frames of a video (macOS only)."
    )

    @Argument(help: "Image or video files.")
    var paths: [String]

    @Option(help: "Seconds between sampled video frames.")
    var every: Double = 2

    func run() async throws {
        #if canImport(Vision) && canImport(AVFoundation)
            let recognizer = VisionTextRecognizer()
            for path in paths {
                let url = URL(fileURLWithPath: path)
                if ["mp4", "mov", "m4v"].contains(url.pathExtension.lowercased()) {
                    try await recognizeVideo(at: url, with: recognizer)
                } else {
                    print("## \(path)")
                    printLines(try recognizer.recognize(fileAt: url))
                }
            }
        #else
            throw ValidationError("hablamon ocr needs Apple's Vision framework, so it only runs on macOS.")
        #endif
    }

    func printLines(_ lines: [RecognizedLine]) {
        if lines.isEmpty { print("  (no text)") }
        for line in lines {
            let box = String(format: "x%.2f y%.2f w%.2f h%.2f", line.box.x, line.box.y, line.box.width, line.box.height)
            print(String(format: "  [%.2f] ", line.confidence) + line.text + "  (\(box))")
        }
    }

    #if canImport(Vision) && canImport(AVFoundation)
        func recognizeVideo(at url: URL, with recognizer: VisionTextRecognizer) async throws {
            let asset = AVURLAsset(url: url)
            let duration = try await asset.load(.duration).seconds
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.requestedTimeToleranceBefore = .zero
            generator.requestedTimeToleranceAfter = .zero
            for seconds in stride(from: 0, to: duration, by: every) {
                let (image, _) = try await generator.image(at: CMTime(seconds: seconds, preferredTimescale: 600))
                let lines = try recognizer.recognize(image)
                print(String(format: "## %@ @ %.1fs", url.lastPathComponent, seconds))
                printLines(lines)
            }
        }
    #endif
}
