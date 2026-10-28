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
    }
#endif
