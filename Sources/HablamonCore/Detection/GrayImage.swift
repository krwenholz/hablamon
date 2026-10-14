/// An 8-bit grayscale image. Detection logic works on this rather than `CIImage`,
/// so it runs and tests on any platform; a thin adapter fills it from camera frames on macOS.
public struct GrayImage: Sendable, Equatable {
    public let width: Int
    public let height: Int
    /// Row-major luminance, `width * height` values.
    public var pixels: [UInt8]

    public init(width: Int, height: Int, pixels: [UInt8]) {
        precondition(width > 0 && height > 0 && pixels.count == width * height, "pixel count must match size")
        self.width = width
        self.height = height
        self.pixels = pixels
    }

    public init(width: Int, height: Int, fill: UInt8 = 0) {
        self.init(width: width, height: height, pixels: [UInt8](repeating: fill, count: width * height))
    }

    public subscript(x: Int, y: Int) -> UInt8 {
        get { pixels[y * width + x] }
        set { pixels[y * width + x] = newValue }
    }

    /// Box-filter downscale; each output pixel averages the source pixels it covers.
    public func downscaled(width newWidth: Int, height newHeight: Int) -> GrayImage {
        precondition(newWidth > 0 && newHeight > 0 && newWidth <= width && newHeight <= height)
        var output = [UInt8](repeating: 0, count: newWidth * newHeight)
        for outY in 0..<newHeight {
            let y0 = outY * height / newHeight
            let y1 = max(y0 + 1, (outY + 1) * height / newHeight)
            for outX in 0..<newWidth {
                let x0 = outX * width / newWidth
                let x1 = max(x0 + 1, (outX + 1) * width / newWidth)
                var sum = 0
                for y in y0..<y1 {
                    let row = y * width
                    for x in x0..<x1 { sum += Int(pixels[row + x]) }
                }
                output[outY * newWidth + outX] = UInt8(sum / ((y1 - y0) * (x1 - x0)))
            }
        }
        return GrayImage(width: newWidth, height: newHeight, pixels: output)
    }

    /// Fraction of pixels (0–1) whose value differs from `other` by more than `tolerance`.
    ///
    /// Counting changed pixels, rather than averaging the difference, keeps a few newly typed
    /// letters visible while sensor noise below `tolerance` counts as no change.
    public func changedFraction(from other: GrayImage, tolerance: UInt8 = 24) -> Double {
        precondition(width == other.width && height == other.height, "images must be the same size")
        var changed = 0
        for index in pixels.indices where abs(Int(pixels[index]) - Int(other.pixels[index])) > Int(tolerance) {
            changed += 1
        }
        return Double(changed) / Double(pixels.count)
    }
}
