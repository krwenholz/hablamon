import JSONSchemaBuilder

/// `voices/manifest.json`: reference clips designed offline for cloning engines.
@Schemable
@ObjectOptions(.additionalProperties(false))
public struct VoiceManifest: VersionedDocument, Equatable {
    public static let currentVersion = 1
    public static let schemaName = "voice-manifest"

    public var schemaVersion: Int
    /// Keyed by character name, matching `characters.json`.
    public var voices: [String: DesignedVoice]

    public init(
        schemaVersion: Int = currentVersion,
        voices: [String: DesignedVoice]
    ) {
        self.schemaVersion = schemaVersion
        self.voices = voices
    }
}

@Schemable
@ObjectOptions(.additionalProperties(false))
public struct DesignedVoice: Codable, Sendable, Equatable {
    public var engine: SpeechEngineID
    /// WAV clip relative to the Application Support folder.
    @StringOptions(.minLength(1))
    public var referenceClip: String
    /// Description the clip was designed from.
    public var prompt: String
    @StringOptions(.format("date-time"))
    public var createdAt: String
    /// What the clip says, for cloning that uses the transcript. Optional so older manifests load.
    public var referenceText: String?

    public init(
        engine: SpeechEngineID,
        referenceClip: String,
        prompt: String,
        createdAt: String,
        referenceText: String? = nil
    ) {
        self.engine = engine
        self.referenceClip = referenceClip
        self.prompt = prompt
        self.createdAt = createdAt
        self.referenceText = referenceText
    }
}
