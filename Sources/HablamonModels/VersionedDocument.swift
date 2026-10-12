import JSONSchema
import JSONSchemaBuilder

/// A JSON file Hablamon reads or writes.
///
/// The Swift type is the source of truth: its `@Schemable` schema is exported to
/// `schemas/` and used to validate files before they are parsed.
public protocol VersionedDocument: Schemable, Codable, Sendable where Schema.Output == Self {
    /// The version this build writes. Older files are migrated on load; newer ones are refused.
    static var currentVersion: Int { get }
    /// Base name of the exported schema file, e.g. `characters` for `characters.schema.json`.
    static var schemaName: String { get }
    /// Top-level key holding the version. Transcript lines use `v` to stay short.
    static var versionKey: String { get }
    /// Upgrades a raw document from `version` to `version + 1`.
    static func migrate(_ json: JSONValue, from version: Int) throws(DocumentError) -> JSONValue
}

extension VersionedDocument {
    public static var versionKey: String { "schemaVersion" }

    public static func migrate(_ json: JSONValue, from version: Int) throws(DocumentError) -> JSONValue {
        throw .noMigration(from: version)
    }
}
