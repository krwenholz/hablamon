import JSONSchemaBuilder

/// `profiles/<game>.json`: where the dialogue box sits in the corrected frame and what it looks like.
/// Everything game-specific lives here so another game can get its own profile.
@Schemable
@ObjectOptions(.additionalProperties(false))
public struct GameProfile: VersionedDocument, Equatable {
    public static let currentVersion = 1
    public static let schemaName = "game-profile"

    public var schemaURI: String?
    public var schemaVersion: Int
    /// Short identifier, such as `scarlet`.
    @StringOptions(.pattern("^[a-z0-9-]+$"))
    public var id: String
    public var name: String
    /// Size of the perspective-corrected frame the regions are measured in.
    public var frameSize: PixelSize
    public var regions: ProfileRegions
    public var panel: PanelAppearance

    enum CodingKeys: String, CodingKey {
        case schemaURI = "$schema"
        case schemaVersion, id, name, frameSize, regions, panel
    }

    public init(
        schemaURI: String? = nil,
        schemaVersion: Int = currentVersion,
        id: String,
        name: String,
        frameSize: PixelSize,
        regions: ProfileRegions,
        panel: PanelAppearance
    ) {
        self.schemaURI = schemaURI
        self.schemaVersion = schemaVersion
        self.id = id
        self.name = name
        self.frameSize = frameSize
        self.regions = regions
        self.panel = panel
    }
}

@Schemable
@ObjectOptions(.additionalProperties(false))
public struct PixelSize: Codable, Sendable, Equatable {
    @NumberOptions(.minimum(1))
    public var width: Int
    @NumberOptions(.minimum(1))
    public var height: Int

    public init(width: Int, height: Int) {
        self.width = width
        self.height = height
    }
}

@Schemable
@ObjectOptions(.additionalProperties(false))
public struct PixelRect: Codable, Sendable, Equatable {
    @NumberOptions(.minimum(0))
    public var x: Int
    @NumberOptions(.minimum(0))
    public var y: Int
    @NumberOptions(.minimum(1))
    public var width: Int
    @NumberOptions(.minimum(1))
    public var height: Int

    public init(x: Int, y: Int, width: Int, height: Int) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

@Schemable
@ObjectOptions(.additionalProperties(false))
public struct ProfileRegions: Codable, Sendable, Equatable {
    public var dialogueBox: PixelRect
    public var bodyText: PixelRect
    public var nameTag: PixelRect
    /// The blinking ▼ shown when a page has finished typing.
    public var advanceIndicator: PixelRect?

    public init(
        dialogueBox: PixelRect,
        bodyText: PixelRect,
        nameTag: PixelRect,
        advanceIndicator: PixelRect? = nil
    ) {
        self.dialogueBox = dialogueBox
        self.bodyText = bodyText
        self.nameTag = nameTag
        self.advanceIndicator = advanceIndicator
    }
}

/// Statistics that say "a dialogue box is on screen", measured on the `dialogueBox` crop.
@Schemable
@ObjectOptions(.additionalProperties(false))
public struct PanelAppearance: Codable, Sendable, Equatable {
    /// Allowed range for the crop's median luminance.
    public var luminance: UnitRange
    /// Allowed range for the crop's median saturation.
    public var saturation: UnitRange
    /// Minimum fraction of strong-gradient pixels in the body text area (text and borders make edges).
    @NumberOptions(.minimum(0), .maximum(1))
    public var minEdgeDensity: Double

    public init(
        luminance: UnitRange,
        saturation: UnitRange,
        minEdgeDensity: Double
    ) {
        self.luminance = luminance
        self.saturation = saturation
        self.minEdgeDensity = minEdgeDensity
    }
}

/// An inclusive range within 0–1.
@Schemable
@ObjectOptions(.additionalProperties(false))
public struct UnitRange: Codable, Sendable, Equatable {
    @NumberOptions(.minimum(0), .maximum(1))
    public var min: Double
    @NumberOptions(.minimum(0), .maximum(1))
    public var max: Double

    public init(min: Double, max: Double) {
        self.min = min
        self.max = max
    }
}
