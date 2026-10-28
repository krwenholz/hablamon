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
