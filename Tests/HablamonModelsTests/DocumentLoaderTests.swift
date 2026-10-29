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
        #expect(settings.schemaVersion == Settings.currentVersion)
        #expect(settings.keys == Keys.defaults)
        #expect(settings.speed == 0.9, "other settings survive")
    }
}

extension DocumentLoaderTests {
    @Test func versionTwoMovesToCharacterVoicesOnce() throws {
        var old = Settings.defaults
        old.engine = .apple
        old.schemaVersion = 2
        let migrated = try DocumentLoader.load(Settings.self, from: try encode(old))
        #expect(migrated.engine == .kokoro, "apple was only ever the old default")
        #expect(migrated.schemaVersion == Settings.currentVersion)

        var chosen = Settings.defaults
        chosen.engine = .apple
        let kept = try DocumentLoader.load(Settings.self, from: try encode(chosen))
        #expect(kept.engine == .apple, "a version 3 file that says apple was chosen on purpose")
    }

    @Test func versionThreeSamplesTwiceASecondWhenIdle() throws {
        var old = Settings.defaults
        old.idleSampleInterval = 2
        old.schemaVersion = 3
        #expect(try DocumentLoader.load(Settings.self, from: try encode(old)).idleSampleInterval == 0.5)

        var custom = Settings.defaults
        custom.idleSampleInterval = 1.5
        custom.schemaVersion = 3
        #expect(try DocumentLoader.load(Settings.self, from: try encode(custom)).idleSampleInterval == 1.5)
        #expect(Settings.defaults.idleSampleInterval == 0.5)
    }

    @Test func versionFourMovesFromQwenToKokoro() throws {
        var old = Settings.defaults
        old.engine = .qwen3
        old.schemaVersion = 4
        #expect(try DocumentLoader.load(Settings.self, from: try encode(old)).engine == .kokoro)

        var apple = Settings.defaults
        apple.engine = .apple
        apple.schemaVersion = 4
        #expect(try DocumentLoader.load(Settings.self, from: try encode(apple)).engine == .apple)

        var chosen = Settings.defaults
        chosen.engine = .qwen3
        #expect(
            try DocumentLoader.load(Settings.self, from: try encode(chosen)).engine == .qwen3,
            "a version 5 file that says qwen3 was chosen on purpose")
    }

    @Test func kokoroIsTheDefaultEngine() {
        #expect(Settings.defaults.engine == .kokoro)
    }
}

func encode<T: Encodable>(_ value: T) throws -> String {
    String(decoding: try JSONEncoder().encode(value), as: UTF8.self)
}
