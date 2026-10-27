#if canImport(SwiftUI) && canImport(AVFoundation)
    import AppKit
    import CoreImage
    import Foundation
    import HablamonCore
    import HablamonModels

    /// The latest camera frame shown in the calibration panel, with proposed corners.
    struct CalibrationPreview {
        var image: CGImage
        /// Preview pixels per camera pixel.
        var scale: Double
        var proposal: Quad?
        var quality: QualityReport?
    }

    /// Owns the camera and live engine while the app watches the TV, and relays their messages to
    /// the model on the main actor in order.
    @MainActor
    final class LiveSession {
        private(set) var engine: LiveEngine?
        private var camera: LiveCamera?
        private var previewer: PreviewRenderer?
        private var device: CameraInfo?
        private var loop: Task<Void, Never>?
        private var ticker: Task<Void, Never>?
        private var waiter: Task<Void, Never>?
        private weak var model: AppModel?
        private var lastSeen: String?

        init(model: AppModel) {
            self.model = model
        }

        func start() {
            model?.note("live mode: camera permission \(LiveCamera.authorizationDescription)")
            waiter = Task { [weak self] in
                // Ask first: macOS may not list the iPhone to an app that hasn't been allowed the camera.
                guard await LiveCamera.authorize() else {
                    self?.model?.liveStatus = text(.cameraDenied, english: false)
                    self?.model?.note("camera access denied")
                    return
                }
                self?.model?.note("camera access granted; looking for the iPhone")
                // Wait for the pinned iPhone (or the first one, before any calibration).
                while !Task.isCancelled {
                    guard let self else { return }
                    if let choice = self.choose() {
                        self.begin(with: choice)
                        return
                    }
                    try? await Task.sleep(for: .seconds(3))
                }
            }
        }

        func stop() {
            waiter?.cancel()
            loop?.cancel()
            ticker?.cancel()
            camera?.stop()
        }

        /// Draws the camera smoothly in the calibration panel only while it's showing.
        func setPreviewing(_ on: Bool) {
            previewer?.isEnabled = on
        }

        func confirm(_ quad: Quad) {
            engine?.confirm(quad, at: Date())
            engine?.setWantsPreview(false)
        }

        /// The camera to use, or nil (and a waiting message) if it isn't there yet.
        private func choose() -> CameraInfo? {
            guard let model else { return nil }
            let pinned = model.store.calibration().value?.deviceID
            let cameras = LiveCamera.available()
            let seen = cameras.map { "\($0.name) [\($0.kind)]" }.joined(separator: ", ")
            if seen != lastSeen {
                lastSeen = seen
                model.note("cameras: \(seen.isEmpty ? "none" : seen)")
            }
            let choice = CameraChooser.choose(
                from: cameras, pinned: pinned, allowBuiltIn: model.settings.allowBuiltInCamera)
            if choice == nil, model.liveStatus == nil {
                model.liveStatus = text(.waitingForPhone, english: model.english)
                model.note("waiting for the camera\(pinned.map { " \($0)" } ?? "")")
            }
            return choice
        }

        private func begin(with choice: CameraInfo) {
            guard let model else { return }
            let calibration = model.store.calibration()
            if let issue = calibration.issue { model.issues.append(issue) }
            model.liveStatus = nil
            device = choice
            model.source = choice.name
            model.note("live camera \(choice.name) (\(choice.id))")

            let (stream, continuation) = AsyncStream.makeStream(of: LiveEngine.Message.self)
            let engine = LiveEngine(
                profile: (try? BundledData.profile("scarlet"))!, characters: model.characters,
                calibration: calibration.value?.screenQuad, reference: model.store.reference(),
                settings: model.settings,
                startingAt: Date(), onMessage: { continuation.yield($0) })
            let previewer = PreviewRenderer { image, scale in
                Task { @MainActor [weak model] in model?.showPreviewFrame(image, scale: scale) }
            }
            self.previewer = previewer
            let camera = LiveCamera()
            camera.onFrame = { image, date in
                engine.feed(image, at: date)
                previewer.offer(image, at: date)
            }
            camera.onSignal = { signal, date in engine.signal(signal, at: date) }
            camera.onLog = { line in Task { @MainActor [weak model] in model?.note(line) } }
            do {
                try camera.start(deviceID: choice.id)
            } catch {
                // The phone may have gone away between choosing and starting; keep waiting for it.
                model.note("camera failed: \(error); waiting again")
                model.liveStatus = text(.waitingForPhone, english: model.english)
                start()
                return
            }
            self.engine = engine
            self.camera = camera
            model.startLiveTranscript()
            if calibration.value == nil || model.store.reference() == nil {
                model.side = .calibration
            }
            setPreviewing(model.side == .calibration)
            loop = Task { [weak self] in
                for await message in stream {
                    guard let self else { break }
                    await self.handle(message)
                }
            }
            ticker = Task {
                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(500))
                    engine.tick(Date())
                }
            }
        }

        private func handle(_ message: LiveEngine.Message) async {
            guard let model else { return }
            switch message {
            case .pipeline(let event):
                await model.apply(event)
            case .frame(let found):
                model.state.apply(.frame(screenFound: found))
            case .state(let state):
                model.state.apply(.connection(state))
                model.note("connection \(state)")
                if state == .recalibrating { model.side = .calibration }
                if state == .tracking, model.side == .calibration { model.side = .words }
            case .effect(let effect):
                await model.perform(effect)
            case .preview(let image, let scale, let proposal, let quality):
                // The engine's frame is up to a second old; keep the smoother camera frame if there is one.
                if previewer?.isEnabled == true, var current = model.calibrationPreview {
                    current.proposal = proposal
                    current.quality = quality
                    model.calibrationPreview = current
                } else {
                    model.calibrationPreview = CalibrationPreview(
                        image: image, scale: scale, proposal: proposal, quality: quality)
                }
            case .calibrated(let quad, let reference):
                model.saveCalibration(
                    quad, reference: reference, deviceID: device?.id ?? "unknown", deviceName: device?.name)
                if model.side == .calibration { model.side = .words }
            case .log(let line):
                model.note(line)
            case .meter(let point):
                camera?.meterExposure(at: CGPoint(x: point.x, y: point.y))
            }
        }
    }

    /// Quiet system sounds for leaving and resuming tracking, and for needing the player.
    enum Cues {
        static func play(_ cue: ConnectionMonitor.Cue) {
            let name =
                switch cue {
                case .stoppedWatching: "Tink"
                case .resumedWatching: "Pop"
                case .needsAttention: "Glass"
                }
            guard let sound = NSSound(named: NSSound.Name(name)) else { return }
            sound.volume = 0.3
            sound.play()
        }
    }

    extension AppModel {
        /// A fresh camera frame for the calibration panel, keeping the proposed corners.
        func showPreviewFrame(_ image: CGImage, scale: Double) {
            calibrationPreview = CalibrationPreview(
                image: image, scale: scale, proposal: calibrationPreview?.proposal, quality: calibrationPreview?.quality
            )
        }

        /// Watches the TV through the iPhone instead of a recording.
        func startLive() {
            live?.stop()
            let session = LiveSession(model: self)
            live = session
            session.start()
        }

        func startLiveTranscript() {
            sessionStart = Date()
            transcript = try? TranscriptWriter(
                sessionsDirectory: store.sessionsDirectory,
                session: TranscriptWriter.sessionName(startingAt: sessionStart))
        }

        func confirmCalibration(_ quad: Quad) {
            live?.confirm(quad)
        }

        func perform(_ effect: ConnectionMonitor.Effect) async {
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
                side = .calibration
                NSApp.activate(ignoringOtherApps: true)
            case .play(let cue):
                Cues.play(cue)
            }
        }

        func saveCalibration(_ quad: Quad, reference: GrayImage, deviceID: String, deviceName: String?) {
            let formatter = ISO8601DateFormatter()
            let calibration = Calibration(
                deviceID: deviceID, deviceName: deviceName, screenQuad: quad, zoomFactor: 1,
                referenceThumbnail: "reference.pgm", calibratedAt: formatter.string(from: Date()))
            do {
                try store.save(calibration)
                try store.save(reference: reference)
                note("calibrated \(quad)")
            } catch {
                issues.append("calibration.json: \(error)")
            }
        }

        /// For testing the calibration panel without a camera: proposes corners on one video frame.
        func previewCalibration(from video: URL, at time: Double = 10) {
            Task.detached(priority: .utility) { [weak self] in
                var frame: CIImage?
                try? await Replay.forEachFrame(in: video, every: 0.5) { image, t in
                    if frame == nil, t >= time { frame = image }
                }
                guard let image = frame, let profile = try? BundledData.profile("scarlet") else { return }
                let context = CIContext()
                let candidates = (try? RectangleFinder().candidates(in: image)) ?? []
                let proposal = QuadPicker.pick(
                    candidates, near: nil, frameArea: Double(image.extent.width * image.extent.height))
                let scale = 640 / image.extent.width
                let small = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
                guard let picture = context.createCGImage(small, from: small.extent) else { return }
                let quality = proposal.map { QualityGate.report(quad: $0, profile: profile, bodyCrop: nil) }
                await MainActor.run { [weak self] in
                    self?.calibrationPreview = CalibrationPreview(
                        image: picture, scale: Double(scale), proposal: proposal, quality: quality)
                }
            }
        }
    }
#endif
