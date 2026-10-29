import Foundation
import HablamonModels

/// The designed character voices as Kokoro styles, keyed by the same names as `VoiceLibrary`.
public enum KokoroVoices {
    public static func bundled() throws -> [String: [Float]] {
        guard let url = Bundle.module.url(forResource: "voices/kokoro-styles", withExtension: "json") else {
            throw CocoaError(.fileNoSuchFile)
        }
        let document = try DocumentLoader.load(KokoroStyles.self, from: String(contentsOf: url, encoding: .utf8))
        return document.styles.mapValues { $0.map(Float.init) }
    }
}
