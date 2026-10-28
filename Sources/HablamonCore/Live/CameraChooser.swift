/// A camera the Mac can see, reduced to what choosing one needs.
public struct CameraInfo: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case continuity, builtIn, external
    }

    public var id: String
    public var name: String
    public var kind: Kind

    public init(id: String, name: String, kind: Kind) {
        self.id = id
        self.name = name
        self.kind = kind
    }
}

/// Which camera to watch the TV with: the iPhone (the normal setup) or the Mac's own camera,
/// for trying a placement without the phone.
public enum CameraSource: String, Sendable, CaseIterable {
    case iphone, mac
}

/// Picks the camera to watch the TV with. The built-in camera faces the player, so it's used only
/// when settings allow it; and once a camera is pinned, nothing else replaces it.
public enum CameraChooser {
    public static func choose(
        from cameras: [CameraInfo], source: CameraSource, pinned: String?, allowBuiltIn: Bool
    ) -> CameraInfo? {
        switch source {
        case .iphone: choose(from: cameras, pinned: pinned, allowBuiltIn: allowBuiltIn)
        case .mac: cameras.first { $0.id == pinned && $0.kind == .builtIn } ?? cameras.first { $0.kind == .builtIn }
        }
    }

    public static func choose(from cameras: [CameraInfo], pinned: String?, allowBuiltIn: Bool) -> CameraInfo? {
        if let pinned { return cameras.first { $0.id == pinned } }
        return cameras.first { $0.kind == .continuity } ?? cameras.first { $0.kind == .external }
            ?? (allowBuiltIn ? cameras.first { $0.kind == .builtIn } : nil)
    }
}
