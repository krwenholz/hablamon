import HablamonModels

extension Quad {
    /// The quad scaled about its center, to take in the TV's frame and a little wall around it.
    public func expanded(by factor: Double) -> Quad {
        let middle = center
        func scale(_ point: Point) -> Point {
            Point(x: middle.x + (point.x - middle.x) * factor, y: middle.y + (point.y - middle.y) * factor)
        }
        return Quad(
            topLeft: scale(topLeft), topRight: scale(topRight), bottomRight: scale(bottomRight),
            bottomLeft: scale(bottomLeft))
    }
}

/// Tells whether the phone still sees the TV where it was calibrated, by comparing the ring around
/// the screen (TV frame and wall) with a reference thumbnail. The picture inside changes constantly,
/// so it's ignored; overall brightness is normalized so exposure drift doesn't count as a move.
public struct BezelMatcher: Sendable {
    /// Thumbnails are the screen quad expanded by this factor, corrected to `size`.
    public static let expansion = 1.15
    public static let size = (width: 128, height: 72)

    /// Mean absolute difference (0–1) above which the view no longer matches.
    public var threshold: Double

    public init(threshold: Double = 0.12) {
        self.threshold = threshold
    }

    public func matches(_ reference: GrayImage, _ current: GrayImage) -> Bool {
        difference(reference, current) <= threshold
    }

    public func difference(_ reference: GrayImage, _ current: GrayImage) -> Double {
        let a = Self.fit(reference)
        let b = Self.fit(current)
        let mask = Self.ringMask()
        let ring = mask.indices.filter { mask[$0] }
        guard !ring.isEmpty else { return 0 }
        let meanA = ring.map { Double(a.pixels[$0]) }.reduce(0, +) / Double(ring.count)
        let meanB = ring.map { Double(b.pixels[$0]) }.reduce(0, +) / Double(ring.count)
        let total = ring.map { abs((Double(a.pixels[$0]) - meanA) - (Double(b.pixels[$0]) - meanB)) }.reduce(0, +)
        return total / Double(ring.count) / 255
    }

    /// True for pixels outside the screen, which sits in the middle `1 / expansion` of the thumbnail.
    public static func ringMask() -> [Bool] {
        let (width, height) = size
        let insetX = Int((Double(width) * (1 - 1 / expansion) / 2).rounded())
        let insetY = Int((Double(height) * (1 - 1 / expansion) / 2).rounded())
        var mask = [Bool](repeating: false, count: width * height)
        for y in 0..<height {
            for x in 0..<width {
                mask[y * width + x] = x < insetX || x >= width - insetX || y < insetY || y >= height - insetY
            }
        }
        return mask
    }

    static func fit(_ image: GrayImage) -> GrayImage {
        if image.width == size.width && image.height == size.height { return image }
        return image.downscaled(width: size.width, height: size.height)
    }
}
