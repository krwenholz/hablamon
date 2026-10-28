/// The text found on one snapshot of the screen and its English: game terms immediately from the
/// official names, everything else as machine translation arrives.
public struct ScreenTranslation: Equatable, Sendable {
    public private(set) var blocks: [TextBlock]
    private var english: [Int: String] = [:]

    public init(blocks: [TextBlock], terms: GameTerms) {
        self.blocks = blocks
        for block in blocks {
            if let term = terms.english(for: block.text) { english[block.id] = term }
        }
    }

    public func english(for id: Int) -> String? {
        english[id]
    }

    /// Blocks still waiting for machine translation, top to bottom.
    public var pending: [TextBlock] {
        blocks.filter { english[$0.id] == nil }
    }

    public var isComplete: Bool { pending.isEmpty }

    public mutating func translated(id: Int, english text: String) {
        english[id] = text
    }

    public static func == (lhs: ScreenTranslation, rhs: ScreenTranslation) -> Bool {
        lhs.blocks == rhs.blocks && lhs.english == rhs.english
    }
}
