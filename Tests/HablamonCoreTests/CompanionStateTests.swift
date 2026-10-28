import Foundation
import HablamonModels
import Testing

@testable import HablamonCore

func spokenPage(_ text: String, speaker: ResolvedSpeaker = .narrator, at time: Double = 0) -> SpokenPage {
    SpokenPage(
        time: time, speaker: speaker, speakerRaw: speaker == .narrator ? nil : speaker.name, text: text,
        confidence: OCRConfidence(mean: 0.5, min: 0.5),
        voice: VoicePlan(register: .female, voiceIdentifier: nil, pitch: 1, rate: 1))
}

@Suite struct CompanionStateTests {
    @Test func speakMovesPreviousLineIntoConversation() {
        var state = CompanionState()
        state.apply(.pipeline(.speak(spokenPage("Uno"))))
        state.apply(.pipeline(.speak(spokenPage("Dos"))))
        #expect(state.current?.text == "Dos")
        #expect(state.conversation.count == 1)
        if case .line(_, let page) = state.conversation.first {
            #expect(page.text == "Uno")
        } else {
            Issue.record("expected a line")
        }
        #expect(state.lineCount == 2)
    }

    @Test func pillFollowsPipeline() {
        var state = CompanionState()
        #expect(state.pill == .idle)
        state.apply(.pipeline(.dialogueStarted))
        #expect(state.pill == .reading)
        state.apply(.speechStarted)
        #expect(state.pill == .speaking)
        state.apply(.speechFinished)
        #expect(state.pill == .reading)
        state.apply(.pipeline(.dialogueEnded))
        #expect(state.pill == .idle)
    }

    @Test func connectionStatesMapToPills() {
        var state = CompanionState()
        state.apply(.pipeline(.dialogueStarted))
        state.apply(.connection(.paused))
        #expect(state.pill == .phoneInUse)
        state.apply(.connection(.refinding(since: Date())))
        #expect(state.pill == .findingTV)
        state.apply(.connection(.lost))
        #expect(state.pill == .lostCamera)
        state.apply(.connection(.recalibrating))
        #expect(state.pill == .needsYou)
        state.apply(.connection(.tracking))
        #expect(state.pill == .reading)
    }

    @Test func lightsTrackStages() {
        var state = CompanionState()
        #expect(state.lights == Lights())
        state.apply(.frame(screenFound: true))
        #expect(state.lights.camera == .ok)
        #expect(state.lights.tv == .ok)
        state.apply(.frame(screenFound: false))
        #expect(state.lights.tv == .bad)
        state.apply(.pipeline(.dialogueStarted))
        #expect(state.lights.box == .ok)
        state.apply(.pipeline(.speak(spokenPage("Hola"))))
        #expect(state.lights.text == .ok)
        state.apply(.speechStarted)
        #expect(state.lights.voice == .working)
        state.apply(.speechFinished)
        #expect(state.lights.voice == .ok)
        state.apply(.pipeline(.dialogueEnded))
        #expect(state.lights.box == .off)
    }

    @Test func gapAppearsInConversation() {
        var state = CompanionState()
        state.apply(.gap(.cameraPaused, seconds: 14))
        if case .gap(_, let reason, let seconds) = state.conversation.last {
            #expect(reason == .cameraPaused)
            #expect(seconds == 14)
        } else {
            Issue.record("expected a gap")
        }
    }

    @Test func unknownSpeakersGroupByMatchKey() {
        var state = CompanionState()
        state.apply(.pipeline(.speak(spokenPage("Uno", speaker: .unknown(tag: "Mencia")))))
        state.apply(.pipeline(.speak(spokenPage("Dos", speaker: .unknown(tag: "Mencía.")))))
        state.apply(.pipeline(.speak(spokenPage("Tres"))))
        #expect(state.unknownSpeakers.count == 1)
        #expect(state.unknownSpeakers.first?.lines.map(\.text) == ["Uno", "Dos"])
        #expect(state.unknownSpeakers.first?.shownName == "Mencia")
        let key = state.unknownSpeakers[0].key
        state.apply(.speakerTagged(key: key))
        #expect(state.unknownSpeakers.isEmpty)
    }

    @Test func progressClampsToText() {
        var state = CompanionState()
        state.apply(.pipeline(.speak(spokenPage("Hola"))))
        state.apply(.speechProgress(utf16Offset: 99))
        #expect(state.spokenUTF16 == 4)
        state.apply(.pipeline(.speak(spokenPage("Adiós"))))
        #expect(state.spokenUTF16 == 0)
    }

    @Test func confidenceTracksLastLine() {
        var state = CompanionState()
        state.apply(.pipeline(.speak(spokenPage("Hola"))))
        #expect(state.lastConfidence == 0.5)
    }

    @Test func translationsAttachToLinesByText() {
        var state = CompanionState()
        state.apply(.pipeline(.speak(spokenPage("Hola"))))
        #expect(state.pendingTranslation == ["Hola"])
        state.apply(.translated(source: "Hola", english: "Hello"))
        #expect(state.translation(of: "Hola") == "Hello")
        #expect(state.pendingTranslation.isEmpty)
        state.apply(.pipeline(.speak(spokenPage("Hola"))))
        #expect(state.pendingTranslation.isEmpty, "a repeated line is already translated")
    }
}
