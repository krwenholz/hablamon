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

    public init(spread: Double = 0.08) {
        self.spread = spread
    }

    public func plan(for speaker: ResolvedSpeaker) -> VoicePlan {
        switch speaker {
        case .narrator:
            return VoicePlan(register: .female, voiceIdentifier: nil, pitch: 1.0, rate: 1.0)
        case .known(let name, let character):
            let apple = character.voices?.apple
            let register = Self.register(for: character.gender, name: name)
            let base = Self.basePitch(for: character.ageGroup, register: register)
            return VoicePlan(
                register: register,
                voiceIdentifier: apple?.voice,
                pitch: apple?.pitch ?? clamp(base + nudge(for: name)),
                rate: apple?.rate ?? 1.0
            )
        case .unknown(let tag):
            let register = Self.register(for: .unknown, name: tag)
            return VoicePlan(
                register: register,
                voiceIdentifier: nil,
                pitch: clamp(Self.basePitch(for: nil, register: register) + nudge(for: tag) * 1.5),
                rate: 1.0
            )
        }
    }

    static func register(for gender: Gender, name: String) -> VoicePlan.Register {
        switch gender {
        case .male: .male
        case .female, .neutral: .female
        // Unknown speakers alternate by name so a crowd of NPCs isn't all one voice.
        case .unknown: stableHash(DialogueText.matchKey(name)) % 2 == 0 ? .female : .male
        }
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
