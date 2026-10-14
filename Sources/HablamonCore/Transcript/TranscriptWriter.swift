import Foundation
import HablamonModels

/// Appends entries to `sessions/<session>.jsonl`, one JSON object per line.
///
/// Every entry is written straight to the file, so a crash loses at most the line in flight.
/// Reopening an existing session continues its sequence numbers.
public actor TranscriptWriter {
    public nonisolated let session: String
    public nonisolated let fileURL: URL
    private let timeZone: TimeZone
    private let handle: FileHandle
    private var nextSequence: Int
    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }()

    public init(sessionsDirectory: URL, session: String, timeZone: TimeZone = .current) throws {
        self.session = session
        self.timeZone = timeZone
        self.fileURL = sessionsDirectory.appendingPathComponent("\(session).jsonl")
        try FileManager.default.createDirectory(at: sessionsDirectory, withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: fileURL.path),
            !FileManager.default.createFile(atPath: fileURL.path, contents: nil)
        {
            throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: fileURL.path])
        }
        let existing = try TranscriptReader.entries(at: fileURL)
        nextSequence =
            1
            + existing.compactMap { entry -> Int? in
                if case .line(let line) = entry { return line.seq }
                return nil
            }.reduce(0, max)
        handle = try FileHandle(forWritingTo: fileURL)
        try handle.seekToEnd()
    }

    deinit {
        try? handle.close()
    }

    /// Logs a spoken page and returns it with its sequence number and timestamp filled in.
    @discardableResult
    public func appendLine(
        at date: Date,
        speaker: String,
        speakerRaw: String?,
        text: String,
        ocrConfidence: OCRConfidence,
        crop: String? = nil,
        engine: SpeechEngineID,
        voice: String
    ) throws -> TranscriptLine {
        let line = TranscriptLine(
            ts: Self.timestamp(date, timeZone: timeZone),
            session: session,
            seq: nextSequence,
            speaker: speaker,
            speakerRaw: speakerRaw,
            text: text,
            ocrConfidence: ocrConfidence,
            crop: crop,
            engine: engine,
            voice: voice
        )
        try write(.line(line))
        nextSequence += 1
        return line
    }

    public func appendGap(at date: Date, reason: TranscriptGap.Reason, duration: TimeInterval) throws {
        try write(
            .gap(
                TranscriptGap(
                    ts: Self.timestamp(date, timeZone: timeZone),
                    session: session,
                    reason: reason,
                    durationSec: (duration * 10).rounded() / 10
                )
            )
        )
    }

    public func appendRecalibration(at date: Date, trigger: TranscriptRecalibration.Trigger) throws {
        try write(
            .recalibrated(
                TranscriptRecalibration(
                    ts: Self.timestamp(date, timeZone: timeZone), session: session, trigger: trigger)
            )
        )
    }

    private func write(_ entry: TranscriptEntry) throws {
        var data = try encoder.encode(entry)
        data.append(0x0A)
        try handle.write(contentsOf: data)
    }

    /// Session names are the start time, safe for file names: `2026-10-11T19-30-00`.
    public static func sessionName(startingAt date: Date, timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd'T'HH-mm-ss"
        return formatter.string(from: date)
    }

    /// ISO 8601 with milliseconds and offset: `2026-10-11T19:42:07.512-07:00`.
    public static func timestamp(_ date: Date, timeZone: TimeZone) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = timeZone
        return formatter.string(from: date)
    }
}

public enum TranscriptReader {
    /// Reads and validates every entry in a session file. Blank lines are skipped.
    public static func entries(at url: URL) throws -> [TranscriptEntry] {
        let text = try String(contentsOf: url, encoding: .utf8)
        var entries: [TranscriptEntry] = []
        for (index, line) in text.split(separator: "\n", omittingEmptySubsequences: true).enumerated() {
            do {
                entries.append(try DocumentLoader.load(TranscriptEntry.self, from: String(line)))
            } catch {
                throw TranscriptReadError(file: url.lastPathComponent, line: index + 1, underlying: error)
            }
        }
        return entries
    }
}

public struct TranscriptReadError: Error, CustomStringConvertible {
    public var file: String
    public var line: Int
    public var underlying: DocumentError

    public var description: String { "\(file):\(line): \(underlying)" }
}
