/// A run of on-screen text that belongs together: a menu row, a label, or a wrapped paragraph.
public struct TextBlock: Equatable, Sendable, Identifiable {
    public var id: Int
    public var text: String
    /// Normalized to the frame, origin top left.
    public var box: NormalizedRect
}

/// Turns OCR lines from a whole game frame into blocks worth translating.
public enum ScreenText {
    /// A line only continues onto the next one if it's wide enough to have wrapped; short labels
    /// stacked in a menu stay separate.
    static let minimumWrappingWidth = 0.2
    static let minimumConfidence = 0.3

    public static func blocks(from lines: [RecognizedLine], excluding excluded: NormalizedRect? = nil) -> [TextBlock] {
        let kept = lines.filter { line in
            line.confidence >= minimumConfidence && isWords(line.text)
                && !(excluded.map { contains($0, center(of: line.box)) } ?? false)
        }
        .sorted { $0.box.y != $1.box.y ? $0.box.y < $1.box.y : $0.box.x < $1.box.x }

        var groups: [[RecognizedLine]] = []
        for line in kept {
            if let index = groups.lastIndex(where: { continues($0.last!, with: line) }) {
                groups[index].append(line)
            } else {
                groups.append([line])
            }
        }
        return groups.enumerated().map { index, group in
            TextBlock(
                id: index, text: DialogueText.normalize(lines: group.map(\.text)),
                box: group.map(\.box).dropFirst().reduce(group[0].box, union))
        }
    }

    /// `next` is the following line of the same paragraph as `last`.
    static func continues(_ last: RecognizedLine, with next: RecognizedLine) -> Bool {
        let gap = next.box.y - (last.box.y + last.box.height)
        let height = max(last.box.height, next.box.height)
        let overlap = min(last.box.x + last.box.width, next.box.x + next.box.width) - max(last.box.x, next.box.x)
        return last.box.width >= minimumWrappingWidth && gap < height * 0.6 && gap > -height * 0.5
            && abs(next.box.x - last.box.x) < height * 1.5 && overlap > 0
    }

    /// Real Spanish words: Latin letters only (scenery script often reads as Cyrillic or Greek),
    /// mostly letters rather than symbols, at least two of them, and not a short all-caps label
    /// like "PP" or "PS".
    static func isWords(_ text: String) -> Bool {
        let letters = text.filter(\.isLetter)
        guard letters.count >= 2, letters.unicodeScalars.allSatisfy({ $0.value < 0x0250 }) else { return false }
        let visible = text.filter { !$0.isWhitespace }.count
        guard Double(letters.count) / Double(visible) >= 0.6 else { return false }
        return !(letters.count <= 2 && letters.allSatisfy(\.isUppercase))
    }

    static func center(of rect: NormalizedRect) -> (x: Double, y: Double) {
        (rect.x + rect.width / 2, rect.y + rect.height / 2)
    }

    static func contains(_ rect: NormalizedRect, _ point: (x: Double, y: Double)) -> Bool {
        point.x >= rect.x && point.x <= rect.x + rect.width && point.y >= rect.y && point.y <= rect.y + rect.height
    }

    static func union(_ a: NormalizedRect, _ b: NormalizedRect) -> NormalizedRect {
        let x = min(a.x, b.x)
        let y = min(a.y, b.y)
        return NormalizedRect(
            x: x, y: y, width: max(a.x + a.width, b.x + b.width) - x, height: max(a.y + a.height, b.y + b.height) - y)
    }
}
