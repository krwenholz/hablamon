#if canImport(SwiftUI) && canImport(AVFoundation)
    import Foundation
    import HablamonCore
    import HablamonModels
    import Observation

    /// What the window shows and the actions it can take. Replay events arrive on a stream and are
    /// applied in order on the main actor.
    @MainActor @Observable
    final class AppModel {
        var state = CompanionState()
        var words: [VocabEntry] = []
        /// Labels in English while the English key is held.
        var english = false
        /// Problems loading files, shown in diagnostics.
        var issues: [String] = []
        /// How far behind the video clock processing is, in seconds.
        var replayLag = 0.0
        var paused = false
        var source: String?
        /// What the right-hand slot shows.
        var side: SidePanel = .words {
            didSet { live?.setPreviewing(side == .calibration) }
        }
        /// The latest camera frame and proposed corners, while calibrating.
        var calibrationPreview: CalibrationPreview?
        /// Why live mode isn't running yet, such as waiting for the iPhone.
        var liveStatus: String?

        @ObservationIgnored let store: AppSupportStore
        @ObservationIgnored var characters: CharacterTable
        @ObservationIgnored private var known: KnownWords
        @ObservationIgnored let settings: Settings
        @ObservationIgnored private var ranker: VocabRanker?
        @ObservationIgnored let narrator: Narrator
        @ObservationIgnored private let voices = VoiceSelector()
        @ObservationIgnored private var replayTask: Task<Void, Never>?
        /// Decodes and reads the video; cancelled along with `replayTask` so an old replay stops.
        @ObservationIgnored private var replayProducer: Task<Void, Never>?
        @ObservationIgnored var transcript: TranscriptWriter?
        @ObservationIgnored var log: FileLog?
        @ObservationIgnored var sessionStart = Date()
        @ObservationIgnored var live: LiveSession?
        @ObservationIgnored var keyMonitor: Any?
        /// Bumped per spoken line so late progress callbacks from an old line are ignored.
        @ObservationIgnored private var generation = 0

        init(store: AppSupportStore = AppSupportStore()) {
            self.store = store
            var problems: [String] = []
            do { try store.seedIfNeeded() } catch { problems.append("seeding Application Support: \(error)") }
            let characters = store.characters()
            let settings = store.settings()
            let known = store.knownWords()
            self.characters = characters.value
            self.settings = settings.value
            self.known = known.value
            let apple = AppleSpeechEngine()
            narrator = Narrator(engine: apple, fallback: apple, speed: settings.value.speed)
            issues = problems + [characters.issue, settings.issue, known.issue].compactMap { $0 }
            log = try? FileLog(
                directory: store.logsDirectory, name: TranscriptWriter.sessionName(startingAt: sessionStart))
            log?.write("launched; root \(store.root.path)")
            for issue in issues { log?.write("issue: \(issue)") }
            loadVocabulary()
        }

        var voiceSummary: String { "Apple · \(String(format: "%.2g", settings.speed))×" }
        var keys: Keys { settings.keys }

        // MARK: Replay

        /// Plays a recorded video as if it were the live camera.
        func startReplay(video: URL, calibration: URL) {
            replayTask?.cancel()
            replayProducer?.cancel()
            source = video.lastPathComponent
            let quad: Calibration
            do {
                quad = try DocumentLoader.load(
                    Calibration.self, from: try String(contentsOf: calibration, encoding: .utf8))
            } catch {
                issues.append("\(calibration.lastPathComponent): \(error)")
                return
            }
            sessionStart = Date()
            // Replays are kept apart from real sessions so they don't skew word frequencies.
            transcript = try? TranscriptWriter(
                sessionsDirectory: store.root.appendingPathComponent("replays", isDirectory: true),
                session: TranscriptWriter.sessionName(startingAt: sessionStart))
            log?.write("replay \(video.path)")

            let (stream, continuation) = AsyncStream.makeStream(of: ReplayMessage.self)
            let characters = self.characters
            let started = ContinuousClock.now
            let producer = Task.detached(priority: .utility) {
                do {
                    try await Replay.run(
                        video: video, calibration: quad, profile: try BundledData.profile("scarlet"),
                        characters: characters, realTime: true,
                        onFrame: { found, time in
                            let lag = (ContinuousClock.now - started) / .seconds(1) - time
                            continuation.yield(.frame(found, lag: lag))
                        },
                        onEvent: { event, _ in continuation.yield(.pipeline(event)) })
                    continuation.yield(.finished(nil))
                } catch is CancellationError {
                } catch {
                    continuation.yield(.finished("\(error)"))
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in producer.cancel() }
            replayProducer = producer
            replayTask = Task { [weak self] in
                for await message in stream {
                    guard let self, !Task.isCancelled else { break }
                    await self.handle(message)
                }
            }
        }

        private enum ReplayMessage: Sendable {
            case pipeline(PipelineEvent)
            case frame(Bool, lag: Double)
            case finished(String?)
        }

        private func handle(_ message: ReplayMessage) async {
            switch message {
            case .frame(let found, let lag):
                replayLag = max(0, lag)
                state.apply(.frame(screenFound: found))
            case .finished(let error):
                log?.write("replay finished \(error ?? "ok")")
                if let error { issues.append("replay: \(error)") }
            case .pipeline(let event):
                await apply(event)
            }
        }

        /// A pipeline event from replay or the live camera.
        func apply(_ event: PipelineEvent) async {
            switch event {
            case .speak(let raw):
                let page = raw.reresolved(with: SpeakerResolver(table: characters), voices: voices)
                state.apply(.pipeline(.speak(page)))
                log?.write("line \(page.speaker.name): \(page.text)")
                ranker?.add(line: page.text)
                refreshWords()
                await writeTranscript(page)
                if !paused { await speak(page.text, voice: page.voice) }
            case .pageChanged:
                state.apply(.pipeline(.pageChanged))
                await narrator.interrupt()
            default:
                state.apply(.pipeline(event))
            }
        }

        private func writeTranscript(_ page: SpokenPage) async {
            do {
                try await transcript?.appendLine(
                    at: sessionStart.addingTimeInterval(page.time), speaker: page.speaker.name,
                    speakerRaw: page.speakerRaw, text: page.text, ocrConfidence: page.confidence,
                    engine: .apple, voice: page.voice.summary)
            } catch {
                log?.write("transcript: \(error)")
            }
        }

        // MARK: Speech

        /// `tracksCurrent` is false when replaying an older line, so it doesn't drive the top box.
        private func speak(_ text: String, voice: VoicePlan, tracksCurrent: Bool = true) async {
            generation += 1
            let token = generation
            guard tracksCurrent else {
                await narrator.say(text, voice: voice)
                return
            }
            await narrator.say(text, voice: voice) { offset in
                Task { @MainActor [weak self] in
                    guard let self, self.generation == token else { return }
                    self.state.apply(.speechProgress(utf16Offset: offset))
                }
            }
            state.apply(.speechStarted)
            Task { [weak self, narrator] in
                await narrator.finish()
                guard let self, self.generation == token else { return }
                self.state.apply(.speechFinished)
            }
        }

        /// Says a line again; `slow` plays it at 70 % of the usual speed.
        func replay(_ page: SpokenPage, slow: Bool = false) {
            var voice = page.voice
            if slow { voice.rate *= 0.7 }
            let isCurrent = page == state.current
            Task { await speak(page.text, voice: voice, tracksCurrent: isCurrent) }
        }

        func repeatLast(slow: Bool) {
            if let current = state.current { replay(current, slow: slow) }
        }

        /// Writes a line to this session's log.
        func note(_ message: String) {
            log?.write(message)
        }

        /// Opens the calibration panel; in live mode it shows the camera with proposed corners.
        func recalibrate() {
            side = .calibration
            live?.engine?.setWantsPreview(true)
            log?.write("recalibrate requested")
        }

        func togglePause() {
            paused.toggle()
            if paused { Task { await narrator.interrupt() } }
        }

        func toggleSpeed() {
            Task {
                let speed = await narrator.speed
                await narrator.setSpeed(speed < 0.95 ? 1.0 : settings.speed)
            }
        }

        // MARK: Words and speakers

        private func loadVocabulary() {
            let history = store.pastLines().map(\.text)
            let known = Set(self.known.lemmas)
            let names = Set(characters.characters.flatMap { [$0.key] + ($0.value.aliases ?? []) })
            Task.detached(priority: .utility) {
                do {
                    let glossary = try BundledGlossary.load()
                    let ranker = VocabRanker(
                        analyzer: NLWordAnalyzer(glossary: glossary), glosses: glossary, history: history, known: known,
                        names: names)
                    await MainActor.run { [weak self] in
                        self?.ranker = ranker
                        self?.refreshWords()
                    }
                } catch {
                    await MainActor.run { [weak self] in self?.issues.append("glossary: \(error)") }
                }
            }
        }

        private func refreshWords() {
            words = ranker?.top(5) ?? []
        }

        func markKnown(_ lemma: String) {
            ranker?.markKnown(lemma)
            known.lemmas.append(lemma)
            do { try store.save(known) } catch { issues.append("known-words.json: \(error)") }
            refreshWords()
        }

        /// Saves a voice for an unknown speaker; their next line uses it.
        func tag(_ speaker: UnknownSpeaker, as gender: Gender) {
            characters.characters[speaker.shownName] = Speaker(gender: gender)
            do { try store.save(characters) } catch { issues.append("characters.json: \(error)") }
            log?.write("tagged \(speaker.shownName) as \(gender.rawValue)")
            state.apply(.speakerTagged(key: speaker.key))
        }
    }
#endif
