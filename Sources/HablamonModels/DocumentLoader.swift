import JSONSchema
import JSONSchemaBuilder

/// Why a document could not be loaded. Messages name the offending JSON path.
public enum DocumentError: Error, Equatable, CustomStringConvertible {
    case invalidJSON(String)
    case missingVersion(key: String)
    case newerVersion(found: Int, supported: Int)
    case noMigration(from: Int)
    case invalid([Issue])

    public struct Issue: Equatable, Sendable, CustomStringConvertible {
        /// JSON Pointer to the value, e.g. `/characters/Clavel/gender`.
        public var path: String
        public var message: String

        public init(path: String, message: String) {
            self.path = path
            self.message = message
        }

        public var description: String { "\(path.isEmpty ? "/" : path): \(message)" }
    }

    public var description: String {
        switch self {
        case .invalidJSON(let reason):
            "not valid JSON: \(reason)"
        case .missingVersion(let key):
            "missing integer \"\(key)\""
        case .newerVersion(let found, let supported):
            "version \(found) is newer than this build supports (\(supported)); update Hablamon"
        case .noMigration(let from):
            "no migration from version \(from)"
        case .invalid(let issues):
            issues.map(\.description).joined(separator: "\n")
        }
    }
}

/// Loads versioned documents: parse, migrate to the current version, validate, then build the Swift value.
public enum DocumentLoader {
    public static func load<T: VersionedDocument>(_ type: T.Type, from text: String) throws(DocumentError) -> T {
        let json: JSONValue
        do {
            json = try JSONValue.parse(text)
        } catch {
            throw .invalidJSON(String(describing: error))
        }
        return try load(type, from: json)
    }

    public static func load<T: VersionedDocument>(_ type: T.Type, from json: JSONValue) throws(DocumentError) -> T {
        var json = json
        var version = try readVersion(of: json, key: T.versionKey)
        if version > T.currentVersion {
            throw .newerVersion(found: version, supported: T.currentVersion)
        }
        while version < T.currentVersion {
            json = try T.migrate(json, from: version)
            version += 1
        }
        let result = T.schema.definition().validate(json)
        guard result.isValid else {
            throw .invalid(issues(from: result))
        }
        do {
            return try T.schema.parseAndValidate(json)
        } catch {
            throw .invalid([.init(path: "", message: String(describing: error))])
        }
    }

    static func readVersion(of json: JSONValue, key: String) throws(DocumentError) -> Int {
        guard case .object(let object) = json,
            case .numberLiteral(let number)? = object[key],
            let version = try? number.integerValue()
        else {
            throw .missingVersion(key: key)
        }
        return version
    }

    /// Flattens nested validation errors to their leaves, which carry the specific messages.
    static func issues(from result: ValidationResult) -> [DocumentError.Issue] {
        var issues: [DocumentError.Issue] = []
        func collect(_ errors: [ValidationError]) {
            for error in errors {
                if let nested = error.errors, !nested.isEmpty {
                    collect(nested)
                } else {
                    // A `false` schema (from additionalProperties) fails without a message.
                    let message = error.message.isEmpty && error.keyword == "boolean" ? "unexpected key" : error.message
                    let issue = DocumentError.Issue(path: error.instanceLocation.jsonPointerString, message: message)
                    if !issues.contains(issue) { issues.append(issue) }
                }
            }
        }
        collect(result.errors ?? [])
        if issues.isEmpty {
            issues.append(.init(path: "", message: "does not match the schema"))
        }
        return issues
    }
}
