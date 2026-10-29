import Foundation

/// Spanish text to the phonemes Kokoro reads, in the style of espeak-ng (which Kokoro was trained
/// on) with a Latin American accent: `c`/`z` sound like s and `ll` like y.
///
/// Spanish spelling is regular enough for rules: stress falls on the accented vowel, else the
/// second-to-last syllable for words ending in a vowel, n, or s, else the last; b, d, and g soften
/// between sounds; unstressed i and u next to another vowel glide.
public enum SpanishPhonemes {
    public static func phonemize(_ text: String) -> String {
        var output = ""
        // The last sound spoken in this phrase; punctuation starts a new phrase.
        var previous: Character?
        for token in tokens(spellingOutNumbers(text)) {
            switch token {
            case .word(let word):
                if !output.isEmpty && output.last != " " { output += " " }
                let phonemes = self.word(word, after: previous)
                output += phonemes
                previous = phonemes.last
            case .pause(let mark):
                while output.last == " " { output.removeLast() }
                output += mark
                previous = nil
            }
        }
        return output.trimmingCharacters(in: .whitespaces)
    }

    /// Splits a phoneme string into pieces of at most `maxLength` characters (what the model
    /// renders in one pass), in halves of about equal length: after punctuation near the middle
    /// if there is one, else at the space nearest the middle.
    public static func pieces(_ phonemes: String, maxLength: Int) -> [String] {
        let characters = Array(phonemes)
        guard characters.count > maxLength else { return phonemes.isEmpty ? [] : [phonemes] }
        let spaces = characters.indices.filter { characters[$0] == " " }
        let middle = Double(characters.count) / 2
        let nearMiddle = { (index: Int) in abs(Double(index) - middle) }
        let pauses = spaces.filter {
            $0 > 0 && ",.;:!?…".contains(characters[$0 - 1]) && nearMiddle($0) <= Double(characters.count) / 4
        }
        guard
            let cut = pauses.min(by: { nearMiddle($0) < nearMiddle($1) })
                ?? spaces.min(by: { nearMiddle($0) < nearMiddle($1) })
        else { return [phonemes] }
        return pieces(String(characters[..<cut]), maxLength: maxLength)
            + pieces(String(characters[(cut + 1)...]), maxLength: maxLength)
    }

    // MARK: Words

    /// Monosyllables Spanish leaves unstressed in a sentence (articles, clitics, short
    /// prepositions and conjunctions).
    private static let unstressed: Set<String> = [
        "a", "al", "de", "del", "el", "la", "las", "lo", "los", "le", "les", "me", "te", "se", "nos", "os",
        "mi", "mis", "tu", "tus", "su", "sus", "que", "y", "o", "u", "e", "ni", "en", "con", "por", "sin",
        "si", "un", "mas",
    ]

    private static let strong: Set<Character> = ["a", "e", "o", "á", "é", "í", "ó", "ú"]
    private static let vowels: Set<Character> = ["a", "e", "i", "o", "u", "á", "é", "í", "ó", "ú", "ü"]
    private static let accented: Set<Character> = ["á", "é", "í", "ó", "ú"]
    private static let frontVowels: Set<Character> = ["e", "i", "é", "í"]

    private static func word(_ word: String, after previous: Character?) -> String {
        let letters = Array(word.lowercased())
        let vowelAt = vowelPositions(letters)
        let groups = syllableNuclei(letters, vowelAt: vowelAt)
        let stressedGroup = stressedNucleus(word: word.lowercased(), letters: letters, groups: groups)
        let stressedLetter = stressedGroup.map { nucleusLetter(letters, group: groups[$0]) }
        let glides = Set(groups.flatMap { group in group.filter { $0 != nucleusLetter(letters, group: group) } })

        var output = ""
        var last = previous
        func emit(_ sound: String) {
            output += sound
            last = sound.last
        }
        var index = 0
        while index < letters.count {
            let letter = letters[index]
            let next = index + 1 < letters.count ? letters[index + 1] : nil
            let afterNext = index + 2 < letters.count ? letters[index + 2] : nil
            if vowelAt.contains(index) {
                if index == stressedLetter { output += "ˈ" }
                let plain = plainVowel(letter)
                if glides.contains(index) {
                    emit(plain == "i" ? "j" : plain == "u" ? "w" : plain)
                } else {
                    emit(plain)
                }
                index += 1
                continue
            }
            let phraseStart = last == nil
            switch letter {
            case "b", "v":
                emit(phraseStart || last == "m" || last == "n" ? "b" : "β")
            case "d":
                emit(phraseStart || last == "n" || last == "l" || index == letters.count - 1 ? "d" : "ð")
            case "g":
                if let next, frontVowels.contains(next) {
                    emit("x")
                } else {
                    emit(phraseStart || last == "n" || last == "ŋ" ? "ɡ" : "ɣ")
                    // "gue", "gui": the u is silent.
                    if next == "u", let afterNext, frontVowels.contains(afterNext) { index += 1 }
                }
            case "c":
                if next == "h" {
                    emit("ʧ")
                    index += 1
                } else {
                    emit(next.map { frontVowels.contains($0) } == true ? "s" : "k")
                }
            case "q":
                emit("k")
                if next == "u" { index += 1 }
            case "z", "s": emit("s")
            case "r":
                if next == "r" {
                    emit("r")
                    index += 1
                } else {
                    emit(index == 0 || last == "n" || last == "l" || last == "s" ? "r" : "ɾ")
                }
            case "l":
                if next == "l" {
                    emit("ʝ")
                    index += 1
                } else {
                    emit("l")
                }
            case "y": emit("ʝ")
            case "ñ": emit("ɲ")
            case "j": emit("x")
            case "h": break
            case "x": emit("ks")
            case "n":
                let velar = next.map { "gkqj".contains($0) || ($0 == "c" && !frontVowels.contains(afterNext ?? " ")) }
                emit(velar == true ? "ŋ" : "n")
            default:
                if letter.isLetter { emit(String(letter)) }
            }
            index += 1
        }
        return output
    }

