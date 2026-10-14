import HablamonModels
import Testing

@testable import HablamonCore

@Suite struct SpeakerResolverTests {
    let resolver: SpeakerResolver

    init() throws {
        resolver = SpeakerResolver(table: try BundledData.defaultCharacters())
    }

    @Test func emptyTagIsNarrator() {
        #expect(resolver.resolve(tag: nil) == .narrator)
        #expect(resolver.resolve(tag: "  ") == .narrator)
    }

    @Test(arguments: [
        ("Mencía", "Mencía"),
        ("Mencia", "Mencía"),  // accent lost in OCR
        ("MENCÍA", "Mencía"),
        ("Clavei", "Clavel"),  // the design doc's example misread
        ("Cael", "Clavel"),  // alias
        ("Abuela", "Heladia"),
        ("e-Nigma", "e-Nigma"),
        ("eNigma", "e-Nigma"),
        ("Damlán", "Damián"),
    ])
    func resolvesKnownSpeakers(tag: String, expected: String) {
        #expect(resolver.resolve(tag: tag).name == expected)
    }

    @Test func shortNamesAllowOneEdit() {
        #expect(resolver.resolve(tag: "Lev1").name == "Levi")
        // Two edits on a four-letter name is too far: "Lavu" must not become Levi.
        #expect(resolver.resolve(tag: "Lavu") == .unknown(tag: "Lavu"))
    }

    @Test func tiedMatchesAreUnknown() {
        // One edit from Mila, Mimí, and Lima alike.
        #expect(resolver.resolve(tag: "Mima") == .unknown(tag: "Mima"))
    }

    @Test func unmatchedTagIsUnknown() {
        #expect(resolver.resolve(tag: "Vendedora") == .unknown(tag: "Vendedora"))
    }
}
