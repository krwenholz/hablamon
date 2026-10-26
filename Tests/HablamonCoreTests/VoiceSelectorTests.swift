import HablamonModels
import Testing

@testable import HablamonCore

@Suite struct VoiceSelectorTests {
    let selector = VoiceSelector()
    let resolver: SpeakerResolver

    init() throws {
        resolver = SpeakerResolver(table: try BundledData.defaultCharacters())
    }

    @Test func hashIsStableAcrossRuns() {
        // Pinned values: a change here means every voice would shift.
        #expect(VoiceSelector.stableHash("") == 0xcbf2_9ce4_8422_2325)
        #expect(VoiceSelector.stableHash("a") == 0xaf63_dc4c_8601_ec8c)
    }

    @Test func sameSpeakerSameVoice() {
        let first = selector.plan(for: resolver.resolve(tag: "Mencía"))
        let misread = selector.plan(for: resolver.resolve(tag: "Mencia"))
        #expect(first == misread)
    }

    @Test func registerFollowsGender() {
        #expect(selector.plan(for: resolver.resolve(tag: "Clavel")).register == .male)
        #expect(selector.plan(for: resolver.resolve(tag: "Mencía")).register == .female)
    }

    @Test func ageShiftsPitch() {
        let child = selector.plan(for: resolver.resolve(tag: "Pola")).pitch  // Poppy
        let elder = selector.plan(for: resolver.resolve(tag: "Nevesio")).pitch
        #expect(child > 1.2)
        #expect(elder < 0.97)
    }

    @Test func similarCharactersDiffer() {
        // Both teen girls on the female register.
        let mencia = selector.plan(for: resolver.resolve(tag: "Mencía"))
        let noa = selector.plan(for: resolver.resolve(tag: "Noa"))
        #expect(mencia.pitch != noa.pitch)
    }

    @Test func explicitSettingsWin() {
        let speaker = Speaker(
            gender: .male, voices: VoiceAssignments(apple: AppleVoice(voice: "jorge", pitch: 0.7, rate: 0.9)))
        let plan = selector.plan(for: .known(name: "X", speaker: speaker))
        #expect(plan == VoicePlan(register: .male, voiceIdentifier: "jorge", pitch: 0.7, rate: 0.9))
        #expect(plan.summary == "jorge p0.70 r0.90")
    }

    @Test func pitchStaysInRange() {
        for tag in ["Vendedora", "Recepcionista", "Pescador", "Profesora", "Abuelita", "Chico", "Chica"] {
            let pitch = selector.plan(for: .unknown(tag: tag)).pitch
            #expect((0.5...2.0).contains(pitch))
        }
    }

    @Test func unknownSpeakersShareNeutralRegister() {
        let first = selector.plan(for: .unknown(tag: "Recepcionista"))
        let second = selector.plan(for: .unknown(tag: "Recluta"))
        let range =
            (VoiceSelector.neutralPitch - selector.spread * 1.5)...(VoiceSelector.neutralPitch + selector.spread * 1.5)
        #expect(first.register == .female)
        #expect(second.register == .female)
        #expect(range.contains(first.pitch))
        #expect(range.contains(second.pitch))
        #expect(first.pitch != second.pitch)
    }

    @Test func neutralCharacterUsesNeutralPitch() {
        let plan = selector.plan(for: .known(name: "Rotom", speaker: Speaker(gender: .neutral)))
        #expect(plan.register == .female)
        #expect(abs(plan.pitch - VoiceSelector.neutralPitch) <= selector.spread + 0.005)
    }
}
