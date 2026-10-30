import AVFoundation
import AudioToolbox
import CoreGraphics
import Foundation
import HablamonCore
import HablamonModels
import HablamonVoices
import Observation
import UIKit

/// The latest camera frame for the camera screen, with the proposed TV corners.
struct CameraPreview {
    var image: CGImage
    /// Preview pixels per camera pixel.
    var scale: Double
    var proposal: Quad?
    var quality: QualityReport?
}

/// What the phone screen shows and the actions it takes: a cut-down `AppModel` for trying Hablamon
/// on the iPhone (phase 2 of docs/plans/ios-app.md). Phase 3 replaces it with a model shared with
/// the Mac app.
@MainActor @Observable
final class PhoneModel {
    var state = CompanionState()
    /// The camera screen: live picture, corners, and lens controls.
    var showingCamera = false {
        didSet {
            previewer?.isEnabled = showingCamera
            engine?.setWantsPreview(showingCamera)
        }
    }
    var showingStats = false
    var preview: CameraPreview?
    /// Why nothing is running yet, such as no camera permission.
    var status: String?
    var paused = false
    /// Speaking at 1× instead of the slow default.
    var normalSpeed = false
    var voiceStatus: VoiceModelStatus?
    var lenses: [PhoneLens] = []
    var lensID: String?
    var controls = PhoneCamera.Controls()
    var thermal = ProcessInfo.ThermalState.nominal
    /// 0–1, or nil when iOS doesn't say.
    var battery: Double?
    var charging = false
    /// The newest log lines, for the stats panel.
    var recentLog: [String] = []
    /// The last translation failed, so the English slot says so instead of waiting.
    var translationProblem = false
    @ObservationIgnored var translationReady = false

    @ObservationIgnored let store: AppSupportStore
    @ObservationIgnored let settings: Settings
    @ObservationIgnored private var characters: CharacterTable
    @ObservationIgnored private let narrator: Narrator
    @ObservationIgnored private var voices = VoiceSelector()
    @ObservationIgnored private var voiceEngine: SpeechEngineID = .apple
    @ObservationIgnored private var transcript: TranscriptWriter?
    @ObservationIgnored private var log: FileLog?
    @ObservationIgnored private let sessionStart = Date()
    @ObservationIgnored private var camera: PhoneCamera?
    @ObservationIgnored private var engine: LiveEngine?
    @ObservationIgnored private var previewer: PreviewRenderer?
    @ObservationIgnored private var tasks: [Task<Void, Never>] = []
    @ObservationIgnored private var started = false
    /// Bumped per spoken line so late progress callbacks from an old line are ignored.
    @ObservationIgnored private var generation = 0

    private enum Saved {
        static let lens = "camera.lens"
        static let zoom = "camera.zoom"
        static let exposureBias = "camera.exposureBias"
        static let focusLocked = "camera.focusLocked"
    }

    /// Messages from the camera and engine, applied in order on the main actor.
    private enum Message: Sendable {
        case engine(LiveEngine.Message)
        case previewFrame(CGImage, scale: Double)
        case log(String)
    }

    init() {
        let store = AppSupportStore()
        self.store = store
        var problems: [String] = []
        do { try store.seedIfNeeded() } catch { problems.append("seeding the data folder: \(error)") }
        let settings = store.settings()
        let characters = store.characters()
        self.settings = settings.value
        self.characters = characters.value
        let apple = AppleSpeechEngine()
        var kokoro: KokoroSpeechEngine?
        // Qwen3 is Mac-only; on the phone every character voice is Kokoro.
        if settings.value.engine != .apple, let library = try? VoiceLibrary.bundled() {
            kokoro = KokoroSpeechEngine(
                library: library, fallback: apple,
                modelsDirectory: store.root.appendingPathComponent("models", isDirectory: true))
            voices = VoiceSelector(clips: library.names)
        }
        narrator = Narrator(engine: kokoro ?? apple, fallback: apple, speed: settings.value.speed)
        log = try? FileLog(
            directory: store.logsDirectory, name: TranscriptWriter.sessionName(startingAt: sessionStart))
        note("launched on \(Self.machine) iOS \(UIDevice.current.systemVersion); root \(store.root.path)")
        for issue in problems + [settings.issue, characters.issue].compactMap({ $0 }) { note("issue: \(issue)") }
        if let kokoro { loadVoices(kokoro) }
    }

