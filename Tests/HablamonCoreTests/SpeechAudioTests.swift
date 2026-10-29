import Testing

@testable import HablamonCore

struct SpeechAudioTests {
    let rate = 1000

    @Test func cutsQuietNoiseAndALoneClickAfterSpeech() {
        let speech = (0..<500).map { index in Float(index % 2 == 0 ? 0.3 : -0.3) }
        let hiss = [Float](repeating: 0.005, count: 200)
        var click = [Float](repeating: 0, count: 100)
        click[50] = 0.9
        let trimmed = SpeechAudio.trimmingTrailingNoise(speech + hiss + click + hiss, sampleRate: rate)
        #expect(trimmed.count >= 500 && trimmed.count < 560)
        // Fades out rather than stopping on a full-scale sample.
        #expect(abs(trimmed.last ?? 1) < 0.05)
    }

    @Test func leavesCleanSpeechAndSilenceAlone() {
        let speech = (0..<300).map { index in Float(index % 2 == 0 ? 0.3 : -0.3) }
        #expect(SpeechAudio.trimmingTrailingNoise(speech, sampleRate: rate).count == 300)
        #expect(SpeechAudio.trimmingTrailingNoise([Float](repeating: 0, count: 100), sampleRate: rate).isEmpty)
    }
}
