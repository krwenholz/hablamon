/// One line of text found by OCR.
public struct RecognizedLine: Sendable, Equatable {
    public var text: String
    /// 0–1, from the recognizer.
    public var confidence: Double
    /// Position in the image, normalized to 0–1 with the origin at the top left.
    public var box: NormalizedRect

    public init(text: String, confidence: Double, box: NormalizedRect) {
        self.text = text
        self.confidence = confidence
        self.box = box
    }
}

public struct NormalizedRect: Sendable, Equatable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}
