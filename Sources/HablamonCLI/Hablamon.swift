import ArgumentParser

@main
struct Hablamon: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "hablamon",
        abstract: "Live Spanish audio for Pokémon Scarlet.",
        subcommands: [OCRCommand.self, SchemaCommand.self]
    )
}
