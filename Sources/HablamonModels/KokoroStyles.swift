import JSONSchemaBuilder

/// `voices/kokoro-styles.json`: each designed voice as a Kokoro style vector, cloned from its
/// reference clip by `scripts/clone-kokoro-voices.py`, for the fast Kokoro engine.
@Schemable
@ObjectOptions(.additionalProperties(false))
public struct KokoroStyles: VersionedDocument, Equatable {
    public static let currentVersion = 1
    public static let schemaName = "kokoro-styles"
    /// Floats in one style vector.
    public static let styleLength = 256

    public var schemaVersion: Int
    /// Keyed by voice name, matching `voices/manifest.json`.
    public var styles: [String: [Double]]

    public init(schemaVersion: Int = currentVersion, styles: [String: [Double]]) {
        self.schemaVersion = schemaVersion
        self.styles = styles
    }
}
