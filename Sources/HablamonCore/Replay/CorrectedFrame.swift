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
        /// Whether a box missed where the profile has it is looked for on the panel as shown.
        let alignsToPanel: Bool
        /// The regions this frame is read with, once `boxFeatures` has chosen them.
        private var chosen: GameProfile?

        /// `image` must already be corrected to the profile's frame size, with its origin at zero.
        /// `alignsToPanel` suits corners that don't sit exactly on the picture's edge, as the phone's
        /// often do; with exact corners, as in the Mac's fixtures, switching regions between frames
        /// confuses the settle detector, so it's off by default.
        public init(image: CIImage, context: CIContext, recognizer: VisionTextRecognizer, alignsToPanel: Bool = false) {
            self.image = image
            self.context = context
            self.recognizer = recognizer
            self.alignsToPanel = alignsToPanel
        }

        /// Measures the box where the profile has it. When that finds no box, measures it again
        /// on the dialogue panel as this frame shows it (`PanelLocator`): corners placed on the TV's
        /// bezel, or a TV that overscans, move the box from where the profile expects it. Frames
        /// read fine with the profile's regions are read exactly as before.
        public func boxFeatures(_ profile: GameProfile) throws -> BoxFeatures {
            chosen = profile
            let fixed = try features(profile)
            guard alignsToPanel, !fixed.isBoxVisible(profile.detection), let panel = try locatePanel(profile) else {
                return fixed
            }
            var moved = profile
            moved.regions = panel.regions
            bodyCache = nil
            let aligned = try features(moved, panelBlankFraction: panel.blankFraction)
            guard aligned.isBoxVisible(profile.detection) else {
                bodyCache = nil
                return fixed
            }
            chosen = moved
            return aligned
        }

        public func settleCrop(_ profile: GameProfile) throws -> GrayImage {
            try body(chosen ?? profile).gray.downscaled(width: 160, height: 40)
        }

        public func readBody(_ profile: GameProfile) throws -> [RecognizedLine] {
            let profile = chosen ?? profile
            return try recognizer.recognize(try cgImage(profile.regions.bodyText, profile, scale: 2))
        }

        public func readNameTag(_ profile: GameProfile) throws -> [RecognizedLine] {
            let profile = chosen ?? profile
            return try recognizer.recognize(try cgImage(profile.regions.nameTag, profile, scale: 3))
        }

        private func features(_ profile: GameProfile, panelBlankFraction: Double? = nil) throws -> BoxFeatures {
            let regions = profile.regions
            let top = regions.textLines.y - regions.bodyText.y
            return BoxFeatures(
                body: try body(profile),
                textRows: top..<(top + regions.textLines.height),
                nameTag: try rgba(regions.nameTag, profile),
                detection: profile.detection,
                panelBlankFraction: panelBlankFraction
            )
        }

        /// The profile's regions moved onto the dialogue panel this frame shows, and how much of
        /// the panel is blank rows; nil when no panel-sized band is near where the box should be.
        func locatePanel(_ profile: GameProfile) throws -> (regions: ProfileRegions, blankFraction: Double)? {
            let box = profile.regions.dialogueBox
            let top = max(0, box.y - box.height / 2)
            let band = PixelRect(
                x: box.x + box.width / 5, y: top, width: box.width * 3 / 5, height: profile.frameSize.height - top)
            let image = try rgba(band, profile)
            let medians = (0..<image.height).map { y in
                let row = (0..<image.width).map { image.luminance(x: $0, y: y) }.sorted()
                return row[row.count / 2]
            }
            guard let panel = PanelLocator.locate(rowMedians: medians, firstRow: band.y, expected: box) else {
                return nil
            }
            let rows = (panel.top - band.y + 1)..<(panel.top - band.y + panel.height)
            let blank = rows.filter { y in
                let edges = (0..<image.width).filter { x in
                    abs(image.luminance(x: x, y: y) - image.luminance(x: x, y: y - 1)) > profile.detection.edgeStep
                }
                return Double(edges.count) / Double(image.width) < PanelLocator.blankRowEdges
            }
            let regions = profile.regions.aligned(
                boxTop: panel.top, boxHeight: panel.height, frameHeight: profile.frameSize.height)
            return (regions, Double(blank.count) / Double(max(1, rows.count)))
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
