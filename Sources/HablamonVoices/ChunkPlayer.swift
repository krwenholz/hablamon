#if canImport(AVFoundation)
    @preconcurrency import AVFoundation
    import Foundation
    import HablamonCore

    /// Plays a line that's generated piece by piece: the first piece starts playing as soon as it's
    /// ready while the rest generate, and progress follows the playback position.
    final class ChunkPlayer: @unchecked Sendable {
        struct Timing {
            /// From the start of generation to the first sound.
            var firstAudio: TimeInterval
            /// Generating every piece.
            var generating: TimeInterval
        }

        private let audio = AVAudioEngine()
        private let player = AVAudioPlayerNode()
        private let timePitch = AVAudioUnitTimePitch()
        private let format: AVAudioFormat

        init(sampleRate: Double) {
            format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
            audio.attach(player)
            audio.attach(timePitch)
            audio.connect(player, to: timePitch, format: format)
            audio.connect(timePitch, to: audio.mainMixerNode, format: format)
        }

        /// Generates each of `chunks` (pieces of `text`, in order) and plays them back to back.
        /// Returns once the last has played; throws `CancellationError` if the task is cancelled.
        func play(
            _ text: String, chunks: [String], rate: Double, progress: @escaping @Sendable (Int) -> Void,
            generate: (String) async throws -> [Float]
        ) async throws -> Timing {
            let started = Date()
            let playback = Playback(text: text, chunks: chunks, offsets: SpeechChunker.offsets(of: chunks, in: text))
            player.stop()
            timePitch.rate = Float(min(max(rate, 0.5), 2.0))
            if !audio.isRunning { try? audio.start() }
            let ticker = Task { [self] in
                while !Task.isCancelled {
                    if let nodeTime = player.lastRenderTime, let time = player.playerTime(forNodeTime: nodeTime) {
                        progress(playback.offset(atSample: Int(time.sampleTime)))
                    }
                    try? await Task.sleep(for: .milliseconds(100))
                }
            }
            defer { ticker.cancel() }
            var firstAudio: TimeInterval?
            for (index, chunk) in chunks.enumerated() {
                let samples = try await generate(chunk)
                if Task.isCancelled {
                    player.stop()
                    throw CancellationError()
                }
                schedule(samples, last: index == chunks.count - 1, playback: playback)
                if firstAudio == nil {
                    firstAudio = Date().timeIntervalSince(started)
                    player.play()
                }
            }
            let timing = Timing(firstAudio: firstAudio ?? 0, generating: Date().timeIntervalSince(started))
            await withTaskCancellationHandler {
                await playback.finished()
            } onCancel: { [self] in
                player.stop()
                playback.finish()
            }
            progress(text.utf16.count)
            return timing
        }

        /// Stopping the player calls the queued buffers' completions, which finishes the line.
        func stop() {
            player.stop()
        }

        /// Queues a generated piece after whatever is already playing.
        private func schedule(_ samples: [Float], last: Bool, playback: Playback) {
            guard !samples.isEmpty,
                let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count))
            else {
                if last { playback.finish() }
                return
            }
            buffer.frameLength = AVAudioFrameCount(samples.count)
            samples.withUnsafeBufferPointer { source in
                buffer.floatChannelData![0].update(from: source.baseAddress!, count: samples.count)
            }
            playback.add(samples: samples.count)
            player.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { _ in
                if last { playback.finish() }
            }
        }

        /// Tracks the pieces of one line as they're queued, to map playback position to a word and to
        /// know when the last piece has played.
        final class Playback: @unchecked Sendable {
            private let lock = NSLock()
            private let text: String
            private let chunks: [String]
            private let offsets: [Int]
            private var ends: [Int] = []
            private var done = false
            private var waiting: CheckedContinuation<Void, Never>?

            init(text: String, chunks: [String], offsets: [Int]) {
                self.text = text
                self.chunks = chunks
                self.offsets = offsets
            }

            func add(samples: Int) {
                lock.withLock { ends.append((ends.last ?? 0) + samples) }
            }

            /// The word being spoken at `sample` samples into the line.
            func offset(atSample sample: Int) -> Int {
                lock.withLock {
                    guard let index = ends.firstIndex(where: { sample < $0 }), index < chunks.count else {
                        return ends.count == chunks.count ? text.utf16.count : (offsets[safe: ends.count] ?? 0)
                    }
                    let start = index == 0 ? 0 : ends[index - 1]
                    let fraction = Double(sample - start) / Double(max(1, ends[index] - start))
                    return offsets[index] + PlaybackProgress.offset(fraction: fraction, in: chunks[index])
                }
            }

            func finish() {
                let continuation = lock.withLock { () -> CheckedContinuation<Void, Never>? in
                    done = true
                    defer { waiting = nil }
                    return waiting
                }
                continuation?.resume()
            }

            func finished() async {
                await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                    let alreadyDone = lock.withLock { () -> Bool in
                        if done { return true }
                        waiting = continuation
                        return false
                    }
                    if alreadyDone { continuation.resume() }
                }
            }
        }
    }

    extension Array {
        subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
    }
#endif
