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
        /// A pixel counts as changed when it moves by more than this fraction of the crop's contrast…
        public var toleranceFraction: Double
        /// …but never less than this many levels (noise on near-blank crops)…
        public var minTolerance: Int
        /// …or more than this many (crisp, high-contrast pages).
        public var maxTolerance: Int
        /// Fraction of changed pixels below which a frame counts as "not changing".
        public var stillThreshold: Double
        /// Consecutive still samples needed to settle (3 at ~4 Hz is ~750 ms).
        public var stillSamples: Int
        /// Fraction of pixels changed since the settled snapshot that means a new page started.
        public var pageChangeThreshold: Double

        /// Defaults tuned on far.mp4; see docs/plans/done/spike-a-ocr.md.
        public init(
            toleranceFraction: Double = 0.25,
            minTolerance: Int = 8,
            maxTolerance: Int = 24,
            stillThreshold: Double = 0.006,
            stillSamples: Int = 3,
            pageChangeThreshold: Double = 0.03
        ) {
            self.toleranceFraction = toleranceFraction
            self.minTolerance = minTolerance
            self.maxTolerance = maxTolerance
            self.stillThreshold = stillThreshold
            self.stillSamples = stillSamples
            self.pageChangeThreshold = pageChangeThreshold
        }
    }

    public var configuration: Configuration
    private var previous: GrayImage?
    /// The crop when the page settled. Comparing against it, rather than the previous frame,
    /// catches a faint new page that changes only a little per sample.
    private var settledSnapshot: GrayImage?
    private var stillCount = 0

    public init(configuration: Configuration = .init()) {
        self.configuration = configuration
    }

    public mutating func observe(_ crop: GrayImage) -> Event? {
        defer { previous = crop }
        guard let previous, previous.width == crop.width, previous.height == crop.height else {
            stillCount = 0
            return nil
        }
        if let settledSnapshot {
            guard difference(crop, settledSnapshot) > configuration.pageChangeThreshold else { return nil }
            self.settledSnapshot = nil
            stillCount = 0
            return .pageChanged
        }
        stillCount = difference(crop, previous) < configuration.stillThreshold ? stillCount + 1 : 0
        guard stillCount >= configuration.stillSamples else { return nil }
        settledSnapshot = crop
        return .settled
    }

    func difference(_ a: GrayImage, _ b: GrayImage) -> Double {
        let contrast = Double(max(a.contrastRange, b.contrastRange))
        let tolerance = min(
            configuration.maxTolerance,
            max(configuration.minTolerance, Int(configuration.toleranceFraction * contrast))
        )
        return a.changedFraction(from: b, tolerance: UInt8(tolerance))
    }

    /// Call when the dialogue box disappears.
    public mutating func reset() {
        previous = nil
        settledSnapshot = nil
        stillCount = 0
    }
}
