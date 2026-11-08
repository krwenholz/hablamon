/// The text found on one snapshot of the screen and its English: game terms immediately from the
/// official names, everything else as machine translation arrives.
public struct ScreenTranslation: Equatable, Sendable {
    public private(set) var blocks: [TextBlock]
    private var english: [Int: String] = [:]
    /// Machine translation can't run (no language pack, or no Translation at all, as in the iOS
    /// Simulator), so the blocks without a game term stay in Spanish instead of waiting forever.
    public private(set) var unavailable = false

    public init(blocks: [TextBlock], terms: GameTerms) {
        self.blocks = blocks
        for block in blocks {
            if let term = terms.english(for: block.text) { english[block.id] = term }
        }
    }

    public func english(for id: Int) -> String? {
        english[id]
    }

    /// Blocks still waiting for machine translation, top to bottom; none once it's unavailable.
    public var pending: [TextBlock] {
        unavailable ? [] : untranslated
    }

    /// Blocks with no English, whether still waiting or given up on.
    public var untranslated: [TextBlock] {
        blocks.filter { english[$0.id] == nil }
    }

    /// Nothing more is coming: every block has its English, or the rest can't be translated.
    public var isComplete: Bool { pending.isEmpty }

    public mutating func translated(id: Int, english text: String) {
        english[id] = text
    }

    public mutating func translationUnavailable() {
        unavailable = true
    }

    public static func == (lhs: ScreenTranslation, rhs: ScreenTranslation) -> Bool {
        lhs.blocks == rhs.blocks && lhs.english == rhs.english && lhs.unavailable == rhs.unavailable
    }
}
