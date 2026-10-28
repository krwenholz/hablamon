#if canImport(Vision)
    import CoreGraphics

    /// Reads all the Spanish on a whole game frame (menus, labels, descriptions, dialogue) as blocks.
    public struct ScreenReader: Sendable {
        let recognizer = VisionTextRecognizer()

        public init() {}

        public func read(_ image: CGImage) throws -> [TextBlock] {
            ScreenText.blocks(from: try recognizer.recognize(image))
        }
    }
#endif

#if canImport(CoreImage) && canImport(Vision)
    import CoreImage
    import HablamonModels

    extension ScreenReader {
        /// A picture of the room flattened to the TV screen, found with Vision. When the TV can't be
        /// found (glare along an edge can hide it), the whole picture is used.
        public static func flatten(_ image: CIImage, size: PixelSize = PixelSize(width: 1280, height: 720)) -> CIImage {
            let area = Double(image.extent.width * image.extent.height)
            guard let candidates = try? RectangleFinder().candidates(in: image),
                let quad = QuadPicker.pick(candidates, near: nil, frameArea: area),
                let flat = ScreenCorrector(quad: quad, size: size).correct(image)
            else { return image }
            return flat
        }
    }
#endif
