/// Estimates which word is being spoken from how far playback has got, for engines that report no
/// word timings. Speech is roughly even across characters, so the fraction of audio played maps to
/// the same fraction of the text, snapped back to the start of that word.
public enum PlaybackProgress {
    /// A UTF-16 offset into `text` for `fraction` (0–1) of the audio played.
    public static func offset(fraction: Double, in text: String) -> Int {
        let units = Array(text.utf16)
        guard fraction > 0 else { return 0 }
        guard fraction < 1 else { return units.count }
        var index = Int((Double(units.count) * fraction).rounded(.down))
        // Back up to the start of the word the position falls in.
        while index > 0, !isSpace(units[index - 1]) { index -= 1 }
        return index
    }

    private static func isSpace(_ unit: UTF16.CodeUnit) -> Bool {
        unit == 0x20 || unit == 0x0A || unit == 0x09
    }
}

/// Limits how much audio a generative voice may produce for a line, so a model that keeps talking
/// can't run on. Spanish is spoken at roughly 12 characters a second; the cap is twice that plus two
/// seconds, in the model's 12-per-second codec frames.
public enum SpeechBudget {
    public static let framesPerSecond = 12

    public static func maxFrames(for text: String) -> Int {
        let expectedSeconds = Double(text.count) / 12
        return Int((expectedSeconds * 2 + 2) * Double(framesPerSecond))
    }
}

/// Splits a line into pieces a generative voice can start speaking sooner: sentences, with long
/// sentences broken at the comma nearest their middle, and tiny sentences ("¡Ah!") kept with the
/// next so they don't sound clipped.
public enum SpeechChunker {
    static let shortest = 20
    static let longest = 70

    public static func chunks(_ text: String) -> [String] {
        var sentences: [[Substring]] = [[]]
        for word in text.split(separator: " ") {
            sentences[sentences.count - 1].append(word)
            if endsSentence(word) { sentences.append([]) }
        }
        var merged: [String] = []
        var carry = ""
        for words in sentences where !words.isEmpty {
            let sentence = (carry.isEmpty ? "" : carry + " ") + words.joined(separator: " ")
            if sentence.count < shortest {
                carry = sentence
            } else {
                merged.append(sentence)
                carry = ""
            }
        }
        if !carry.isEmpty {
            if merged.isEmpty { merged.append(carry) } else { merged[merged.count - 1] += " " + carry }
        }
        return merged.flatMap(splitLong)
    }

    /// The UTF-16 offset where each chunk starts in `text`.
    public static func offsets(of chunks: [String], in text: String) -> [Int] {
        var offsets: [Int] = []
        var searchFrom = text.startIndex
        for chunk in chunks {
            if let range = text.range(of: chunk, range: searchFrom..<text.endIndex) {
                offsets.append(text.utf16.distance(from: text.startIndex, to: range.lowerBound))
                searchFrom = range.upperBound
            } else {
                offsets.append(offsets.last ?? 0)
            }
        }
        return offsets
    }

    static func endsSentence(_ word: Substring) -> Bool {
        guard let last = word.last(where: { !"\"»”)".contains($0) }) else { return false }
        return ".!?…".contains(last)
    }

    static func splitLong(_ sentence: String) -> [String] {
        guard sentence.count > longest else { return [sentence] }
        let words = sentence.split(separator: " ")
        let middle = sentence.count / 2
        var position = 0
        var best: (index: Int, distance: Int)?
        for (index, word) in words.enumerated().dropLast() {
            position += word.count + 1
            if word.hasSuffix(","), best.map({ abs(position - middle) < $0.distance }) ?? true {
                best = (index, abs(position - middle))
            }
        }
        guard let best else { return [sentence] }
        let first = words[...best.index].joined(separator: " ")
        let rest = words[(best.index + 1)...].joined(separator: " ")
        return [first] + splitLong(rest)
    }
}
