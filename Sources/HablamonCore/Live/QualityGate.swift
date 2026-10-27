import HablamonModels

public struct QualityReport: Equatable, Sendable {
    /// Body-text cap height in camera pixels.
    public var textHeight: Double
    /// Fraction of the body crop that is blown out to white.
    public var clipped: Double
    /// Spanish, for the calibration panel.
    public var warnings: [String]
}

/// Judges whether the camera can read the text: big enough, and not overexposed.
public enum QualityGate {
    /// Cap height of body text in the game's 1280×720 frame.
    public static let capHeight = 18.0
    /// Spike A read text correctly at about 10 px; below this it gets unreliable.
    public static let minimumTextHeight = 8.0
    public static let maximumClipped = 0.05

    public static func report(quad: Quad, profile: GameProfile, bodyCrop: RGBAImage?) -> QualityReport {
        let screenHeight =
            (quad.topLeft.distance(to: quad.bottomLeft) + quad.topRight.distance(to: quad.bottomRight)) / 2
        let textHeight = capHeight * screenHeight / Double(profile.frameSize.height)
        var clipped = 0.0
        if let body = bodyCrop {
            var bright = 0
            for y in 0..<body.height {
                for x in 0..<body.width where body.luminance(x: x, y: y) >= 0.98 { bright += 1 }
            }
            clipped = Double(bright) / Double(body.width * body.height)
        }
        var warnings: [String] = []
        if textHeight < minimumTextHeight {
            warnings.append(
                "El texto mide \(Int(textHeight.rounded())) px en la cámara; acerca el móvil o sube el zoom.")
        }
        if clipped > maximumClipped {
            warnings.append(
                "La caja está sobreexpuesta (\(Int((clipped * 100).rounded())) %); baja el brillo o la exposición.")
        }
        return QualityReport(textHeight: textHeight, clipped: clipped, warnings: warnings)
    }
}
