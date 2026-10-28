import JSONSchema
import JSONSchemaBuilder

/// `settings.json`: user preferences.
@Schemable
@ObjectOptions(.additionalProperties(false))
public struct Settings: VersionedDocument, Equatable {
    public static let currentVersion = 4
    public static let schemaName = "settings"

    public var schemaURI: String?
    public var schemaVersion: Int
    public var engine: SpeechEngineID
    /// Global speaking-rate multiplier.
    @NumberOptions(.minimum(0.5), .maximum(2.0))
    public var speed: Double
    /// Seconds between checks while no dialogue box is visible.
    @NumberOptions(.minimum(0.25), .maximum(3))
    public var idleSampleInterval: Double
    /// Samples per second while a dialogue box is visible.
    @NumberOptions(.minimum(1), .maximum(10))
    public var dialogueSampleRate: Double
    public var speakBattleText: Bool
    /// The built-in camera faces the player, so it is only allowed when chosen explicitly.
    public var allowBuiltInCamera: Bool
    public var keys: Keys

    enum CodingKeys: String, CodingKey {
        case schemaURI = "$schema"
        case schemaVersion, engine, speed, idleSampleInterval, dialogueSampleRate
        case speakBattleText, allowBuiltInCamera, keys
    }

    /// Version 1 had global ⌥⌘ hotkeys; version 2 has plain keys that work while the app is in front.
    /// Version 3 makes the Qwen3 character voices the default: "apple" in an older file was only the
    /// old default, never a choice.
    /// Version 4 checks for dialogue twice a second when idle; 2 s in an older file was the old default.
    public static func migrate(_ json: JSONValue, from version: Int) throws(DocumentError) -> JSONValue {
        if version == 3, case .object(var object) = json {
            if case .numberLiteral(let interval) = object["idleSampleInterval"], interval == JSONNumberLiteral(2) {
                object["idleSampleInterval"] = .numberLiteral(try! JSONNumberLiteral(0.5))
            }
            object["schemaVersion"] = .numberLiteral(JSONNumberLiteral(4))
            return .object(object)
        }
        if version == 2, case .object(var object) = json {
            object["engine"] = .string(SpeechEngineID.qwen3.rawValue)
            object["schemaVersion"] = .numberLiteral(JSONNumberLiteral(3))
            return .object(object)
            return .object(object)
        }
        guard version == 1, case .object(var object) = json else { throw .noMigration(from: version) }
        object.removeValue(forKey: "hotkeys")
        object["keys"] = .object([
            "repeatLast": .string(Keys.defaults.repeatLast),
            "repeatLastSlowly": .string(Keys.defaults.repeatLastSlowly),
            "toggleSpeed": .string(Keys.defaults.toggleSpeed),
            "togglePause": .string(Keys.defaults.togglePause),
            "recalibrate": .string(Keys.defaults.recalibrate),
            "holdForEnglish": .string(Keys.defaults.holdForEnglish),
        ])
        object["schemaVersion"] = .numberLiteral(JSONNumberLiteral(2))
        return .object(object)
    }

    public static let defaults = Settings(
        schemaURI: nil,
        schemaVersion: currentVersion,
        engine: .qwen3,
        speed: 0.85,
        idleSampleInterval: 0.5,
        dialogueSampleRate: 4,
        speakBattleText: false,
        allowBuiltInCamera: false,
        keys: .defaults
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
        keys: Keys
    ) {
        self.schemaURI = schemaURI
        self.schemaVersion = schemaVersion
        self.engine = engine
        self.speed = speed
        self.idleSampleInterval = idleSampleInterval
        self.dialogueSampleRate = dialogueSampleRate
        self.speakBattleText = speakBattleText
        self.allowBuiltInCamera = allowBuiltInCamera
        self.keys = keys
    }
}

@Schemable
public enum SpeechEngineID: String, Codable, Sendable, CaseIterable {
    case apple
    case qwen3
    case kokoro
}

/// Keys that work while Hablamon is the front app: a letter, digit, or `space`, optionally with
/// `shift+`. No ⌘ or ⌥, so they never clash with other apps' shortcuts.
@Schemable
@ObjectOptions(.additionalProperties(false))
public struct Keys: Codable, Sendable, Equatable {
    @StringOptions(.pattern(Keys.pattern))
    public var repeatLast: String
    @StringOptions(.pattern(Keys.pattern))
    public var repeatLastSlowly: String
    @StringOptions(.pattern(Keys.pattern))
    public var toggleSpeed: String
    @StringOptions(.pattern(Keys.pattern))
    public var togglePause: String
    @StringOptions(.pattern(Keys.pattern))
    public var recalibrate: String
    /// Held down, shows the labels in English.
    @StringOptions(.pattern(Keys.pattern))
    public var holdForEnglish: String
    /// Switches between the iPhone and the Mac's camera; `m` when absent. New keys are optional so
    /// existing settings files keep loading without a migration.
    @StringOptions(.pattern(Keys.pattern))
    public var toggleCamera: String?
    /// Opens or closes the recap (conversation and session words); `h` when absent.
    @StringOptions(.pattern(Keys.pattern))
    public var toggleRecap: String?
    /// Opens the whole-screen translation (Escape or the same key closes it); `t` when absent.
    @StringOptions(.pattern(Keys.pattern))
    public var translateScreen: String?

    public static let pattern = "^(shift\\+)?([a-z0-9]|space)$"

    public static let defaults = Keys(
        repeatLast: "r",
        repeatLastSlowly: "shift+r",
        toggleSpeed: "s",
        togglePause: "space",
        recalibrate: "c",
        holdForEnglish: "e"
    )

    public init(
        repeatLast: String,
        repeatLastSlowly: String,
        toggleSpeed: String,
        togglePause: String,
        recalibrate: String,
        holdForEnglish: String,
        toggleCamera: String? = nil,
        toggleRecap: String? = nil,
        translateScreen: String? = nil
    ) {
        self.repeatLast = repeatLast
        self.repeatLastSlowly = repeatLastSlowly
        self.toggleSpeed = toggleSpeed
        self.togglePause = togglePause
        self.recalibrate = recalibrate
        self.holdForEnglish = holdForEnglish
        self.toggleCamera = toggleCamera
        self.toggleRecap = toggleRecap
        self.translateScreen = translateScreen
    }
}
