#if canImport(CoreImage) && canImport(Vision)
    import CoreImage
    import Foundation
    import Testing

    @testable import HablamonCore

    /// Corrected screens saved by the iPhone app's Guardar captura: soft, tinted, with corners on the
    /// TV's bezel, and Mencía's green-on-black calls. Reading the screen's text must find each line
    /// and its speaker, which the box detector mostly couldn't.
    @Suite struct PhoneCaptureTests {
        static let directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Fixtures/phone-captures")

        @Test(
            arguments: [
                ("enhorabuena-gimnasio_far_bezel-corners.png", "Pueblo Altamía!", nil),
                ("enhorabuena-gimnasio_far_bezel-corners-pink.png", "Pueblo Altamía!", nil),
                ("helado-fresquitos_far_bezel-corners.png", "apetece uno?", nil),
                ("hesperio-clase-arte_far_bezel-corners.png", "clase de Arte.", "Hesperio"),
                ("que-tal-gimnasios_far_bezel-corners-call.png", "punto de mira ahora mismo?", "Mencía"),
                ("hola-miguel_far_bezel-corners-call.png", "¿quién si no?", "Mencía"),
                ("antes-de-afrontar_far_bezel-corners-bright-floor.png", "arena de combate local.", "Mencía"),
                ("aja-te-queria-ver_far_bezel-corners.png", "¡A ti te quería yo ver!", "Mencía"),
            ] as [(String, String, String?)])
        func readsTheLineAndSpeaker(_ name: String, _ ending: String, _ speaker: String?) throws {
            let url = Self.directory.appendingPathComponent(name)
            let image = try #require(CIImage(contentsOf: url), "missing fixture \(name)")
            let found = try ScreenReader().freeSpeech(in: image, context: CIContext(), dialogue: true)
            print("[phone] \(name): \(found.map { "\($0.kind) \($0.speaker ?? "-"): \($0.text)" })")
            let lines = found.filter { $0.kind == .dialogue }
            #expect(lines.count == 1)
            #expect(lines.first?.text.hasSuffix(ending) == true)
            #expect(lines.first?.speaker == speaker)
        }
    }
#endif
