import Foundation
import HablamonModels
import Testing

@Suite struct DocumentLoaderTests {
    @Test func reportsPathOfInvalidValue() {
        let text = #"{"schemaVersion": 1, "characters": {"Clavel": {"gender": "robot"}}}"#
        #expect {
            try DocumentLoader.load(CharacterTable.self, from: text)
        } throws: { error in
            guard case DocumentError.invalid(let issues) = error else { return false }
            return issues.contains { $0.path == "/characters/Clavel/gender" }
        }
    }

    @Test func rejectsMisspelledKey() {
        let text = #"{"schemaVersion": 1, "characters": {"Clavel": {"gender": "male", "gendr": "male"}}}"#
        #expect {
            try DocumentLoader.load(CharacterTable.self, from: text)
        } throws: { error in
            guard case DocumentError.invalid(let issues) = error else { return false }
            return issues == [.init(path: "/characters/Clavel/gendr", message: "unexpected key")]
        }
    }

    @Test func refusesNewerVersion() {
        let text = #"{"schemaVersion": 2, "characters": {}}"#
        #expect(throws: DocumentError.newerVersion(found: 2, supported: 1)) {
            try DocumentLoader.load(CharacterTable.self, from: text)
        }
    }

    @Test func requiresVersion() {
        #expect(throws: DocumentError.missingVersion(key: "schemaVersion")) {
            try DocumentLoader.load(CharacterTable.self, from: #"{"characters": {}}"#)
        }
    }

    @Test func rejectsMalformedJSON() {
        #expect {
            try DocumentLoader.load(CharacterTable.self, from: "{")
        } throws: { error in
            if case DocumentError.invalidJSON = error { return true }
            return false
        }
    }

    @Test func acceptsSchemaKey() throws {
        let text = #"{"$schema": "schemas/characters.schema.json", "schemaVersion": 1, "characters": {}}"#
        let table = try DocumentLoader.load(CharacterTable.self, from: text)
        #expect(table.schemaURI == "schemas/characters.schema.json")
    }

    @Test func rejectsModifierKeys() {
        var settings = Settings.defaults
        settings.keys.repeatLast = "cmd+r"
        #expect(throws: DocumentError.self) {
            try DocumentLoader.load(Settings.self, from: try encode(settings))
        }
    }

    @Test func migratesVersionOneHotkeysToPlainKeys() throws {
        let v1 = #"""
            {"schemaVersion": 1, "engine": "apple", "speed": 0.9, "idleSampleInterval": 2, "dialogueSampleRate": 4,
             "speakBattleText": false, "allowBuiltInCamera": false,
             "hotkeys": {"repeatLast": "opt+cmd+R", "repeatLastSlowly": "opt+shift+cmd+R", "toggleSpeed": "opt+cmd+S",
                         "togglePause": "opt+cmd+P", "recalibrate": "opt+cmd+C", "holdForEnglish": "opt+cmd+E"}}
            """#
        let settings = try DocumentLoader.load(Settings.self, from: v1)
        #expect(settings.schemaVersion == 2)
        #expect(settings.keys == Keys.defaults)
        #expect(settings.speed == 0.9, "other settings survive")
    }
}

func encode<T: Encodable>(_ value: T) throws -> String {
    String(decoding: try JSONEncoder().encode(value), as: UTF8.self)
}
