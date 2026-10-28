import Foundation
import HablamonModels

/// What the Apple engine should use for one speaker.
public struct VoicePlan: Equatable, Sendable {
    public enum Register: String, Sendable {
        case male
        case female
    }

    /// Which system voice family to use when no explicit voice identifier is set.
    public var register: Register
    /// Explicit `AVSpeechSynthesisVoice` identifier from the character table, if any.
    public var voiceIdentifier: String?
    public var pitch: Double
    public var rate: Double
    /// The designed voice clip to clone (a `voices/manifest.json` key), for engines that clone.
    public var clip: String? = nil

    /// Short form for the transcript's `voice` field, e.g. `es-ES female p1.12 r1.00`.
    public var summary: String {
        let voice = voiceIdentifier ?? "es-ES \(register.rawValue)"
        return "\(voice) p\(Self.format(pitch)) r\(Self.format(rate))"
    }

    static func format(_ value: Double) -> String {
        String(format: "%.2f", value)
    }
}

/// Picks consistent voice settings for each speaker.
///
/// Explicit table entries win. Otherwise gender and age group set the register and base pitch,
/// and a stable hash of the name nudges the pitch so two similar characters still sound different.
/// The same name always gets the same voice, across runs and machines.
public struct VoiceSelector: Sendable {
    /// Maximum pitch nudge either way for characters without an explicit pitch.
    public var spread: Double
    /// Names of the designed voice clips available; empty when no cloning engine is in use.
    public var clips: Set<String>
    /// Base pitch for neutral and unknown speakers. Apple's es-ES voices are male or female,
    /// so "neutral" is a slightly lowered female voice.
    public static let neutralPitch = 0.92

    public init(spread: Double = 0.08, clips: Set<String> = []) {
        self.spread = spread
        self.clips = clips
    }

    /// The character's own clip if it has one, otherwise a generic voice of the same gender and age.
    func clip(name: String?, gender: Gender, age: AgeGroup?) -> String? {
        if let name, clips.contains(name) { return name }
        let generic: String =
            switch (gender, age) {
            case (_, .child?): "generic-child"
            case (.female, .teen?): "generic-girl"
            case (.male, .teen?): "generic-boy"
            case (.female, .elder?): "generic-older-woman"
            case (.male, .elder?): "generic-older-man"
            case (.female, _): "generic-woman"
            case (.male, _): "generic-man"
            case (.neutral, _), (.unknown, _): "generic-neutral"
            }
        return clips.contains(generic) ? generic : nil
    }

    public func plan(for speaker: ResolvedSpeaker) -> VoicePlan {
        var plan = basePlan(for: speaker)
        plan.clip =
            switch speaker {
            case .narrator: clips.contains("narrator") ? "narrator" : clip(name: nil, gender: .female, age: .adult)
            case .known(let name, let character): clip(name: name, gender: character.gender, age: character.ageGroup)
            case .unknown: clip(name: nil, gender: .neutral, age: nil)
            }
        return plan
    }

    private func basePlan(for speaker: ResolvedSpeaker) -> VoicePlan {
        switch speaker {
        case .narrator:
            return VoicePlan(register: .female, voiceIdentifier: nil, pitch: 1.0, rate: 1.0)
        case .known(let name, let character):
            let apple = character.voices?.apple
            let register = Self.register(for: character.gender)
            let base =
                character.gender == .neutral && character.ageGroup == nil
                ? Self.neutralPitch : Self.basePitch(for: character.ageGroup, register: register)
            return VoicePlan(
                register: register,
                voiceIdentifier: apple?.voice,
                pitch: apple?.pitch ?? clamp(base + nudge(for: name)),
                rate: apple?.rate ?? 1.0
            )
        case .unknown(let tag):
            // One neutral voice for everyone not in the table, nudged by name so strangers differ.
            return VoicePlan(
                register: .female,
                voiceIdentifier: nil,
                pitch: clamp(Self.neutralPitch + nudge(for: tag) * 1.5),
                rate: 1.0
            )
        }
    }

    static func register(for gender: Gender) -> VoicePlan.Register {
        gender == .male ? .male : .female
    }

    static func basePitch(for age: AgeGroup?, register: VoicePlan.Register) -> Double {
        switch age {
        case .child: 1.3
        case .teen: register == .female ? 1.12 : 1.05
        case .elder: 0.88
        case .adult, nil: 1.0
        }
    }

    /// A value in -spread...spread determined only by the name.
    func nudge(for name: String) -> Double {
        let unit = Double(Self.stableHash(DialogueText.matchKey(name)) % 1001) / 1000  // 0...1
        return (unit * 2 - 1) * spread
    }

    func clamp(_ pitch: Double) -> Double {
        min(2.0, max(0.5, (pitch * 100).rounded() / 100))
    }

    /// FNV-1a, 64-bit. Unlike Swift's `Hasher`, it gives the same value on every launch.
    static func stableHash(_ text: String) -> UInt64 {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100_0000_01b3
        }
        return hash
    }
}
