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
}
