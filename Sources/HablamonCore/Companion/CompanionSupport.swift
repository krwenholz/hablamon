import Foundation
import HablamonModels

extension SpokenPage {
    /// Resolves an unknown speaker again against an updated character table, as after the player
    /// tags them. Known speakers and narration are returned unchanged.
    public func reresolved(with resolver: SpeakerResolver, voices: VoiceSelector) -> SpokenPage {
        guard case .unknown = speaker else { return self }
        var page = self
        page.speaker = resolver.resolve(tag: speakerRaw)
        page.voice = voices.plan(for: page.speaker)
        return page
    }
}

/// A plain-text log, one timestamped line per call, kept in Application Support so it survives
/// app reinstalls.
public final class FileLog: @unchecked Sendable {
    private let handle: FileHandle
    private let lock = NSLock()
    private let formatter = ISO8601DateFormatter()

    public init(directory: URL, name: String) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("\(name).log")
        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: nil)
        }
        handle = try FileHandle(forWritingTo: url)
        handle.seekToEndOfFile()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    }

    deinit { try? handle.close() }

    public func write(_ message: String) {
        lock.withLock {
            let line = "\(formatter.string(from: Date())) \(message)\n"
            handle.write(Data(line.utf8))
        }
    }
}
