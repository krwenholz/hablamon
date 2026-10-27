import HablamonModels

/// An 8-bit RGBA image, row-major. Like `GrayImage`, it keeps detection logic platform-neutral.
public struct RGBAImage: Sendable, Equatable {
    public let width: Int
    public let height: Int
    public var pixels: [UInt8]

    public init(width: Int, height: Int, pixels: [UInt8]) {
        precondition(width > 0 && height > 0 && pixels.count == width * height * 4, "pixel count must match size")
        self.width = width
        self.height = height
        self.pixels = pixels
    }

    public func luminance(x: Int, y: Int) -> Double {
        let i = (y * width + x) * 4
        return (0.299 * Double(pixels[i]) + 0.587 * Double(pixels[i + 1]) + 0.114 * Double(pixels[i + 2])) / 255
    }

    public func saturation(x: Int, y: Int) -> Double {
        let i = (y * width + x) * 4
        let channels = [pixels[i], pixels[i + 1], pixels[i + 2]]
        let high = Double(channels.max()!)
        let low = Double(channels.min()!)
        return high == 0 ? 0 : (high - low) / high
    }

    /// Grayscale copy, for the settle detector.
    public var gray: GrayImage {
        var values = [UInt8](repeating: 0, count: width * height)
        for y in 0..<height {
            for x in 0..<width { values[y * width + x] = UInt8((luminance(x: x, y: y) * 255).rounded()) }
        }
        return GrayImage(width: width, height: height, pixels: values)
    }
}

/// Structural measurements of one frame's dialogue area, compared against the profile's `BoxDetection`.
public struct BoxFeatures: Sendable, Equatable {
    /// Edge density on the text lines.
    public var textEdgeDensity: Double
    /// Edge density in the body-text rows outside the text lines, where the panel is blank.
    public var marginEdgeDensity: Double
    /// Fraction of the name-tag region that is saturated tag blue.
    public var tagFraction: Double

    public init(textEdgeDensity: Double, marginEdgeDensity: Double, tagFraction: Double) {
        self.textEdgeDensity = textEdgeDensity
        self.marginEdgeDensity = marginEdgeDensity
        self.tagFraction = tagFraction
    }

    /// - Parameters:
    ///   - body: the `bodyText` crop.
    ///   - textRows: rows of `body` covered by `textLines`.
    ///   - nameTag: the `nameTag` crop.
    public init(body: RGBAImage, textRows: Range<Int>, nameTag: RGBAImage, detection: BoxDetection) {
        var textEdges = 0
        var textPixels = 0
        var marginEdges = 0
        var marginPixels = 0
        for y in 1..<body.height {
            let inText = textRows.contains(y)
            for x in 0..<body.width {
                let isEdge = abs(body.luminance(x: x, y: y) - body.luminance(x: x, y: y - 1)) > detection.edgeStep
                if inText {
                    textPixels += 1
                    if isEdge { textEdges += 1 }
                } else {
                    marginPixels += 1
                    if isEdge { marginEdges += 1 }
                }
            }
        }
        var tagPixels = 0
        for y in 0..<nameTag.height {
            for x in 0..<nameTag.width where Self.isTagColor(nameTag, x: x, y: y, saturation: detection.tagSaturation) {
                tagPixels += 1
            }
        }
        self.init(
            textEdgeDensity: Double(textEdges) / Double(max(1, textPixels)),
            marginEdgeDensity: Double(marginEdges) / Double(max(1, marginPixels)),
            tagFraction: Double(tagPixels) / Double(nameTag.width * nameTag.height)
        )
    }

    static func isTagColor(_ image: RGBAImage, x: Int, y: Int, saturation: Double) -> Bool {
        let i = (y * image.width + x) * 4
        let red = image.pixels[i]
        let green = image.pixels[i + 1]
        let blue = image.pixels[i + 2]
        return blue >= red && blue >= green && image.saturation(x: x, y: y) > saturation
    }

    /// A speaker's name tag means the box is up. Without one (narration), require blank margins
    /// around text: scenery has edges everywhere. Tall letters on some pages reach into the margins,
    /// which is why the tag, when present, takes precedence.
    public func isBoxVisible(_ detection: BoxDetection) -> Bool {
        hasNameTag(detection)
            || (marginEdgeDensity <= detection.maxMarginEdgeDensity
                && textEdgeDensity >= detection.minTextEdgeDensity
                && textEdgeDensity > marginEdgeDensity)
    }

    /// Whether the box has a speaker name tag; without one, the line is narration.
    public func hasNameTag(_ detection: BoxDetection) -> Bool {
        tagFraction >= detection.minTagFraction
    }
}

/// Debounces per-sample box detection into "dialogue is on screen".
///
/// Two consecutive positive samples enter dialogue mode, ignoring one-frame flashes; dialogue
/// mode ends once the box has been absent for `exitDelay` seconds.
public struct DialoguePresence: Sendable {
    public var requiredPositives: Int
    public var exitDelay: Double
    public private(set) var isActive = false
    private var positives = 0
    /// A box was seen on the last sample, even if not yet often enough to enter dialogue.
    public var isTentative: Bool { positives > 0 }
    private var lastSeen: Double?

    public init(requiredPositives: Int = 2, exitDelay: Double = 3) {
        self.requiredPositives = requiredPositives
        self.exitDelay = exitDelay
    }

    public enum Change: Equatable, Sendable {
        case entered
        case exited
    }

    /// Records one sample at `time` seconds and reports whether dialogue mode started or ended.
    public mutating func observe(boxVisible: Bool, at time: Double) -> Change? {
        if boxVisible {
            positives += 1
            lastSeen = time
            if !isActive && positives >= requiredPositives {
                isActive = true
                return .entered
            }
            return nil
        }
        positives = 0
        if isActive, let lastSeen, time - lastSeen >= exitDelay {
            isActive = false
            return .exited
        }
        return nil
    }
}
