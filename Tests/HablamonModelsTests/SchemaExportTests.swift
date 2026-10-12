import Foundation
import HablamonModels
import Testing

@Suite struct SchemaExportTests {
    static let schemasDirectory = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("schemas")

    @Test(arguments: try SchemaCatalog.exportAll().map(\.fileName))
    func committedSchemaIsCurrent(fileName: String) throws {
        let exported = try #require(try SchemaCatalog.exportAll().first { $0.fileName == fileName })
        let committed = try String(
            contentsOf: Self.schemasDirectory.appendingPathComponent(fileName),
            encoding: .utf8
        )
        #expect(
            committed == exported.contents,
            "schemas/\(fileName) is stale; run `swift run hablamon schema export`"
        )
    }

    @Test func noExtraSchemaFiles() throws {
        let expected = Set(try SchemaCatalog.exportAll().map(\.fileName))
        let committed = Set(try FileManager.default.contentsOfDirectory(atPath: Self.schemasDirectory.path))
        #expect(committed == expected)
    }

    @Test func schemaNamesAreUnique() throws {
        let names = try SchemaCatalog.exportAll().map(\.fileName)
        #expect(Set(names).count == names.count)
    }
}
