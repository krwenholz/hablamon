import Foundation
import HablamonModels

/// Data files shipped inside the app.
public enum BundledData {
    /// The starter character table, used to seed `characters.json`.
    public static func defaultCharacters() throws -> CharacterTable {
        guard let url = Bundle.module.url(forResource: "characters.default", withExtension: "json") else {
            throw CocoaError(.fileNoSuchFile)
        }
        let text = try String(contentsOf: url, encoding: .utf8)
        return try DocumentLoader.load(CharacterTable.self, from: text)
    }
}
