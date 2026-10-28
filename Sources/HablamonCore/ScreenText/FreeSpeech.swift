/// Speech shown without a dialogue box: cutscene subtitles along the bottom, speech bubbles over
/// characters in the overworld, and boxes the box detector doesn't know (Casiopea's dark calls).
public struct FreeSpeech: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case subtitle, bubble
    }

    public var text: String
    /// A name shown just above, when there is one.
    public var speaker: String?
    public var kind: Kind

    public init(text: String, speaker: String?, kind: Kind) {
        self.text = text
        self.speaker = speaker
        self.kind = kind
    }

    /// The blocks on a frame that are someone speaking. `brightness` gives the mean luminance (0–1)
    /// of the frame under a box. Only full sentences count, never the top band (quest banners), and
    /// either low and centered (subtitles) or on a light background (bubbles); dark notifications on
    /// the right and menu labels don't qualify.
    public static func find(in blocks: [TextBlock], brightness: (NormalizedRect) -> Double) -> [FreeSpeech] {
        blocks.compactMap { block in
            guard isSentence(block.text), block.box.y >= 0.15 else { return nil }
            let center = block.box.x + block.box.width / 2
            let light = brightness(block.box)
            let kind: Kind
            if block.box.y >= 0.65 && abs(center - 0.5) < 0.12 {
                // Low and centered on white is the ordinary dialogue box, which the dialogue reader has.
                guard light < 0.8 else { return nil }
                kind = .subtitle
            } else if light >= 0.65 {
                kind = .bubble
            } else {
                return nil
            }
            return FreeSpeech(text: block.text, speaker: name(above: block, in: blocks), kind: kind)
        }
    }

    static func isSentence(_ text: String) -> Bool {
        let words = text.split(separator: " ").filter { $0.contains(where: \.isLetter) }
        guard words.count >= 3, let last = text.last(where: { !"\"»”)".contains($0) }) else { return false }
        return ".!?…".contains(last)
    }

    /// A single capitalized word sitting just above and overlapping the block, like a name tag.
    static func name(above block: TextBlock, in blocks: [TextBlock]) -> String? {
        blocks.first { other in
            let gap = block.box.y - (other.box.y + other.box.height)
            let words = other.text.split(separator: " ")
            return other.id != block.id && gap >= -0.01 && gap < block.box.height && words.count == 1
                && other.text.first?.isUppercase == true && other.box.x < block.box.x + block.box.width
                && other.box.x + other.box.width > block.box.x
        }?.text
    }
}

/// Decides when on-screen speech should be spoken: once it has been seen on two checks in a row
/// (one sighting can be a misread mid-animation), and not again until it has left the screen.
public struct FreeSpeechTracker: Sendable {
    /// Seconds a line must be gone before it can be spoken again.
    public static let forgetAfter = 3.0

    private var seen: [(key: String, firstSeen: Double, lastSeen: Double, spoken: Bool)] = []
    /// Recent lines read from dialogue boxes, so a box the detector missed for a moment isn't said twice.
    private var recentDialogue: [String] = []

    public init() {}

    /// Notes a line spoken from a dialogue box.
    public mutating func alreadySaid(_ text: String) {
        recentDialogue.append(DialogueText.matchKey(text))
        if recentDialogue.count > 10 { recentDialogue.removeFirst() }
    }

    public mutating func observe(_ speech: [FreeSpeech], at time: Double) -> [FreeSpeech] {
        seen.removeAll { time - $0.lastSeen > Self.forgetAfter }
        var ready: [FreeSpeech] = []
        for line in speech {
            let key = DialogueText.matchKey(line.text)
            if recentDialogue.contains(where: { similarity($0, key) >= 0.85 }) { continue }
            if let index = seen.firstIndex(where: { similarity($0.key, key) >= 0.85 }) {
                seen[index].lastSeen = time
                seen[index].key = key
                if !seen[index].spoken {
                    seen[index].spoken = true
                    ready.append(line)
                }
            } else {
                seen.append((key, time, time, false))
            }
        }
        return ready
    }
}
