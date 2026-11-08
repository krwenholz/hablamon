import HablamonModels

/// Where the dialogue panel actually is in a corrected frame. Corners placed on the TV's bezel
/// rather than its picture, or a TV that overscans, shift and shrink the box from where the profile
/// expects it, and the box detector's blank-margin rows then land on the text. The panel is the
/// brightest band of rows around the expected box; each row's median brightness ignores the text.
public enum PanelLocator {
    /// Rows darker than the band's brightest by more than this aren't panel.
    static let brightnessDrop = 0.1
    /// Text lines and the panel's inner edge dip the median for a few rows; bridge gaps this short.
    static let maxGap = 10
    /// A band this much smaller or larger than the expected box isn't the box.
    static let heightRange = 0.6...1.3
    /// A panel row with fewer edges than this, as a fraction of its pixels, is blank.
    public static let blankRowEdges = 0.02

    /// `medians[i]` is the median luminance (0–1) of row `firstRow + i` across the panel's middle.
    /// Returns the panel's top row and height, or nil when no box-sized band sits near `expected`.
    public static func locate(rowMedians medians: [Double], firstRow: Int, expected: PixelRect)
        -> (top: Int, height: Int)?
    {
        let inBox = medians.indices.filter { (expected.y..<expected.y + expected.height).contains(firstRow + $0) }
        guard let peak = inBox.map({ medians[$0] }).max(), peak >= 0.6 else { return nil }
        let threshold = peak - brightnessDrop

        var bands: [Range<Int>] = []
        for (index, median) in medians.enumerated() where median >= threshold {
            if let last = bands.last, index - last.upperBound <= maxGap {
                bands[bands.count - 1] = last.lowerBound..<(index + 1)
            } else {
                bands.append(index..<(index + 1))
            }
        }
        let expectedCenter = Double(expected.y) + Double(expected.height) / 2
        let candidates = bands.filter { band in
            let ratio = Double(band.count) / Double(expected.height)
            let center = Double(firstRow + band.lowerBound) + Double(band.count) / 2
            return heightRange.contains(ratio) && abs(center - expectedCenter) <= Double(expected.height)
        }
        guard
            let best = candidates.min(by: { first, second in
                func distance(_ band: Range<Int>) -> Double {
                    abs(Double(firstRow + band.lowerBound) + Double(band.count) / 2 - expectedCenter)
                }
                return distance(first) < distance(second)
            })
        else { return nil }
        return (firstRow + best.lowerBound, best.count)
    }
}

extension ProfileRegions {
    /// The regions moved and scaled vertically so the dialogue box spans `boxTop..<boxTop + boxHeight`,
    /// kept inside a frame `frameHeight` rows tall.
    public func aligned(boxTop: Int, boxHeight: Int, frameHeight: Int) -> ProfileRegions {
        let scale = Double(boxHeight) / Double(dialogueBox.height)
        func map(_ rect: PixelRect) -> PixelRect {
            let top = Double(boxTop) + Double(rect.y - dialogueBox.y) * scale
            let y = min(max(0, Int(top.rounded())), frameHeight - 1)
            let height = min(max(1, Int((Double(rect.height) * scale).rounded())), frameHeight - y)
            return PixelRect(x: rect.x, y: y, width: rect.width, height: height)
        }
        return ProfileRegions(
            dialogueBox: map(dialogueBox), bodyText: map(bodyText), textLines: map(textLines),
            nameTag: map(nameTag), advanceIndicator: advanceIndicator.map(map))
    }
}
