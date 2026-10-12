import JSONSchemaBuilder

/// `characters.json`: everyone who can appear in a dialogue name tag, keyed by the
/// Spanish (Spain) name as the game shows it.
@Schemable
@ObjectOptions(.additionalProperties(false))
public struct CharacterTable: VersionedDocument, Equatable {
    public static let currentVersion = 1
    public static let schemaName = "characters"

    /// Path or URL of the JSON Schema, for editor autocomplete.
    public var schemaURI: String?
    public var schemaVersion: Int
    public var characters: [String: Speaker]

    enum CodingKeys: String, CodingKey {
        case schemaURI = "$schema"
        case schemaVersion
        case characters
    }

    public init(schemaURI: String? = nil, schemaVersion: Int = currentVersion, characters: [String: Speaker]) {
        self.schemaURI = schemaURI
        self.schemaVersion = schemaVersion
        self.characters = characters
    }
}

@Schemable
@ObjectOptions(.additionalProperties(false))
public struct Speaker: Codable, Sendable, Equatable {
    /// Name in the English release, for reference.
    public var englishName: String?
    public var gender: Gender
    public var ageGroup: AgeGroup?
    /// Who the character is, in a few words.
    public var role: String?
    /// How the character should sound; input for designing generated voices.
    public var description: String?
    /// Other name-tag texts that resolve to this speaker, such as a disguise or title.
    public var aliases: [String]?
    /// Set when the character appears in only one version of the game.
    public var version: GameVersion?
    public var voices: VoiceAssignments?

    public init(
        englishName: String? = nil,
        gender: Gender,
        ageGroup: AgeGroup? = nil,
        role: String? = nil,
        description: String? = nil,
        aliases: [String]? = nil,
        version: GameVersion? = nil,
        voices: VoiceAssignments? = nil
    ) {
        self.englishName = englishName
        self.gender = gender
        self.ageGroup = ageGroup
        self.role = role
        self.description = description
        self.aliases = aliases
        self.version = version
        self.voices = voices
    }
}

@Schemable
public enum Gender: String, Codable, Sendable, CaseIterable {
    case male
    case female
    case neutral
    case unknown
}

@Schemable
public enum AgeGroup: String, Codable, Sendable, CaseIterable {
    case child
    case teen
    case adult
    case elder
}

@Schemable
public enum GameVersion: String, Codable, Sendable, CaseIterable {
    case scarlet
    case violet
}

/// Per-engine voice settings. Engines without an entry fall back to defaults for the speaker's gender and age.
@Schemable
@ObjectOptions(.additionalProperties(false))
public struct VoiceAssignments: Codable, Sendable, Equatable {
    public var apple: AppleVoice?
    public var qwen3: ClonedVoice?
    public var kokoro: KokoroVoice?

    public init(apple: AppleVoice? = nil, qwen3: ClonedVoice? = nil, kokoro: KokoroVoice? = nil) {
        self.apple = apple
        self.qwen3 = qwen3
        self.kokoro = kokoro
    }
}

@Schemable
@ObjectOptions(.additionalProperties(false))
public struct AppleVoice: Codable, Sendable, Equatable {
    /// `AVSpeechSynthesisVoice` identifier; omit to use the default es-ES voice.
    public var voice: String?
    /// `AVSpeechUtterance.pitchMultiplier`.
    @NumberOptions(.minimum(0.5), .maximum(2.0))
    public var pitch: Double?
    /// Multiplier on the global speaking rate.
    @NumberOptions(.minimum(0.5), .maximum(2.0))
    public var rate: Double?

    public init(voice: String? = nil, pitch: Double? = nil, rate: Double? = nil) {
        self.voice = voice
        self.pitch = pitch
        self.rate = rate
    }
}

@Schemable
@ObjectOptions(.additionalProperties(false))
public struct ClonedVoice: Codable, Sendable, Equatable {
    /// Short WAV clip the engine clones, relative to the Application Support folder.
    @StringOptions(.minLength(1))
    public var referenceClip: String

    public init(referenceClip: String) {
        self.referenceClip = referenceClip
    }
}

@Schemable
@ObjectOptions(.additionalProperties(false))
public struct KokoroVoice: Codable, Sendable, Equatable {
    /// Kokoro voice ID, such as `ef_dora`.
    @StringOptions(.minLength(1))
    public var voice: String

    public init(voice: String) {
        self.voice = voice
    }
}
