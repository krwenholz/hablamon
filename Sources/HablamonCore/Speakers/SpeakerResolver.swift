import HablamonModels

/// Who said a line, resolved from the OCR'd name tag.
public enum ResolvedSpeaker: Equatable, Sendable {
    /// No name tag: item pickups, system messages, unnamed NPCs.
    case narrator
    /// A character from the table; `name` is the table key even when an alias or a misread matched.
    case known(name: String, speaker: Speaker)
    /// A tag that matches nobody in the table.
    case unknown(tag: String)

    public var name: String {
        switch self {
        case .narrator: "narrator"
        case .known(let name, _): name
        case .unknown(let tag): tag
        }
    }
}

/// Maps name-tag text to a character, tolerating OCR misreads ("Clavei" → Clavel).
public struct SpeakerResolver: Sendable {
    private struct Candidate: Sendable {
        var key: String
        var name: String
        var speaker: Speaker
    }

    private let candidates: [Candidate]
    private let byKey: [String: Candidate]

    public init(table: CharacterTable) {
        var candidates: [Candidate] = []
        for (name, speaker) in table.characters where name != "narrator" {
            for tag in [name] + (speaker.aliases ?? []) {
                candidates.append(Candidate(key: DialogueText.matchKey(tag), name: name, speaker: speaker))
            }
        }
        self.candidates = candidates.sorted { $0.key < $1.key }
        self.byKey = Dictionary(candidates.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
    }

    public func resolve(tag: String?) -> ResolvedSpeaker {
        let cleaned = DialogueText.normalize(tag ?? "")
        let key = DialogueText.matchKey(cleaned)
        guard !key.isEmpty else { return .narrator }
        if let exact = byKey[key] {
            return .known(name: exact.name, speaker: exact.speaker)
        }
        let allowed = Self.allowedEdits(forLength: key.count)
        let scored = candidates.map { (candidate: $0, distance: editDistance(key, $0.key)) }
            .filter { $0.distance <= allowed }
            .sorted { $0.distance < $1.distance }
        // Only accept a single closest match; a tie between two characters is ambiguous.
        guard let best = scored.first,
            scored.dropFirst().first(where: { $0.distance == best.distance && $0.candidate.name != best.candidate.name }
            )
                == nil
        else {
            return .unknown(tag: cleaned)
        }
        return .known(name: best.candidate.name, speaker: best.candidate.speaker)
    }

    /// Short names get less slack: with two edits, "Levi" could become "Lima".
    static func allowedEdits(forLength length: Int) -> Int {
        switch length {
        case ..<3: 0
        case ..<6: 1
        default: 2
        }
    }
}
