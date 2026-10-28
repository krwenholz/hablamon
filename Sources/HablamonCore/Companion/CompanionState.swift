import Foundation
import HablamonModels

/// The state word shown in the window's status pill.
public enum StatusPill: Equatable, Sendable, CaseIterable {
    case idle, reading, speaking, phoneInUse, findingTV, lostCamera, needsYou
}

public enum Light: Equatable, Sendable {
    case off, ok, working, bad
}

/// One light per pipeline stage, left to right in the status strip.
public struct Lights: Equatable, Sendable {
    public var camera: Light = .off
    public var tv: Light = .off
    public var box: Light = .off
    public var text: Light = .off
    public var voice: Light = .off

    public init() {}
}

public enum ConversationItem: Equatable, Sendable, Identifiable {
    case line(id: Int, page: SpokenPage)
    case gap(id: Int, reason: TranscriptGap.Reason, seconds: Double)

    public var id: Int {
        switch self {
        case .line(let id, _), .gap(let id, _, _): id
        }
    }
}

/// A name tag that matches nobody in the character table, with what they've said this session.
public struct UnknownSpeaker: Equatable, Sendable, Identifiable {
    /// `DialogueText.matchKey` of the tag, so OCR variants of one name group together.
    public var key: String
    /// The tag as first read.
    public var shownName: String
    public var lines: [SpokenPage]

    public var id: String { key }
}

public enum CompanionEvent: Sendable {
    case pipeline(PipelineEvent)
    /// A sampled frame; `screenFound` is whether the TV screen could be located in it.
    case frame(screenFound: Bool)
    case speechStarted
    case speechProgress(utf16Offset: Int)
    case speechFinished
    case connection(ConnectionMonitor.State)
    case gap(TranscriptGap.Reason, seconds: Double)
    /// The player chose a voice for this unknown speaker.
    case speakerTagged(key: String)
    /// An English translation of a line's text arrived.
    case translated(source: String, english: String)
}

/// Everything the companion window shows, updated one event at a time.
public struct CompanionState: Equatable, Sendable {
    public var current: SpokenPage?
    /// How much of `current.text` has been spoken, in UTF-16 units.
    public var spokenUTF16 = 0
    /// Earlier lines and gaps, newest last. The current line isn't repeated here.
    public var conversation: [ConversationItem] = []
    /// In first-seen order.
    public var unknownSpeakers: [UnknownSpeaker] = []
    public var lights = Lights()
    public var lastConfidence: Double?
    public var lineCount = 0
    /// Line texts waiting for an English translation, oldest first.
    public var pendingTranslation: [String] = []
    private var translations: [String: String] = [:]

    private var inDialogue = false
    private var speaking = false
    private var connection: ConnectionMonitor.State = .tracking
    private var nextID = 0

    public init() {}

    public func translation(of text: String) -> String? {
        translations[text]
    }

    public var pill: StatusPill {
        switch connection {
        case .paused: return .phoneInUse
        case .refinding: return .findingTV
        case .lost: return .lostCamera
        case .recalibrating: return .needsYou
        case .tracking: break
        }
        if speaking { return .speaking }
        return inDialogue ? .reading : .idle
    }

    public mutating func apply(_ event: CompanionEvent) {
        switch event {
        case .pipeline(.dialogueStarted):
            inDialogue = true
            lights.box = .ok
        case .pipeline(.dialogueEnded):
            inDialogue = false
            lights.box = .off
        case .pipeline(.pageChanged):
            lights.text = .working
        case .pipeline(.speak(let page)):
            if let current { conversation.append(.line(id: takeID(), page: current)) }
            current = page
            spokenUTF16 = 0
            lineCount += 1
            lastConfidence = page.confidence.mean
            lights.text = .ok
            if case .unknown(let tag) = page.speaker { noteUnknown(tag: tag, page: page) }
            if translations[page.text] == nil && !pendingTranslation.contains(page.text) {
                pendingTranslation.append(page.text)
            }
        case .frame(let screenFound):
            lights.camera = .ok
            lights.tv = screenFound ? .ok : .bad
        case .speechStarted:
            speaking = true
            lights.voice = .working
        case .speechProgress(let offset):
            spokenUTF16 = min(max(0, offset), current?.text.utf16.count ?? 0)
        case .speechFinished:
            speaking = false
            lights.voice = .ok
            spokenUTF16 = current?.text.utf16.count ?? 0
        case .connection(let state):
            connection = state
            switch state {
            case .tracking: break
            case .paused, .lost: lights.camera = .bad
            case .refinding, .recalibrating: lights.tv = .bad
            }
        case .gap(let reason, let seconds):
            conversation.append(.gap(id: takeID(), reason: reason, seconds: seconds))
        case .speakerTagged(let key):
            unknownSpeakers.removeAll { $0.key == key }
        case .translated(let source, let english):
            translations[source] = english
            pendingTranslation.removeAll { $0 == source }
        }
    }

    private mutating func noteUnknown(tag: String, page: SpokenPage) {
        let key = DialogueText.matchKey(tag)
        if let index = unknownSpeakers.firstIndex(where: { $0.key == key }) {
            unknownSpeakers[index].lines.append(page)
        } else {
            unknownSpeakers.append(UnknownSpeaker(key: key, shownName: tag, lines: [page]))
        }
    }

    private mutating func takeID() -> Int {
        nextID += 1
        return nextID
    }
}