    /// Letters that are vowels: the five (accented or not), and `y` at the end of a word after a
    /// vowel ("muy", "hoy") or on its own.
    private static func vowelPositions(_ letters: [Character]) -> Set<Int> {
        var positions = Set<Int>()
        for (index, letter) in letters.enumerated() where vowels.contains(letter) {
            // The u in "que", "qui", "gue", "gui" is silent.
            if letter == "u", index > 0, "qg".contains(letters[index - 1]), index + 1 < letters.count,
                frontVowels.contains(letters[index + 1])
            {
                continue
            }
            positions.insert(index)
        }
        if letters.last == "y", letters.count == 1 || positions.contains(letters.count - 2) {
            positions.insert(letters.count - 1)
        }
        return positions
    }

    /// Groups adjacent vowels into syllable nuclei: two strong vowels (a, e, o, or any accented
    /// vowel) are separate syllables; weak i and u join their neighbor.
    private static func syllableNuclei(_ letters: [Character], vowelAt: Set<Int>) -> [[Int]] {
        var groups: [[Int]] = []
        var previousVowel = -2
        for index in vowelAt.sorted() {
            let isStrong = strong.contains(letters[index])
            if index == previousVowel + 1, var group = groups.popLast() {
                let groupHasStrong = group.contains { strong.contains(letters[$0]) }
                if isStrong && groupHasStrong {
                    groups.append(group)
                    groups.append([index])
                } else {
                    group.append(index)
                    groups.append(group)
                }
            } else {
                groups.append([index])
            }
            previousVowel = index
        }
        return groups
    }

    private static func stressedNucleus(word: String, letters: [Character], groups: [[Int]]) -> Int? {
        if let marked = groups.firstIndex(where: { $0.contains { accented.contains(letters[$0]) } }) { return marked }
        guard !groups.isEmpty else { return nil }
        if groups.count == 1 { return unstressed.contains(word) ? nil : 0 }
        let last = letters.last.map { vowels.contains($0) || $0 == "n" || $0 == "s" } ?? false
        return last ? groups.count - 2 : groups.count - 1
    }

    /// The vowel a nucleus is built on: its strong vowel, else the second of two weak ones
    /// ("ciu", "cui"), unless that's a final y ("muy").
    private static func nucleusLetter(_ letters: [Character], group: [Int]) -> Int {
        if let strongest = group.first(where: { strong.contains(letters[$0]) }) { return strongest }
        if group.count > 1, letters[group[1]] != "y" { return group[1] }
        return group[0]
    }

    private static func plainVowel(_ letter: Character) -> String {
        switch letter {
        case "á": "a"
        case "é": "e"
        case "í", "y": "i"
        case "ó": "o"
        case "ú", "ü": "u"
        default: String(letter)
        }
    }

    // MARK: Text

    private enum Token {
        case word(String)
        case pause(String)
    }

    private static func tokens(_ text: String) -> [Token] {
        var tokens: [Token] = []
        var current = ""
        func flush() {
            if !current.isEmpty { tokens.append(.word(current)) }
            current = ""
        }
        let text = text.replacingOccurrences(of: "...", with: "…")
        for character in text {
            if character.isLetter {
                current.append(character)
            } else if ",.;:!?…".contains(character) {
                flush()
                tokens.append(.pause(String(character)))
            } else {
                flush()
            }
        }
        flush()
        return tokens
    }

    private static func spellingOutNumbers(_ text: String) -> String {
        guard text.contains(where: \.isNumber) else { return text }
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "es")
        formatter.numberStyle = .spellOut
        var output = ""
        var digits = ""
        func flush() {
            if let value = Int(digits), let words = formatter.string(from: NSNumber(value: value)) {
                output += words
            } else {
                output += digits
            }
            digits = ""
        }
        for character in text {
            if character.isASCII && character.isNumber {
                digits.append(character)
            } else {
                if !digits.isEmpty { flush() }
                output.append(character)
            }
        }
        if !digits.isEmpty { flush() }
        return output
    }
}
