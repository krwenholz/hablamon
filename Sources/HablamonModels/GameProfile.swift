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
    public var detection: BoxDetection

    enum CodingKeys: String, CodingKey {
        case schemaURI = "$schema"
        case schemaVersion, id, name, frameSize, regions, detection
    }

    public init(
        schemaURI: String? = nil,
        schemaVersion: Int = currentVersion,
        id: String,
        name: String,
        frameSize: PixelSize,
        regions: ProfileRegions,
        detection: BoxDetection
    ) {
        self.schemaURI = schemaURI
        self.schemaVersion = schemaVersion
        self.id = id
        self.name = name
        self.frameSize = frameSize
        self.regions = regions
        self.detection = detection
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
    /// The rows of `bodyText` that hold the two text lines; the rest of `bodyText` is blank panel.
    public var textLines: PixelRect
    public var nameTag: PixelRect
    /// The blinking ▼ shown when a page has finished typing.
    public var advanceIndicator: PixelRect?

    public init(
        dialogueBox: PixelRect,
        bodyText: PixelRect,
        textLines: PixelRect,
        nameTag: PixelRect,
        advanceIndicator: PixelRect? = nil
    ) {
        self.dialogueBox = dialogueBox
        self.bodyText = bodyText
        self.textLines = textLines
        self.nameTag = nameTag
        self.advanceIndicator = advanceIndicator
    }
}

/// Thresholds for "a dialogue box is on screen", measured on the body-text and name-tag crops.
///
/// Brightness and color alone fail when the phone overexposes the TV (everything reads white), so
/// detection relies on structure: the box's blank margins above and below the text have almost no
/// edges, while scenery is busy everywhere. See docs/plans/spike-a-ocr.md.
@Schemable
@ObjectOptions(.additionalProperties(false))
public struct BoxDetection: Codable, Sendable, Equatable {
    /// Luminance step (0–1) between vertically adjacent pixels that counts as an edge.
    @NumberOptions(.minimum(0), .maximum(1))
    public var edgeStep: Double
    /// Maximum edge density in the body-text rows outside `textLines`, where the panel is blank.
    @NumberOptions(.minimum(0), .maximum(1))
    public var maxMarginEdgeDensity: Double
    /// Minimum edge density within `textLines`.
    @NumberOptions(.minimum(0), .maximum(1))
    public var minTextEdgeDensity: Double
    /// A name-tag pixel counts as tag color when its saturation is above this and blue is its strongest channel.
    @NumberOptions(.minimum(0), .maximum(1))
    public var tagSaturation: Double
    /// Fraction of the name-tag region that must be tag color for the line to have a speaker.
    @NumberOptions(.minimum(0), .maximum(1))
    public var minTagFraction: Double

    public init(
        edgeStep: Double,
        maxMarginEdgeDensity: Double,
        minTextEdgeDensity: Double,
        tagSaturation: Double,
        minTagFraction: Double
    ) {
        self.edgeStep = edgeStep
        self.maxMarginEdgeDensity = maxMarginEdgeDensity
        self.minTextEdgeDensity = minTextEdgeDensity
        self.tagSaturation = tagSaturation
        self.minTagFraction = minTagFraction
    }
}
