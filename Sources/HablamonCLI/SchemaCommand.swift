import ArgumentParser
import Foundation
import HablamonModels

struct SchemaCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "schema",
        abstract: "Work with the JSON Schemas generated from the model types.",
        subcommands: [Export.self]
    )

    struct Export: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Write every schema to a directory.")

        @Option(name: .shortAndLong, help: "Directory to write *.schema.json files to.")
        var output: String = "schemas"

        func run() throws {
            let directory = URL(fileURLWithPath: output, isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            for schema in try SchemaCatalog.exportAll() {
                let url = directory.appendingPathComponent(schema.fileName)
                try Data(schema.contents.utf8).write(to: url, options: .atomic)
                print("wrote \(url.path)")
            }
        }
    }
}
