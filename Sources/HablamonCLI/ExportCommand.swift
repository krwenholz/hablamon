import ArgumentParser
import Foundation
import HablamonCore

struct ExportCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "export",
        abstract: "Write spoken lines from session transcripts as CSV, for study or batch translation."
    )

    @Option(help: "Only sessions started within this long, such as 7d, 12h, or 30m.")
    var since: String?

    @Option(help: "Sessions directory. Defaults to ~/Library/Application Support/Hablamon/sessions.")
    var sessions: String?

    func run() throws {
        var cutoff: Date?
        if let since {
            guard let seconds = TranscriptExporter.duration(since) else {
                throw ValidationError("--since takes a number and a unit, such as 7d, 12h, or 30m.")
            }
            cutoff = Date().addingTimeInterval(-seconds)
        }
        let directory =
            sessions.map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Hablamon/sessions", isDirectory: true)
        print(TranscriptExporter.csv(try TranscriptExporter.lines(in: directory, since: cutoff)), terminator: "")
    }
}
