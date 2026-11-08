import Foundation
import MetricKit

/// Saves the crash and hang reports iOS keeps for this app into the logs folder, so they can be
/// sent back from Files along with the session log. iOS hands them over on the launch after a
/// crash; nothing leaves the phone.
final class CrashReports: NSObject, MXMetricManagerSubscriber, @unchecked Sendable {
    private let directory: URL
    private let note: @Sendable (String) -> Void

    init(directory: URL, note: @escaping @Sendable (String) -> Void) {
        self.directory = directory
        self.note = note
    }

    func start() {
        MXMetricManager.shared.add(self)
        save(MXMetricManager.shared.pastDiagnosticPayloads)
    }

    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        save(payloads)
    }

    private func save(_ payloads: [MXDiagnosticPayload]) {
        let formatter = ISO8601DateFormatter()
        for payload in payloads {
            let stamp = formatter.string(from: payload.timeStampBegin).replacingOccurrences(of: ":", with: "-")
            let url = directory.appendingPathComponent("diagnostics-\(stamp).json")
            // Past payloads come back on every launch; keep one copy of each.
            guard !FileManager.default.fileExists(atPath: url.path) else { continue }
            do {
                try payload.jsonRepresentation().write(to: url)
                let crashes = payload.crashDiagnostics?.count ?? 0
                let hangs = payload.hangDiagnostics?.count ?? 0
                note("diagnostics from \(stamp): \(crashes) crashes, \(hangs) hangs → \(url.lastPathComponent)")
            } catch {
                note("diagnostics \(stamp): \(error)")
            }
        }
    }
}
