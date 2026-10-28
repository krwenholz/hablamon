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

#if canImport(CoreImage) && canImport(Vision)
    extension ScreenReader {
        /// Mean luminance (0–1) of `image` under a normalized, top-left-origin rectangle.
        public static func brightness(of rect: NormalizedRect, in image: CIImage, context: CIContext) -> Double {
            let extent = image.extent
            let area = CGRect(
                x: extent.minX + rect.x * extent.width, y: extent.minY + (1 - rect.y - rect.height) * extent.height,
                width: rect.width * extent.width, height: rect.height * extent.height)
            let average = image.cropped(to: area).applyingFilter(
                "CIAreaAverage", parameters: [kCIInputExtentKey: CIVector(cgRect: area)])
            var pixel = [UInt8](repeating: 0, count: 4)
            context.render(
                average, toBitmap: &pixel, rowBytes: 4, bounds: CGRect(x: 0, y: 0, width: 1, height: 1), format: .RGBA8,
                colorSpace: CGColorSpaceCreateDeviceRGB())
            return (0.299 * Double(pixel[0]) + 0.587 * Double(pixel[1]) + 0.114 * Double(pixel[2])) / 255
        }

        /// Speech shown without a dialogue box on a flattened frame.
        public func freeSpeech(in image: CIImage, context: CIContext) throws -> [FreeSpeech] {
            guard let picture = context.createCGImage(image, from: image.extent) else { return [] }
            let blocks = try read(picture)
            return FreeSpeech.find(in: blocks) { Self.brightness(of: $0, in: image, context: context) }
        }
    }
#endif
