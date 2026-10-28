#if canImport(CoreImage) && canImport(Vision)
    import CoreImage
    import Foundation
    import Testing

    @testable import HablamonCore

    /// The whole-screen reader on real screenshots of menus, banners, battles, bubbles, and subtitles.
    @Suite struct ScreenshotFixtureTests {
        struct Expected: Decodable {
            var screens: [String: [String]]
        }

        static let directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Fixtures/photos")

        static let expected: [String: [String]] = {
            guard let data = try? Data(contentsOf: directory.appendingPathComponent("screens.expected.json")) else {
                return [:]
            }
            return (try? JSONDecoder().decode(Expected.self, from: data).screens) ?? [:]
        }()

        @Test(arguments: expected.keys.sorted())
        func findsTheTextOnScreen(_ name: String) throws {
            let url = Self.directory.appendingPathComponent(name)
            let image = try #require(CIImage(contentsOf: url, options: [.applyOrientationProperty: true]))
            let flat = ScreenReader.flatten(image)
            let picture = try #require(CIContext().createCGImage(flat, from: flat.extent))
            let texts = try ScreenReader().read(picture).map(\.text)
            print("[screens] \(name): \(texts)")
            for phrase in Self.expected[name] ?? [] {
                #expect(
                    texts.contains { $0.localizedCaseInsensitiveContains(phrase) }, "\(name) should show “\(phrase)”")
            }
        }

        /// Which screenshots show speech without a dialogue box, and which must not be mistaken for it.
        @Test(
            arguments: [
                ("subtitle-proyecto_far_straight.jpeg", "subtitle", nil),
                ("subtitle-crecer_far_straight-glare.jpeg", "subtitle", nil),
                ("npc-bubble-clases_far_straight-glare.jpeg", "bubble", nil),
                ("casiopea-stardust_far_straight-glare.jpeg", "subtitle", "Casiopea"),
                ("banner-ciudad-meseta_far_straight-glare.jpeg", "none", nil),
                ("banner-clase-hogar_far_straight-glare.jpeg", "none", nil),
                ("map-ciudad-meseta_far_straight-glare.jpeg", "none", nil),
                ("map-menu-pokedex_far_straight-glare.jpeg", "none", nil),
                ("battle-menu-lechonk_far_straight-glare.jpeg", "none", nil),
                ("party-menu_far_straight-glare.jpeg", "none", nil),
            ] as [(String, String, String?)])
        func findsSpeechWithoutABox(_ name: String, _ kind: String, _ speaker: String?) throws {
            let url = Self.directory.appendingPathComponent(name)
            let image = try #require(CIImage(contentsOf: url, options: [.applyOrientationProperty: true]))
            let found = try ScreenReader().freeSpeech(in: ScreenReader.flatten(image), context: CIContext())
            print("[free] \(name): \(found.map { "\($0.kind) \($0.speaker ?? "-"): \($0.text)" })")
            if kind == "none" {
                #expect(found.isEmpty)
            } else {
                #expect(found.count == 1)
                #expect(found.first.map { "\($0.kind)" } == kind)
                #expect(found.first?.speaker == speaker)
            }
        }
    }
#endif
