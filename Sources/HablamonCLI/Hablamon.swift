import ArgumentParser

@main
struct Hablamon: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "hablamon",
        abstract: "Live Spanish audio for Pokémon Scarlet.",
        subcommands: [RunCommand.self, ExportCommand.self, OCRCommand.self, SchemaCommand.self]
    )
}
