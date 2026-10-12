import JSONSchemaBuilder

/// `calibration.json`: the pinned camera and where the TV screen is in its frame.
@Schemable
@ObjectOptions(.additionalProperties(false))
public struct Calibration: VersionedDocument, Equatable {
    public static let currentVersion = 1
    public static let schemaName = "calibration"

    public var schemaVersion: Int
    /// `AVCaptureDevice.uniqueID` of the pinned camera.
    @StringOptions(.minLength(1))
    public var deviceID: String
    public var deviceName: String?
    /// TV screen corners in source-camera pixels.
    public var screenQuad: Quad
    /// `AVCaptureDevice.videoZoomFactor` in use when calibrated.
    @NumberOptions(.minimum(1))
    public var zoomFactor: Double
    /// Grayscale thumbnail of the corrected bezel, relative to the Application Support folder.
    public var referenceThumbnail: String
    /// ISO 8601 timestamp.
    @StringOptions(.format("date-time"))
    public var calibratedAt: String

    public init(
        schemaVersion: Int = currentVersion,
        deviceID: String,
        deviceName: String? = nil,
        screenQuad: Quad,
        zoomFactor: Double,
        referenceThumbnail: String,
        calibratedAt: String
    ) {
        self.schemaVersion = schemaVersion
        self.deviceID = deviceID
        self.deviceName = deviceName
        self.screenQuad = screenQuad
        self.zoomFactor = zoomFactor
        self.referenceThumbnail = referenceThumbnail
        self.calibratedAt = calibratedAt
    }
}

@Schemable
@ObjectOptions(.additionalProperties(false))
public struct Quad: Codable, Sendable, Equatable {
    public var topLeft: Point
    public var topRight: Point
    public var bottomRight: Point
    public var bottomLeft: Point

    public init(topLeft: Point, topRight: Point, bottomRight: Point, bottomLeft: Point) {
        self.topLeft = topLeft
        self.topRight = topRight
        self.bottomRight = bottomRight
        self.bottomLeft = bottomLeft
    }
}

@Schemable
@ObjectOptions(.additionalProperties(false))
public struct Point: Codable, Sendable, Equatable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}
