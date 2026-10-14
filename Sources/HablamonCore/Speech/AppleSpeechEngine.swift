#if canImport(AVFoundation)
    import AVFoundation
    import Foundation
    import HablamonModels

    /// Speaks with the system's Spanish voices. Install Enhanced or Premium es-ES voices in
    /// System Settings → Accessibility → Spoken Content for better quality; the best installed one wins.
    public final class AppleSpeechEngine: NSObject, SpeechEngine, AVSpeechSynthesizerDelegate, @unchecked Sendable {
        public let id: SpeechEngineID = .apple
        public let language: String
        private let synthesizer = AVSpeechSynthesizer()
        private let lock = NSLock()
        /// The utterance in flight and who's waiting for it. Callbacks for older utterances are ignored.
        private var inFlight: (utterance: AVSpeechUtterance, done: CheckedContinuation<Void, Never>)?

        public init(language: String = "es-ES") {
            self.language = language
            super.init()
            synthesizer.delegate = self
        }

        public func prepare() async throws {}

        public func speak(_ text: String, voice plan: VoicePlan, rate: Double) async throws {
            try Task.checkCancellation()
            let utterance = AVSpeechUtterance(string: text)
            utterance.voice = Self.voice(for: plan, language: language)
            utterance.pitchMultiplier = Float(plan.pitch)
            let scaled = AVSpeechUtteranceDefaultSpeechRate * Float(rate)
            utterance.rate = min(AVSpeechUtteranceMaximumSpeechRate, max(AVSpeechUtteranceMinimumSpeechRate, scaled))
            await withTaskCancellationHandler {
                await withCheckedContinuation { continuation in
                    lock.withLock { inFlight = (utterance, continuation) }
                    synthesizer.speak(utterance)
                }
            } onCancel: {
                synthesizer.stopSpeaking(at: .immediate)
            }
        }

        public func stop() async {
            synthesizer.stopSpeaking(at: .immediate)
        }

        public nonisolated func speechSynthesizer(
            _ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance
        ) {
            complete(utterance)
        }

        public nonisolated func speechSynthesizer(
            _ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance
        ) {
            complete(utterance)
        }

        private func complete(_ utterance: AVSpeechUtterance) {
            let waiting = lock.withLock { () -> CheckedContinuation<Void, Never>? in
                guard let inFlight, inFlight.utterance === utterance else { return nil }
                self.inFlight = nil
                return inFlight.done
            }
            waiting?.resume()
        }

        /// The explicit voice if set, otherwise the highest-quality installed voice of the right gender.
        static func voice(for plan: VoicePlan, language: String) -> AVSpeechSynthesisVoice? {
            if let identifier = plan.voiceIdentifier, let voice = AVSpeechSynthesisVoice(identifier: identifier) {
                return voice
            }
            let installed = AVSpeechSynthesisVoice.speechVoices().filter { $0.language == language }
            let gender: AVSpeechSynthesisVoiceGender = plan.register == .male ? .male : .female
            let matching = installed.filter { $0.gender == gender }
            let pool = matching.isEmpty ? installed : matching
            return pool.max { $0.quality.rawValue < $1.quality.rawValue } ?? AVSpeechSynthesisVoice(language: language)
        }
    }
#endif
