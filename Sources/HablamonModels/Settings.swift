import JSONSchemaBuilder

/// `settings.json`: user preferences.
@Schemable
@ObjectOptions(.additionalProperties(false))
public struct Settings: VersionedDocument, Equatable {
    public static let currentVersion = 1
    public static let schemaName = "settings"

    public var schemaURI: String?
    public var schemaVersion: Int
    public var engine: SpeechEngineID
    /// Global speaking-rate multiplier.
    @NumberOptions(.minimum(0.5), .maximum(2.0))
    public var speed: Double
    /// Seconds between checks while no dialogue box is visible.
    @NumberOptions(.minimum(1), .maximum(3))
    public var idleSampleInterval: Double
    /// Samples per second while a dialogue box is visible.
    @NumberOptions(.minimum(1), .maximum(10))
    public var dialogueSampleRate: Double
    public var speakBattleText: Bool
    /// The built-in camera faces the player, so it is only allowed when chosen explicitly.
    public var allowBuiltInCamera: Bool
    public var hotkeys: Hotkeys

    enum CodingKeys: String, CodingKey {
        case schemaURI = "$schema"
        case schemaVersion, engine, speed, idleSampleInterval, dialogueSampleRate
        case speakBattleText, allowBuiltInCamera, hotkeys
    }

    public static let defaults = Settings(
        schemaURI: nil,
        schemaVersion: currentVersion,
        engine: .apple,
        speed: 0.85,
        idleSampleInterval: 2,
        dialogueSampleRate: 4,
        speakBattleText: false,
        allowBuiltInCamera: false,
        hotkeys: .defaults
    )

    public init(
        schemaURI: String? = nil,
        schemaVersion: Int = currentVersion,
        engine: SpeechEngineID,
        speed: Double,
        idleSampleInterval: Double,
        dialogueSampleRate: Double,
        speakBattleText: Bool,
        allowBuiltInCamera: Bool,
        hotkeys: Hotkeys
    ) {
        self.schemaURI = schemaURI
        self.schemaVersion = schemaVersion
        self.engine = engine
        self.speed = speed
        self.idleSampleInterval = idleSampleInterval
        self.dialogueSampleRate = dialogueSampleRate
        self.speakBattleText = speakBattleText
        self.allowBuiltInCamera = allowBuiltInCamera
        self.hotkeys = hotkeys
    }
}

@Schemable
public enum SpeechEngineID: String, Codable, Sendable, CaseIterable {
    case apple
    case qwen3
    case kokoro
}

/// Global hotkeys, written as modifiers and a key joined by `+`, such as `opt+cmd+R`.
@Schemable
@ObjectOptions(.additionalProperties(false))
public struct Hotkeys: Codable, Sendable, Equatable {
    @StringOptions(.pattern(Hotkeys.pattern))
    public var repeatLast: String
    @StringOptions(.pattern(Hotkeys.pattern))
    public var repeatLastSlowly: String
    @StringOptions(.pattern(Hotkeys.pattern))
    public var toggleSpeed: String
    @StringOptions(.pattern(Hotkeys.pattern))
    public var togglePause: String
    @StringOptions(.pattern(Hotkeys.pattern))
    public var recalibrate: String
    /// Held down, shows the labels in English.
    @StringOptions(.pattern(Hotkeys.pattern))
    public var holdForEnglish: String

    public static let pattern = "^((ctrl|opt|shift|cmd)\\+)+[A-Z0-9]$"

    public static let defaults = Hotkeys(
        repeatLast: "opt+cmd+R",
        repeatLastSlowly: "opt+shift+cmd+R",
        toggleSpeed: "opt+cmd+S",
        togglePause: "opt+cmd+P",
        recalibrate: "opt+cmd+C",
        holdForEnglish: "opt+cmd+E"
    )

    public init(
        repeatLast: String,
        repeatLastSlowly: String,
        toggleSpeed: String,
        togglePause: String,
        recalibrate: String,
        holdForEnglish: String
    ) {
        self.repeatLast = repeatLast
        self.repeatLastSlowly = repeatLastSlowly
        self.toggleSpeed = toggleSpeed
        self.togglePause = togglePause
        self.recalibrate = recalibrate
        self.holdForEnglish = holdForEnglish
    }
}
