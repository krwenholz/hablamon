import Foundation

/// A back camera of the iPhone, reduced to what choosing one needs.
public struct PhoneLens: Equatable, Sendable, Identifiable {
    public var id: String
    /// Magnification relative to the main (1×) camera.
    public var magnification: Double

    public init(id: String, magnification: Double) {
        self.id = id
        self.magnification = magnification
    }

    /// "0.5×", "1×", "3×", as the Camera app labels them.
    public var name: String {
        if magnification < 0.8 { return "0.5×" }
        return "\(Int(magnification.rounded()))×"
    }

    /// How much narrower a lens sees than the main camera, from their horizontal fields of view in
    /// degrees.
    public static func magnification(fieldOfView: Double, mainFieldOfView: Double) -> Double {
        guard fieldOfView > 0, fieldOfView < 180, mainFieldOfView > 0, mainFieldOfView < 180 else { return 1 }
        return tan(mainFieldOfView / 2 * .pi / 180) / tan(fieldOfView / 2 * .pi / 180)
    }

    /// A point in the upright frame (0–1, top-left origin) as the camera's point of interest, which
    /// is in the sensor's own landscape orientation. `rotation` is the clockwise angle in degrees
    /// that turns the sensor's picture upright (0, 90, 180, or 270).
    public static func sensorPoint(x: Double, y: Double, rotation: Double) -> (x: Double, y: Double) {
        switch Int((rotation.truncatingRemainder(dividingBy: 360) + 360).rounded()) % 360 {
        case 90: (y, 1 - x)
        case 180: (1 - x, 1 - y)
        case 270: (1 - y, x)
        default: (x, y)
        }
    }
}
