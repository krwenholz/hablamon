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

    /// A bundled game profile, such as `scarlet`.
    public static func profile(_ id: String) throws -> GameProfile {
        guard let url = Bundle.module.url(forResource: id, withExtension: "json", subdirectory: "profiles") else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try DocumentLoader.load(GameProfile.self, from: try String(contentsOf: url, encoding: .utf8))
    }
}