    /// The hardware model, such as "iPhone16,1", for the log.
    private static var machine: String {
        var info = utsname()
        uname(&info)
        return withUnsafeBytes(of: info.machine) { bytes in
            String(decoding: bytes.prefix { $0 != 0 }, as: UTF8.self)
        }
    }

    // MARK: Starting

    func start() {
        guard !started else { return }
        started = true
        UIApplication.shared.isIdleTimerDisabled = true
        configureAudio()
        watchDevice()
        tasks.append(
            Task { [weak self] in
                guard await PhoneCamera.authorize() else {
                    self?.status = "Sin permiso para la cámara: Ajustes › Hablamon › Cámara"
                    self?.note("camera access denied")
                    return
                }
                self?.begin()
            })
    }

    private func begin() {
        guard let profile = try? BundledData.profile("scarlet") else {
            status = "No se pudo cargar el perfil del juego"
            return
        }
        let calibration = store.calibration(for: .iphone)
        if let issue = calibration.issue { note("issue: \(issue)") }
        let reference = store.reference(for: .iphone)
        let defaults = UserDefaults.standard
        lenses = PhoneCamera.lenses()
        note("lenses: \(lenses.map { "\($0.name) [\($0.id)]" }.joined(separator: ", "))")

        let (stream, continuation) = AsyncStream.makeStream(of: Message.self)
        let engine = LiveEngine(
            profile: profile, characters: characters, calibration: calibration.value?.screenQuad,
            reference: reference, settings: settings, startingAt: Date(),
            onMessage: { continuation.yield(.engine($0)) })
        let previewer = PreviewRenderer { image, scale in continuation.yield(.previewFrame(image, scale: scale)) }
        let camera = PhoneCamera()
        camera.onFrame = { image, date in
            engine.feed(image, at: date)
            previewer.offer(image, at: date)
        }
        camera.onSignal = { signal, date in engine.signal(signal, at: date) }
        camera.onLog = { continuation.yield(.log($0)) }
        do {
            try camera.start(lensID: defaults.string(forKey: Saved.lens) ?? calibration.value?.deviceID)
        } catch {
            status = "\(error)"
            note("camera failed: \(error)")
            return
        }
        self.engine = engine
        self.camera = camera
        self.previewer = previewer
        if defaults.object(forKey: Saved.zoom) != nil { camera.setZoom(defaults.double(forKey: Saved.zoom)) }
        camera.setExposureBias(defaults.double(forKey: Saved.exposureBias))
        if defaults.bool(forKey: Saved.focusLocked) { camera.setFocusLocked(true) }
        refreshControls()
        transcript = try? TranscriptWriter(
            sessionsDirectory: store.sessionsDirectory,
            session: TranscriptWriter.sessionName(startingAt: sessionStart))
        if calibration.value == nil || reference == nil { showingCamera = true }
        previewer.isEnabled = showingCamera

        tasks.append(
            Task { [weak self] in
                for await message in stream {
                    guard let self else { break }
                    await self.handle(message)
                }
            })
        tasks.append(
            Task {
                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(500))
                    engine.tick(Date())
                }
            })
    }

    /// Speech plays even with the ring switch on silent, and is spoken audio for AirPods' sake.
    private func configureAudio() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .spokenAudio)
            try session.setActive(true)
        } catch {
            note("audio session: \(error)")
        }
    }

    /// Downloads (the first time) and loads Kokoro; Apple speaks meanwhile.
    private func loadVoices(_ engine: KokoroSpeechEngine) {
        voiceStatus = .notLoaded
        engine.onStatus = { status in Task { @MainActor [weak self] in self?.voiceStatus = status } }
        engine.onLog = { line in Task { @MainActor [weak self] in self?.note(line) } }
        Task.detached(priority: .utility) { [weak self] in
            do {
                try await engine.prepare()
                await self?.voicesReady()
            } catch {
                await self?.note("kokoro voices failed to load: \(error)")
            }
        }
    }

    private func voicesReady() {
        voiceEngine = .kokoro
        note("kokoro voices ready")
    }

    var voiceSummary: String {
        switch voiceStatus {
        case nil: "Apple"
        case .ready?: "Kokoro"
        case .downloading(let fraction)?: "Voces: descargando \(Int(fraction * 100)) %"
        case .notLoaded?, .loading?: "Voces: cargando…"
        case .failed?: "Apple (voces no disponibles)"
        }
    }

    // MARK: Engine messages

    private func handle(_ message: Message) async {
        switch message {
        case .log(let line):
            note(line)
        case .previewFrame(let image, let scale):
            preview = CameraPreview(
                image: image, scale: scale, proposal: preview?.proposal, quality: preview?.quality)
        case .engine(let message):
            await handle(message)
        }
    }

    private func handle(_ message: LiveEngine.Message) async {
        switch message {
        case .pipeline(let event):
            await apply(event)
        case .frame(let found):
            state.apply(.frame(screenFound: found))
        case .state(let connection):
            state.apply(.connection(connection))
            note("connection \(connection)")
            if connection == .recalibrating { showingCamera = true }
        case .effect(let effect):
            await perform(effect)
        case .preview(let image, let scale, let proposal, let quality):
            // The engine's frame is up to a second old; keep the smoother camera frame if there is one.
            if previewer?.isEnabled == true, var current = preview {
                current.proposal = proposal
                current.quality = quality
                preview = current
            } else {
                preview = CameraPreview(image: image, scale: scale, proposal: proposal, quality: quality)
            }
        case .calibrated(let quad, let reference):
            saveCalibration(quad, reference: reference)
        case .log(let line):
            note(line)
        case .meter(let point):
            camera?.meterExposure(at: CGPoint(x: point.x, y: point.y))
        }
    }

    private func perform(_ effect: ConnectionMonitor.Effect) async {
        note("effect \(effect)")
        switch effect {
        case .stopPipeline:
            await narrator.interrupt()
        case .logGap(let reason, let duration):
            state.apply(.gap(reason, seconds: duration))
            try? await transcript?.appendGap(at: Date(), reason: reason, duration: duration)
        case .logRecalibration(let trigger):
            try? await transcript?.appendRecalibration(at: Date(), trigger: trigger)
        case .showCalibration:
            showingCamera = true
        case .play(let cue):
            // Short built-in system sounds: a tick, a pop, and an alert.
            let sound: SystemSoundID =
                switch cue {
                case .stoppedWatching: 1104
                case .resumedWatching: 1105
                case .needsAttention: 1016
                }
            AudioServicesPlaySystemSound(sound)
        }
    }

    private func apply(_ event: PipelineEvent) async {
        switch event {
        case .speak(let raw):
            var page = raw.reresolved(with: SpeakerResolver(table: characters), voices: voices)
            page.voice.clip = voices.plan(for: page.speaker).clip
            state.apply(.pipeline(.speak(page)))
            note("line \(page.speaker.name): \(page.text)")
            do {
                try await transcript?.appendLine(
                    at: sessionStart.addingTimeInterval(page.time), speaker: page.speaker.name,
                    speakerRaw: page.speakerRaw, text: page.text, ocrConfidence: page.confidence,
                    engine: voiceEngine, voice: page.voice.summary)
            } catch {
                note("transcript: \(error)")
            }
            if !paused { await speak(page.text, voice: page.voice) }
        case .pageChanged:
            state.apply(.pipeline(.pageChanged))
            await narrator.interrupt()
        default:
            state.apply(.pipeline(event))
        }
    }

    // MARK: Speech

    /// `tracksCurrent` is false when replaying an older line, so it doesn't drive the highlight.
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

    /// Says the current line again; `slow` plays it at 70 % of the usual speed.
    func repeatLast(slow: Bool) {
        guard let current = state.current else { return }
        var voice = current.voice
        if slow { voice.rate *= 0.7 }
        Task { await speak(current.text, voice: voice) }
    }

    func togglePause() {
        paused.toggle()
        if paused { Task { await narrator.interrupt() } }
    }

    func toggleSpeed() {
        normalSpeed.toggle()
        let speed = normalSpeed ? 1.0 : settings.speed
        Task { await narrator.setSpeed(speed) }
    }

    var currentTranslation: String? {
        guard let current = state.current else { return nil }
        return state.translation(of: current.text) ?? (translationProblem ? "Traducción no disponible" : nil)
    }

    // MARK: Camera

    func recalibrate() {
        showingCamera = true
        note("recalibrate requested")
    }

    /// The player accepted these corners.
    func confirm(_ quad: Quad) {
        engine?.confirm(quad, at: Date())
        showingCamera = false
    }

    func useLens(_ id: String) {
        guard id != lensID, let camera else { return }
        do {
            try camera.useLens(id)
        } catch {
            note("lens switch failed: \(error)")
            return
        }
        let defaults = UserDefaults.standard
        defaults.set(id, forKey: Saved.lens)
        defaults.removeObject(forKey: Saved.zoom)
        defaults.set(false, forKey: Saved.focusLocked)
        // Each lens has its own exposure; carry the bias over.
        camera.setExposureBias(defaults.double(forKey: Saved.exposureBias))
        refreshControls()
        pictureChanged()
    }

    func setZoom(_ zoom: Double) {
        camera?.setZoom(zoom)
        controls.zoom = zoom
        UserDefaults.standard.set(zoom, forKey: Saved.zoom)
    }

    /// The old corners don't fit after a lens or zoom change: look for the TV again, and keep the
    /// camera screen open so the new corners can be checked.
    func pictureChanged() {
        engine?.signal(.screenMismatch, at: Date())
        recalibrate()
    }

    func setExposureBias(_ bias: Double) {
        camera?.setExposureBias(bias)
        controls.exposureBias = bias
        UserDefaults.standard.set(bias, forKey: Saved.exposureBias)
    }

    func setFocusLocked(_ locked: Bool) {
        camera?.setFocusLocked(locked)
        controls.focusLocked = locked
        UserDefaults.standard.set(locked, forKey: Saved.focusLocked)
    }

    private func refreshControls() {
        guard let camera else { return }
        controls = camera.controls()
        lensID = UserDefaults.standard.string(forKey: Saved.lens) ?? lenses.first { $0.magnification == 1 }?.id
    }

    private func saveCalibration(_ quad: Quad, reference: GrayImage) {
        let calibration = Calibration(
            deviceID: lensID ?? "unknown", deviceName: lenses.first { $0.id == lensID }?.name, screenQuad: quad,
            zoomFactor: controls.zoom, referenceThumbnail: "reference.pgm",
            calibratedAt: ISO8601DateFormatter().string(from: Date()))
        do {
            try store.save(calibration, for: .iphone)
            try store.save(reference: reference, for: .iphone)
            note("calibrated \(quad) at \(controls.zoom)× on \(calibration.deviceName ?? "?")")
        } catch {
            note("calibration.json: \(error)")
        }
    }

    // MARK: Heat and battery

    /// Samples thermal state and battery every few seconds, and logs them every minute and on
    /// every thermal change, so a long session can be read back afterwards.
    private func watchDevice() {
        UIDevice.current.isBatteryMonitoringEnabled = true
        tasks.append(
            Task { [weak self] in
                var lastLogged: Date?
                while !Task.isCancelled {
                    guard let self else { return }
                    let previous = self.thermal
                    self.sampleDevice()
                    if self.thermal != previous || lastLogged.map({ Date().timeIntervalSince($0) >= 60 }) ?? true {
                        lastLogged = Date()
                        self.note(self.deviceSummary)
                    }
                    try? await Task.sleep(for: .seconds(5))
                }
            })
    }

    private func sampleDevice() {
        thermal = ProcessInfo.processInfo.thermalState
        let level = UIDevice.current.batteryLevel
        battery = level < 0 ? nil : Double(level)
        charging = [.charging, .full].contains(UIDevice.current.batteryState)
    }

    var thermalName: String {
        switch thermal {
        case .nominal: "nominal"
        case .fair: "fair"
        case .serious: "serious"
        case .critical: "critical"
        @unknown default: "unknown"
        }
    }

    var deviceSummary: String {
        let minutes = Int(Date().timeIntervalSince(sessionStart) / 60)
        let level = battery.map { "\(Int($0 * 100)) %" } ?? "?"
        return "device: thermal \(thermalName), battery \(level)\(charging ? " charging" : ""), "
            + "\(state.lineCount) lines, \(minutes) min"
    }

    // MARK: Log

    func note(_ message: String) {
        log?.write(message)
        recentLog.append(message)
        if recentLog.count > 12 { recentLog.removeFirst(recentLog.count - 12) }
    }
}
