import Foundation
import HablamonModels

/// The designed character voices bundled with the app (`Resources/voices`, made by
/// `scripts/design-voices.py`): one short reference clip per voice and what it says.
public struct VoiceLibrary: Sendable {
    public struct Clip: Sendable, Equatable {
        public var url: URL
        public var referenceText: String
    }

    private let clips: [String: Clip]

    init(clips: [String: Clip]) {
        self.clips = clips
    }

    public static func bundled() throws -> VoiceLibrary {
        guard let directory = Bundle.module.url(forResource: "voices", withExtension: nil) else {
            throw CocoaError(.fileNoSuchFile)
        }
        let text = try String(contentsOf: directory.appendingPathComponent("manifest.json"), encoding: .utf8)
        let manifest = try DocumentLoader.load(VoiceManifest.self, from: text)
        var clips: [String: Clip] = [:]
        for (name, voice) in manifest.voices where voice.engine == .qwen3 {
            let file = String(voice.referenceClip.dropFirst("voices/".count))
            clips[name] = Clip(url: directory.appendingPathComponent(file), referenceText: voice.referenceText ?? "")
        }
        return VoiceLibrary(clips: clips)
    }

    /// Voice names, matching character names in `characters.json` plus `generic-*`.
    public var names: Set<String> { Set(clips.keys) }

    public func clip(named name: String) -> Clip? {
        clips[name]
    }
}
