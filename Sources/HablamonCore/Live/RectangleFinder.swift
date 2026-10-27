#if canImport(CoreImage) && canImport(Vision)
    import CoreGraphics
    import CoreImage
    import HablamonModels
    import Vision

    /// Proposes TV-screen outlines with Vision's rectangle detector, in top-left pixel coordinates.
    public struct RectangleFinder: Sendable {
        public init() {}

        public func candidates(in image: CIImage) throws -> [Quad] {
            let request = VNDetectRectanglesRequest()
            request.maximumObservations = 8
            // Vision's aspect ratio is short side over long side; 16:9 is 0.56.
            request.minimumAspectRatio = 0.4
            request.maximumAspectRatio = 0.8
            request.minimumSize = 0.2
            request.quadratureTolerance = 20
            try VNImageRequestHandler(ciImage: image).perform([request])
            let width = Double(image.extent.width)
            let height = Double(image.extent.height)
            func point(_ normalized: CGPoint) -> Point {
                Point(x: Double(normalized.x) * width, y: (1 - Double(normalized.y)) * height)
            }
            return (request.results ?? []).map {
                Quad(
                    topLeft: point($0.topLeft), topRight: point($0.topRight),
                    bottomRight: point($0.bottomRight), bottomLeft: point($0.bottomLeft))
            }
        }
    }

    /// Makes the grayscale thumbnail `BezelMatcher` compares: the screen quad expanded to take in
    /// the TV's frame, flattened to `BezelMatcher.size`.
    public enum BezelThumbnail {
        public enum Failure: Error {
            case renderFailed
        }

        public static func make(from image: CIImage, quad: Quad, context: CIContext) throws -> GrayImage {
            let size = BezelMatcher.size
            let corrector = ScreenCorrector(
                quad: quad.expanded(by: BezelMatcher.expansion), size: PixelSize(width: size.width, height: size.height)
            )
            guard let flat = corrector.correct(image),
                let picture = context.createCGImage(
                    flat, from: CGRect(x: 0, y: 0, width: size.width, height: size.height))
            else { throw Failure.renderFailed }
            var pixels = [UInt8](repeating: 0, count: size.width * size.height)
            let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
                guard
                    let bitmap = CGContext(
                        data: buffer.baseAddress, width: size.width, height: size.height, bitsPerComponent: 8,
                        bytesPerRow: size.width, space: CGColorSpaceCreateDeviceGray(),
                        bitmapInfo: CGImageAlphaInfo.none.rawValue)
                else { return false }
                bitmap.draw(picture, in: CGRect(x: 0, y: 0, width: size.width, height: size.height))
                return true
            }
            guard drawn else { throw Failure.renderFailed }
            return GrayImage(width: size.width, height: size.height, pixels: pixels)
        }
    }
#endif
