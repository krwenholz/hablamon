import Foundation
import HablamonModels

/// Flattens spoken lines from session transcripts for study or batch translation.
public enum TranscriptExporter {
    public static let csvColumns = ["session", "seq", "ts", "speaker", "text", "translation"]

    /// Spoken lines from every `*.jsonl` session in `directory` whose session started at or after `since`.
    /// Session names are their start time, so filtering doesn't need to read old files.
    public static func lines(in directory: URL, since: Date? = nil, timeZone: TimeZone = .current) throws
        -> [TranscriptLine]
    {
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "jsonl" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        var lines: [TranscriptLine] = []
        for file in files {
            let session = file.deletingPathExtension().lastPathComponent
            if let since, let started = sessionStart(session, timeZone: timeZone), started < since { continue }
            for case .line(let line) in try TranscriptReader.entries(at: file) {
                lines.append(line)
            }
        }
        return lines
    }

    public static func csv(_ lines: [TranscriptLine]) -> String {
        var output = csvColumns.joined(separator: ",") + "\n"
        for line in lines {
            let fields = [line.session, String(line.seq), line.ts, line.speaker, line.text, line.translation ?? ""]
            output += fields.map(escape).joined(separator: ",") + "\n"
        }
        return output
    }

    /// RFC 4180 quoting: wrap fields containing commas, quotes, or line breaks, and double inner quotes.
    static func escape(_ field: String) -> String {
        guard field.contains(where: { $0 == "," || $0 == "\"" || $0.isNewline }) else { return field }
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    static func sessionStart(_ session: String, timeZone: TimeZone) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd'T'HH-mm-ss"
        return formatter.date(from: session)
    }

    /// Parses durations like `7d`, `12h`, or `30m`.
    public static func duration(_ text: String) -> TimeInterval? {
        guard let unit = text.last, let value = Double(text.dropLast()), value >= 0 else { return nil }
        switch unit {
        case "d": return value * 86_400
        case "h": return value * 3_600
        case "m": return value * 60
        default: return nil
        }
    }
}
