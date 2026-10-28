/// Estimates which word is being spoken from how far playback has got, for engines that report no
/// word timings. Speech is roughly even across characters, so the fraction of audio played maps to
/// the same fraction of the text, snapped back to the start of that word.
public enum PlaybackProgress {
    /// A UTF-16 offset into `text` for `fraction` (0–1) of the audio played.
    public static func offset(fraction: Double, in text: String) -> Int {
        let units = Array(text.utf16)
        guard fraction > 0 else { return 0 }
        guard fraction < 1 else { return units.count }
        var index = Int((Double(units.count) * fraction).rounded(.down))
        // Back up to the start of the word the position falls in.
        while index > 0, !isSpace(units[index - 1]) { index -= 1 }
        return index
    }

    private static func isSpace(_ unit: UTF16.CodeUnit) -> Bool {
        unit == 0x20 || unit == 0x0A || unit == 0x09
    }
}
