import Foundation
import HablamonModels

/// A loaded document, or the fallback used when the file on disk was broken.
public struct Loaded<T: Sendable>: Sendable {
    public var value: T
    /// Why the file on disk wasn't used, for the diagnostics panel. Nil when it loaded or was absent.
    public var issue: String?
}

/// The app's files in Application Support. Everything durable lives here, in the user's home
/// directory, so reinstalling the app never touches settings, characters, transcripts, or logs.
public struct AppSupportStore: Sendable {
    public let root: URL

    public init(root: URL = AppSupportStore.defaultRoot) {
        self.root = root
    }

    public static var defaultRoot: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Hablamon", isDirectory: true)
    }

    public var sessionsDirectory: URL { root.appendingPathComponent("sessions", isDirectory: true) }
    public var logsDirectory: URL { root.appendingPathComponent("logs", isDirectory: true) }

    var charactersURL: URL { root.appendingPathComponent("characters.json") }
    var settingsURL: URL { root.appendingPathComponent("settings.json") }
    var knownWordsURL: URL { root.appendingPathComponent("known-words.json") }

    /// Writes `characters.json` and `settings.json` from the bundled defaults if they don't exist yet.
    public func seedIfNeeded() throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        if !exists(charactersURL) {
            var table = try BundledData.defaultCharacters()
            table.schemaURI = Self.schemaTag(CharacterTable.self)
            try write(table, to: charactersURL)
        }
        if !exists(settingsURL) {
            var settings = Settings.defaults
            settings.schemaURI = Self.schemaTag(Settings.self)
            try write(settings, to: settingsURL)
        }
    }

    public func characters() -> Loaded<CharacterTable> {
        load(CharacterTable.self, from: charactersURL) {
            (try? BundledData.defaultCharacters()) ?? CharacterTable(characters: [:])
        }
    }

    public func settings() -> Loaded<Settings> {
        load(Settings.self, from: settingsURL) { Settings.defaults }
    }

    public func knownWords() -> Loaded<KnownWords> {
        load(KnownWords.self, from: knownWordsURL) { KnownWords(lemmas: []) }
    }

    public func save(_ table: CharacterTable) throws {
        var table = table
        table.schemaURI = table.schemaURI ?? Self.schemaTag(CharacterTable.self)
        try write(table, to: charactersURL)
    }

    public func save(_ words: KnownWords) throws {
        var words = words
        words.schemaURI = words.schemaURI ?? Self.schemaTag(KnownWords.self)
        words.lemmas = Array(Set(words.lemmas.map { $0.lowercased() })).sorted()
        try write(words, to: knownWordsURL)
    }

    /// Every line from every past session, oldest file first. Unreadable files are skipped.
    public func pastLines() -> [TranscriptLine] {
        let files =
            (try? FileManager.default.contentsOfDirectory(at: sessionsDirectory, includingPropertiesForKeys: nil))
            ?? []
        return files.filter { $0.pathExtension == "jsonl" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .flatMap { file in
                ((try? TranscriptReader.entries(at: file)) ?? []).compactMap { entry in
                    if case .line(let line) = entry { line } else { nil }
                }
            }
    }

    /// Marks a seeded file's type without a URL, so editors never fetch anything over the network.
    static func schemaTag<T: VersionedDocument>(_ type: T.Type) -> String { "hablamon:\(T.schemaName)" }

    private func exists(_ url: URL) -> Bool { FileManager.default.fileExists(atPath: url.path) }

    private func load<T: VersionedDocument>(_ type: T.Type, from url: URL, fallback: () -> T) -> Loaded<T> {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            return Loaded(value: fallback(), issue: nil)
        }
        do {
            return Loaded(value: try DocumentLoader.load(T.self, from: text), issue: nil)
        } catch {
            return Loaded(value: fallback(), issue: "\(url.lastPathComponent): \(error)")
        }
    }

    private func write<T: Encodable>(_ value: T, to url: URL) throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(value).write(to: url, options: .atomic)
    }
}
