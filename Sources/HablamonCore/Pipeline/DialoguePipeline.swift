import HablamonModels

/// One sampled, perspective-corrected frame. Implementations crop and OCR lazily, so the
/// pipeline only pays for OCR on settled pages.
public protocol DialogueFrame {
    func boxFeatures(_ profile: GameProfile) throws -> BoxFeatures
    /// The body-text crop, downscaled for the settle detector.
    func settleCrop(_ profile: GameProfile) throws -> GrayImage
    func readBody(_ profile: GameProfile) throws -> [RecognizedLine]
    func readNameTag(_ profile: GameProfile) throws -> [RecognizedLine]
}

/// A page to speak and log.
public struct SpokenPage: Equatable, Sendable {
    /// Seconds since the start of the session or video.
    public var time: Double
    public var speaker: ResolvedSpeaker
    /// Name-tag text as OCR read it, or nil for narration.
    public var speakerRaw: String?
    public var text: String
    public var confidence: OCRConfidence
    public var voice: VoicePlan
}

public enum PipelineEvent: Equatable, Sendable {
    case dialogueStarted
    case dialogueEnded
    /// The player advanced; interrupt speech for the old page.
    case pageChanged
    case speak(SpokenPage)
}

/// Turns sampled frames into pages to speak: box detection, settle, OCR, scroll handling,
/// speaker resolution, and voice choice. Platform-neutral; frames supply the pixels and OCR.
public struct DialoguePipeline {
    public let profile: GameProfile
    private var resolver: SpeakerResolver
    private let voices: VoiceSelector
    private var presence: DialoguePresence
    private var settle: SettleDetector
    private var pages = PageSequencer()

    public init(
        profile: GameProfile,
        characters: CharacterTable,
        settle: SettleDetector.Configuration = .init(),
        voices: VoiceSelector = .init()
    ) {
        self.profile = profile
        self.resolver = SpeakerResolver(table: characters)
        self.voices = voices
        self.presence = DialoguePresence()
        self.settle = SettleDetector(configuration: settle)
    }

    public var isInDialogue: Bool { presence.isActive }

    public mutating func process(_ frame: some DialogueFrame, at time: Double) throws -> [PipelineEvent] {
        let features = try frame.boxFeatures(profile)
        let visible = features.isBoxVisible(profile.detection)
        var events: [PipelineEvent] = []

        switch presence.observe(boxVisible: visible, at: time) {
        case .entered:
            events.append(.dialogueStarted)
        case .exited:
            settle.reset()
            pages.reset()
            events.append(.dialogueEnded)
        case nil:
            break
        }
        guard presence.isActive, visible else { return events }

        switch settle.observe(try frame.settleCrop(profile)) {
        case .pageChanged:
            events.append(.pageChanged)
        case .settled:
            if let page = try read(frame, features: features, at: time) { events.append(.speak(page)) }
        case nil:
            break
        }
        return events
    }

    /// Uses a new character table from the next page on, as when the player tags a speaker.
    public mutating func updateCharacters(_ table: CharacterTable) {
        resolver = SpeakerResolver(table: table)
    }

    /// Forgets the current box, as when the camera stops watching mid-dialogue.
    public mutating func reset() {
        presence = DialoguePresence(requiredPositives: presence.requiredPositives, exitDelay: presence.exitDelay)
        settle.reset()
        pages.reset()
    }

    private mutating func read(_ frame: some DialogueFrame, features: BoxFeatures, at time: Double) throws
        -> SpokenPage?
    {
        let body = try frame.readBody(profile)
        guard let text = pages.next(lines: body.map(\.text)) else { return nil }
        var tag: String?
        if features.hasNameTag(profile.detection) {
            let tagText = DialogueText.normalize(lines: try frame.readNameTag(profile).map(\.text))
            tag = tagText.isEmpty ? nil : tagText
        }
        let speaker = resolver.resolve(tag: tag)
        let confidences = body.map(\.confidence)
        return SpokenPage(
            time: time,
            speaker: speaker,
            speakerRaw: tag,
            text: text,
            confidence: OCRConfidence(
                mean: confidences.reduce(0, +) / Double(max(1, confidences.count)),
                min: confidences.min() ?? 0
            ),
            voice: voices.plan(for: speaker)
        )
    }
}
