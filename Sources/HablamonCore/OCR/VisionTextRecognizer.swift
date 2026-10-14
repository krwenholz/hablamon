#if canImport(Vision)
    import CoreGraphics
    import Foundation
    import ImageIO
    import Vision

    /// On-device OCR with Apple's Vision framework, tuned for Spanish dialogue.
    public struct VisionTextRecognizer: Sendable {
        public enum Failure: Error, CustomStringConvertible {
            case unreadableImage(String)

            public var description: String {
                switch self {
                case .unreadableImage(let path): "could not read image at \(path)"
                }
            }
        }

        public var languages: [String]

        public init(languages: [String] = ["es-ES"]) {
            self.languages = languages
        }

        /// Recognizes text in an image file, honoring its EXIF orientation (iPhone photos are stored sideways).
        public func recognize(fileAt url: URL) throws -> [RecognizedLine] {
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
            else {
                throw Failure.unreadableImage(url.path)
            }
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any]
            let rawOrientation = (properties?[kCGImagePropertyOrientation as String] as? NSNumber)?.uint32Value ?? 1
            return try recognize(image, orientation: CGImagePropertyOrientation(rawValue: rawOrientation) ?? .up)
        }

        /// Lines are returned top to bottom, then left to right.
        public func recognize(_ image: CGImage, orientation: CGImagePropertyOrientation = .up) throws
            -> [RecognizedLine]
        {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.recognitionLanguages = languages
            request.usesLanguageCorrection = true
            let handler = VNImageRequestHandler(cgImage: image, orientation: orientation, options: [:])
            try handler.perform([request])
            let lines = (request.results ?? []).compactMap { observation -> RecognizedLine? in
                guard let candidate = observation.topCandidates(1).first else { return nil }
                let box = observation.boundingBox  // Vision's origin is bottom left.
                return RecognizedLine(
                    text: candidate.string,
                    confidence: Double(candidate.confidence),
                    box: NormalizedRect(x: box.minX, y: 1 - box.maxY, width: box.width, height: box.height)
                )
            }
            return lines.sorted { ($0.box.y, $0.box.x) < ($1.box.y, $1.box.x) }
        }
    }
#endif
