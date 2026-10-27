import HablamonModels

extension Quad {
    var corners: [Point] { [topLeft, topRight, bottomRight, bottomLeft] }

    /// Shoelace area in square pixels.
    public var area: Double {
        let points = corners
        var sum = 0.0
        for index in points.indices {
            let a = points[index]
            let b = points[(index + 1) % points.count]
            sum += a.x * b.y - b.x * a.y
        }
        return abs(sum) / 2
    }

    /// Mean width over mean height, so a TV seen at an angle still reads close to 16:9.
    public var aspect: Double {
        let width = (topLeft.distance(to: topRight) + bottomLeft.distance(to: bottomRight)) / 2
        let height = (topLeft.distance(to: bottomLeft) + topRight.distance(to: bottomRight)) / 2
        return height == 0 ? 0 : width / height
    }

    public var center: Point {
        let points = corners
        return Point(x: points.map(\.x).reduce(0, +) / 4, y: points.map(\.y).reduce(0, +) / 4)
    }

    /// Mean distance between matching corners.
    public func distance(to other: Quad) -> Double {
        zip(corners, other.corners).map { $0.distance(to: $1) }.reduce(0, +) / 4
    }
}

extension Point {
    func distance(to other: Point) -> Double {
        ((x - other.x) * (x - other.x) + (y - other.y) * (y - other.y)).squareRoot()
    }
}

/// Chooses the TV screen among rectangle candidates: roughly widescreen, not tiny, and nearest
/// the last known screen if there is one (picture frames and windows are rectangles too).
public enum QuadPicker {
    public static let aspectRange = 1.45...2.1
    public static let minimumAreaFraction = 0.05

    public static func pick(_ candidates: [Quad], near previous: Quad?, frameArea: Double) -> Quad? {
        let plausible = candidates.filter {
            aspectRange.contains($0.aspect) && $0.area >= frameArea * minimumAreaFraction
        }
        if let previous { return plausible.min { $0.distance(to: previous) < $1.distance(to: previous) } }
        return plausible.max { $0.area < $1.area }
    }
}
