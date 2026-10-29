import JSONSchema
import JSONSchemaBuilder

/// Every document type, and their schemas as written to `schemas/`.
public enum SchemaCatalog {
    public static let documents: [any VersionedDocument.Type] = [
        CharacterTable.self,
        GameProfile.self,
        Calibration.self,
        Settings.self,
        VoiceManifest.self,
        KokoroStyles.self,
        KnownWords.self,
        TranscriptEntry.self,
    ]

    public struct ExportedSchema: Sendable, Equatable {
        public var fileName: String
        public var contents: String
    }

    public static func exportAll() throws -> [ExportedSchema] {
        try documents.map { try export($0) }
    }

    public static func export<T: VersionedDocument>(_ type: T.Type) throws -> ExportedSchema {
        guard case .object(var schema) = T.schema.schemaValue.value else {
            preconditionFailure("\(T.self) schema is not an object")
        }
        schema.updateValue(.string("https://json-schema.org/draft/2020-12/schema"), forKey: "$schema", insertingAt: 0)
        schema.updateValue(.string(T.schemaName), forKey: "title", insertingAt: 1)
        let contents = try JSONValue.object(schema).serialized(options: .pretty) + "\n"
        return ExportedSchema(fileName: "\(T.schemaName).schema.json", contents: contents)
    }
}
