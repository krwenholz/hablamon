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

    /// How the app's screen is turned, as UIKit's interface orientation says.
    public enum ScreenOrientation: Sendable {
        case portrait, portraitUpsideDown, landscapeLeft, landscapeRight
    }

    /// The clockwise rotation in degrees that turns the back camera's frames upright for how the
    /// screen is turned, so the picture always matches what the player sees. Following the screen
    /// rather than the phone's tilt keeps the picture steady when the phone lies flat, where iOS
    /// can't tell how it's held. The sensor is upright with the screen in landscape right.
    public static func captureRotation(for orientation: ScreenOrientation) -> Double {
        switch orientation {
        case .landscapeRight: 0
        case .portrait: 90
        case .landscapeLeft: 180
        case .portraitUpsideDown: 270
        }
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

/// One of the camera screen's zoom buttons, as the physical lens and zoom factor that give it.
public struct PhoneZoom: Equatable, Sendable, Identifiable {
    /// Magnification relative to the main camera, as on the button.
    public var magnification: Double
    public var lensID: String
    /// The lens's own zoom factor (1 = none).
    public var zoom: Double

    public var id: Double { magnification }

    /// The buttons, as the Camera app offers them.
    public static let magnifications: [Double] = [0.5, 1, 2, 4]

    /// Magnifications worked out from fields of view are a little off (an ultra-wide comes out
    /// near 0.52), so a lens this close to a button still counts as fitting it.
    static let tolerance = 1.1

    public init(magnification: Double, lensID: String, zoom: Double) {
        self.magnification = magnification
        self.lensID = lensID
        self.zoom = zoom
    }

    /// "0.5×", "1×", "2×", "4×".
    public var name: String {
        magnification < 1 ? "0.5×" : "\(Int(magnification.rounded()))×"
    }

    /// The buttons this phone can offer; without an ultra-wide there's no 0.5×.
    public static func options(for lenses: [PhoneLens]) -> [PhoneZoom] {
        magnifications.compactMap { choose($0, from: lenses) }
    }

    /// The most magnifying lens that doesn't overshoot `magnification`, zoomed the rest of the
    /// way, since an optical lens is sharper than digital zoom on a wider one. Nil when every lens
    /// overshoots.
    public static func choose(_ magnification: Double, from lenses: [PhoneLens]) -> PhoneZoom? {
        let fitting = lenses.filter { $0.magnification > 0 && $0.magnification <= magnification * tolerance }
        guard let lens = fitting.max(by: { $0.magnification < $1.magnification }) else { return nil }
        // A physical lens can't zoom out past its own field of view.
        return PhoneZoom(
            magnification: magnification, lensID: lens.id, zoom: max(1, magnification / lens.magnification))
    }

    /// Whether the camera is set to this button now.
    public func matches(lensID: String?, zoom: Double) -> Bool {
        lensID == self.lensID && abs(zoom - self.zoom) < 0.05
    }
}
