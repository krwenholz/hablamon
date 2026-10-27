#if canImport(CoreImage)
    import CoreGraphics
    import CoreImage
    import Foundation

    /// Draws camera frames for the calibration panel straight from the camera, about ten a second,
    /// so the picture stays smooth while the slower analysis runs on its own queue.
    public final class PreviewRenderer: @unchecked Sendable {
        /// Preview width in pixels; height follows the frame's aspect.
        public static let width = 640.0
        public static let interval = 0.1

        private let queue = DispatchQueue(label: "hablamon.preview", qos: .userInitiated)
        private let context = CIContext()
        private let lock = NSLock()
        private var enabled = false
        private var busy = false
        private var lastRender: Date?
        private let onImage: @Sendable (CGImage, Double) -> Void

        /// `onImage` gets the downscaled frame and its scale (preview pixels per camera pixel).
        public init(onImage: @escaping @Sendable (CGImage, Double) -> Void) {
            self.onImage = onImage
        }

        /// Only renders while the calibration panel is showing.
        public var isEnabled: Bool {
            get { lock.withLock { enabled } }
            set { lock.withLock { enabled = newValue } }
        }

        /// Offers a camera frame; most are skipped. `wait` renders synchronously, for tests.
        public func offer(_ image: CIImage, at date: Date, wait: Bool = false) {
            let take = lock.withLock { () -> Bool in
                guard enabled, !busy else { return false }
                if let lastRender, date.timeIntervalSince(lastRender) < Self.interval - 0.001 { return false }
                lastRender = date
                busy = true
                return true
            }
            guard take else { return }
            let work = { [self] in
                defer { lock.withLock { busy = false } }
                let scale = Self.width / image.extent.width
                let small = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
                guard let picture = context.createCGImage(small, from: small.extent.integral) else { return }
                onImage(picture, scale)
            }
            if wait { queue.sync(execute: work) } else { queue.async(execute: work) }
        }
    }
#endif
