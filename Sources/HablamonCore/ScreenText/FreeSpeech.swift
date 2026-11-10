/// Speech read straight off a frame's text: cutscene subtitles along the bottom, speech bubbles
/// over characters in the overworld, boxes the box detector doesn't know (Casiopea's dark calls),
/// and, when asked, the dialogue box itself, whatever its colours.
public struct FreeSpeech: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case subtitle, bubble, dialogue
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
    /// of the frame under a box. Never the top band (quest banners) or the upper right
    /// (notifications such as "¡La Pokédex se ha actualizado!"). With `dialogue`, any finished line
    /// in the lower part of the screen, inside the dialogue box's span, is dialogue, so a box of any
    /// colour is read without detecting the box. Otherwise only full sentences count, either low and
    /// centered (subtitles) or on a light background (bubbles); dark notifications on the right and
    /// menu labels don't qualify.
    public static func find(in blocks: [TextBlock], dialogue: Bool = false, brightness: (NormalizedRect) -> Double)
        -> [FreeSpeech]
    {
        blocks.compactMap { block in
            guard block.box.y >= 0.15, !isNotification(block.box) else { return nil }
            if dialogue, isDialogue(block) {
                return FreeSpeech(text: block.text, speaker: name(above: block, in: blocks), kind: .dialogue)
            }
            guard isSentence(block.text) else { return nil }
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

    /// The game's notification cards start about 73 % across the upper right (nearer 70 % with
    /// corners on the TV's bezel); speech bubbles there start further left.
    static func isNotification(_ box: NormalizedRect) -> Bool {
        box.x >= 0.68 && box.y + box.height <= 0.5
    }

    /// A finished line low on the screen within the dialogue box's span (about 25–75 % across). A
    /// line still typing out usually stops mid-word, without its closing punctuation.
    static func isDialogue(_ block: TextBlock) -> Bool {
        let words = block.text.split(separator: " ").filter { $0.contains(where: \.isLetter) }
        guard !words.isEmpty, let last = block.text.last(where: { !"\"»”)".contains($0) }), ".!?…".contains(last)
        else { return false }
        return block.box.y >= 0.6 && block.box.x >= 0.15 && block.box.x + block.box.width <= 0.85
    }

    static func isSentence(_ text: String) -> Bool {
        let words = text.split(separator: " ").filter { $0.contains(where: \.isLetter) }
        guard words.count >= 3, let last = text.last(where: { !"\"»”)".contains($0) }) else { return false }
        return ".!?…".contains(last)
    }

    /// One or two capitalized words sitting just above and overlapping the block, like a name tag.
    static func name(above block: TextBlock, in blocks: [TextBlock]) -> String? {
        blocks.first { other in
            let gap = block.box.y - (other.box.y + other.box.height)
            let words = other.text.split(separator: " ")
            return other.id != block.id && gap >= -0.01 && gap < block.box.height && (1...2).contains(words.count)
                && other.text.first?.isUppercase == true && other.box.x < block.box.x + block.box.width
                && other.box.x + other.box.width > block.box.x
        }?.text
    }
}

/// Decides when on-screen speech should be spoken: once two checks in a row read the same text (one
/// sighting can be a misread mid-animation, and a line still typing out reads longer each time),
/// and not again until it has left the screen.
public struct FreeSpeechTracker: Sendable {
    /// Seconds a line must be gone before it can be spoken again.
    public static let forgetAfter = 3.0
    /// Two reads at least this alike are the same line on screen…
    static let sameLine = 0.85
    /// …and at least this alike, the same text: done typing, give or take an OCR slip.
    static let sameText = 0.95

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
            if recentDialogue.contains(where: { similarity($0, key) >= Self.sameLine }) { continue }
            if let index = seen.firstIndex(where: { similarity($0.key, key) >= Self.sameLine }) {
                let settled = similarity(seen[index].key, key) >= Self.sameText
                seen[index].lastSeen = time
                seen[index].key = key
                if settled, !seen[index].spoken {
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
