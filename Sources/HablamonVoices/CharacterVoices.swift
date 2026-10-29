import HablamonCore

/// The state of a downloadable voice model, for the status strip.
public enum VoiceModelStatus: Equatable, Sendable {
    case notLoaded
    /// Downloading the model the first time (0–1).
    case downloading(Double)
    case loading
    case ready
    case failed(String)
}

/// An engine that speaks in each character's designed voice once its model has loaded, and hands
/// lines to the Apple voice until then.
public protocol CharacterVoiceEngine: SpeechEngine, AnyObject {
    /// Shown in the status strip, e.g. "Kokoro".
    var displayName: String { get }
    /// Called on any thread when the model's status changes.
    var onStatus: (@Sendable (VoiceModelStatus) -> Void)? { get set }
    /// Called with a line for the session log after each spoken line.
    var onLog: (@Sendable (String) -> Void)? { get set }
}
