import ArgumentParser

@main
struct Hablamon: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "hablamon",
        abstract: "Live Spanish audio for Pokémon Scarlet.",
        subcommands: []
    )
}
