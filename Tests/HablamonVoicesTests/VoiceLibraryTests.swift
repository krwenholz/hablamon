import Foundation
import HablamonCore
import HablamonModels
import Testing

@testable import HablamonVoices

@Suite struct VoiceLibraryTests {
    let library: VoiceLibrary

    init() throws {
        library = try VoiceLibrary.bundled()
    }

    @Test func everyClipInTheManifestExists() {
        for name in library.names {
            let clip = library.clip(named: name)
            #expect(clip.map { FileManager.default.fileExists(atPath: $0.url.path) } == true, "\(name)")
            #expect(clip?.referenceText.isEmpty == false, "\(name)")
        }
    }

    @Test func everyBundledCharacterGetsAClip() throws {
        let selector = VoiceSelector(clips: library.names)
        let table = try BundledData.defaultCharacters()
        for (name, speaker) in table.characters {
            let resolved: ResolvedSpeaker = name == "narrator" ? .narrator : .known(name: name, speaker: speaker)
            #expect(selector.plan(for: resolved).clip == name, "\(name) should have its own designed voice")
        }
        #expect(selector.plan(for: .unknown(tag: "Recluta")).clip == "generic-neutral")
    }

    @Test func tuningIsGentle() {
        for name in library.names {
            let clip = library.clip(named: name)!
            #expect((0.85...1.15).contains(clip.rate), "\(name) rate \(clip.rate)")
            #expect((-1.5...1.5).contains(clip.pitch), "\(name) pitch \(clip.pitch)")
        }
    }

    @Test func charactersGetTheirOwnSpeedAndPitch() throws {
        let mencia = try #require(library.clip(named: "Mencía"))
        let laureano = try #require(library.clip(named: "Laureano"))
        #expect(mencia.rate > 1, "bubbly and fast-talking")
        #expect(laureano.rate < 1 && laureano.pitch < 0, "flat, weary, deadpan")
        #expect(library.clip(named: "narrator")?.rate == 1)
    }
}
