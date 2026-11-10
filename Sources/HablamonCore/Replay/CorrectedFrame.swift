#if canImport(CoreImage) && canImport(Vision)
    import CoreGraphics
    import CoreImage
    import CoreImage.CIFilterBuiltins
    import HablamonModels

    /// Flattens camera frames into the profile's canonical frame, using the calibrated screen quad.
    public struct ScreenCorrector {
        public let quad: Quad
        public let size: PixelSize

        public init(quad: Quad, size: PixelSize) {
            self.quad = quad
            self.size = size
        }

        /// `quad` is in top-left pixel coordinates; Core Image's origin is the bottom left.
        public func correct(_ image: CIImage) -> CIImage? {
            let extent = image.extent
            func point(_ p: Point) -> CGPoint {
                CGPoint(x: extent.minX + p.x, y: extent.minY + extent.height - p.y)
            }
            let filter = CIFilter.perspectiveCorrection()
            filter.inputImage = image
            filter.topLeft = point(quad.topLeft)
            filter.topRight = point(quad.topRight)
            filter.bottomRight = point(quad.bottomRight)
            filter.bottomLeft = point(quad.bottomLeft)
            filter.crop = true
            guard let output = filter.outputImage, !output.extent.isInfinite, output.extent.width > 0 else {
                return nil
            }
            let origin = output.transformed(
                by: CGAffineTransform(translationX: -output.extent.minX, y: -output.extent.minY)
            )
            return origin.transformed(
                by: CGAffineTransform(
                    scaleX: CGFloat(size.width) / origin.extent.width,
                    y: CGFloat(size.height) / origin.extent.height
                )
            )
        }
    }

    /// A perspective-corrected frame that crops and OCRs on demand.
    public final class CorrectedFrame: DialogueFrame {
        public enum Failure: Error {
            case renderFailed
        }

        let image: CIImage
        let context: CIContext
        let recognizer: VisionTextRecognizer
        private var bodyCache: RGBAImage?

        /// `image` must already be corrected to the profile's frame size, with its origin at zero.
        public init(image: CIImage, context: CIContext, recognizer: VisionTextRecognizer) {
            self.image = image
            self.context = context
            self.recognizer = recognizer
        }

        public func boxFeatures(_ profile: GameProfile) throws -> BoxFeatures {
            let regions = profile.regions
            let top = regions.textLines.y - regions.bodyText.y
            return BoxFeatures(
                body: try body(profile),
                textRows: top..<(top + regions.textLines.height),
                nameTag: try rgba(regions.nameTag, profile),
                detection: profile.detection
            )
        }

        public func settleCrop(_ profile: GameProfile) throws -> GrayImage {
            try body(profile).gray.downscaled(width: 160, height: 40)
        }

        public func readBody(_ profile: GameProfile) throws -> [RecognizedLine] {
            try recognizer.recognize(try cgImage(profile.regions.bodyText, profile, scale: 2))
        }

        public func readNameTag(_ profile: GameProfile) throws -> [RecognizedLine] {
            try recognizer.recognize(try cgImage(profile.regions.nameTag, profile, scale: 3))
        }

        private func body(_ profile: GameProfile) throws -> RGBAImage {
            if let bodyCache { return bodyCache }
            let rendered = try rgba(profile.regions.bodyText, profile)
            bodyCache = rendered
            return rendered
        }

        /// Crops a region given in top-left frame coordinates, optionally upscaled for OCR.
        func cgImage(_ region: PixelRect, _ profile: GameProfile, scale: CGFloat = 1) throws -> CGImage {
            let flippedY = profile.frameSize.height - region.y - region.height
            var cropped = image.cropped(
                to: CGRect(x: region.x, y: flippedY, width: region.width, height: region.height)
            )
            cropped = cropped.transformed(
                by: CGAffineTransform(translationX: -cropped.extent.minX, y: -cropped.extent.minY)
            )
            if scale != 1 {
                let filter = CIFilter.lanczosScaleTransform()
                filter.inputImage = cropped
                filter.scale = Float(scale)
                filter.aspectRatio = 1
                cropped = filter.outputImage ?? cropped
            }
            let size = CGRect(
                x: 0,
                y: 0,
                width: (CGFloat(region.width) * scale).rounded(),
                height: (CGFloat(region.height) * scale).rounded()
            )
            guard let output = context.createCGImage(cropped, from: size) else { throw Failure.renderFailed }
            return output
        }

        /// Reads a region's pixels. Drawing into a bitmap context puts the top row first.
        func rgba(_ region: PixelRect, _ profile: GameProfile) throws -> RGBAImage {
            let picture = try cgImage(region, profile)
            var pixels = [UInt8](repeating: 0, count: region.width * region.height * 4)
            let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
                guard let space = CGColorSpace(name: CGColorSpace.sRGB),
                    let bitmap = CGContext(
                        data: buffer.baseAddress,
                        width: region.width,
                        height: region.height,
                        bitsPerComponent: 8,
                        bytesPerRow: region.width * 4,
                        space: space,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                    )
                else { return false }
                bitmap.draw(picture, in: CGRect(x: 0, y: 0, width: region.width, height: region.height))
                return true
            }
            guard drawn else { throw Failure.renderFailed }
            return RGBAImage(width: region.width, height: region.height, pixels: pixels)
        }
    }
#endif
