import HablamonCore
import HablamonModels
import Testing

@Suite struct BundledCharactersTests {
    let table: CharacterTable

    init() throws {
        table = try BundledData.defaultCharacters()
    }

    @Test func loadsAndValidates() {
        #expect(table.characters.count > 30)
        #expect(table.characters["narrator"] != nil)
    }

    /// Every name and alias must resolve to exactly one speaker, ignoring case.
    @Test func namesAndAliasesAreUnambiguous() {
        var seen: [String: String] = [:]
        for (name, speaker) in table.characters {
            for tag in [name] + (speaker.aliases ?? []) {
                let key = tag.lowercased()
                #expect(seen[key] == nil, "\(tag) is used by both \(seen[key] ?? "") and \(name)")
                seen[key] = name
            }
        }
    }

    @Test func keepsSpanishSpelling() {
        #expect(table.characters["Mencía"]?.englishName == "Nemona")
        #expect(table.characters["Damián"]?.englishName == "Arven")
        #expect(table.characters["Clavel"]?.aliases == ["Cael"])
    }

    @Test func versionExclusiveProfessors() {
        #expect(table.characters["Albora"]?.version == .scarlet)
        #expect(table.characters["Turo"]?.version == .violet)
    }
}
