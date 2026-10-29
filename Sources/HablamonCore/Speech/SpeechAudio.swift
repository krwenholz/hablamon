/// Cleanup for generated speech.
public enum SpeechAudio {
    /// Cuts what follows the end of speech: Kokoro often adds 100–300 ms of low noise, sometimes
    /// with a lone click. Speech ends at the last 50 ms window that's loud and follows another
    /// loud window, so a single spike doesn't count; the last 10 ms fade out.
    public static func trimmingTrailingNoise(_ samples: [Float], sampleRate: Int) -> [Float] {
        let window = max(1, sampleRate / 20)
        let floor: Float = 0.015
        func loud(_ start: Int) -> Bool {
            guard start >= 0 else { return true }
            let slice = samples[start..<min(samples.count, start + window)]
            let energy = slice.reduce(0) { $0 + $1 * $1 } / Float(max(1, slice.count))
            return energy.squareRoot() > floor
        }
        var start = samples.count - window
        var end = 0
        while start >= 0 {
            if loud(start) && loud(start - window) {
                end = min(samples.count, start + window)
                break
            }
            start -= window / 2
        }
        var trimmed = Array(samples[..<end])
        let fade = min(trimmed.count, sampleRate / 100)
        if fade >= 2 {
            for step in 0..<fade {
                trimmed[trimmed.count - fade + step] *= Float(fade - 1 - step) / Float(fade - 1)
            }
        }
        return trimmed
    }
}
