import JSONSchemaBuilder

/// `known-words.json`: lemmas the player marked "Ya la sé", which the vocabulary panel never shows again.
@Schemable
@ObjectOptions(.additionalProperties(false))
public struct KnownWords: VersionedDocument, Equatable {
    public static let currentVersion = 1
    public static let schemaName = "known-words"

    public var schemaURI: String?
    public var schemaVersion: Int
    /// Lowercased lemmas, sorted and unique.
    public var lemmas: [String]

    enum CodingKeys: String, CodingKey {
        case schemaURI = "$schema"
        case schemaVersion, lemmas
    }

    public init(schemaURI: String? = nil, schemaVersion: Int = currentVersion, lemmas: [String]) {
        self.schemaURI = schemaURI
        self.schemaVersion = schemaVersion
        self.lemmas = lemmas
    }
}
