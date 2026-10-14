/// Waits for the typewriter animation to finish so each dialogue page is OCR'd once.
///
/// Feed it the downscaled body-text crop on every dialogue-mode sample. It reports `.settled` once
/// the crop stops changing, and `.pageChanged` when a large change after that means the player
/// advanced to a new page.
public struct SettleDetector: Sendable {
    public enum Event: Equatable, Sendable {
        /// The page finished typing; OCR it now.
        case settled
        /// The text changed substantially after settling: a new page started.
        case pageChanged
    }

    public struct Configuration: Sendable, Equatable {
        /// A pixel counts as changed when it moves by more than this many levels.
        public var pixelTolerance: UInt8
        /// Fraction of changed pixels below which a frame counts as "not changing".
        public var stillThreshold: Double
        /// Consecutive still samples needed to settle (3 at ~4 Hz is ~750 ms).
        public var stillSamples: Int
        /// Fraction of changed pixels above which, after settling, a new page started.
        public var pageChangeThreshold: Double

        public init(
            pixelTolerance: UInt8 = 24,
            stillThreshold: Double = 0.002,
            stillSamples: Int = 3,
            pageChangeThreshold: Double = 0.05
        ) {
            self.pixelTolerance = pixelTolerance
            self.stillThreshold = stillThreshold
            self.stillSamples = stillSamples
            self.pageChangeThreshold = pageChangeThreshold
        }
    }

    public var configuration: Configuration
    private var previous: GrayImage?
    private var stillCount = 0
    private var hasSettled = false

    public init(configuration: Configuration = .init()) {
        self.configuration = configuration
    }

    public mutating func observe(_ crop: GrayImage) -> Event? {
        defer { previous = crop }
        guard let previous, previous.width == crop.width, previous.height == crop.height else {
            stillCount = 0
            return nil
        }
        let difference = crop.changedFraction(from: previous, tolerance: configuration.pixelTolerance)
        if hasSettled {
            guard difference > configuration.pageChangeThreshold else { return nil }
            hasSettled = false
            stillCount = 0
            return .pageChanged
        }
        stillCount = difference < configuration.stillThreshold ? stillCount + 1 : 0
        guard stillCount >= configuration.stillSamples else { return nil }
        hasSettled = true
        return .settled
    }

    /// Call when the dialogue box disappears.
    public mutating func reset() {
        previous = nil
        stillCount = 0
        hasSettled = false
    }
}
