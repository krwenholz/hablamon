#if canImport(CoreImage) && canImport(Vision)
    import CoreGraphics
    import CoreImage
    import Foundation
    import HablamonModels

    /// Runs the live loop on its own serial queue: takes camera frames, performs what
    /// `LiveController` asks for (OCR through the pipeline, rectangle detection, bezel thumbnails),
    /// and reports what happened. Any frame source works, so fixture videos can stand in for the camera.
    public final class LiveEngine: @unchecked Sendable {
        public enum Message: Sendable {
            case pipeline(PipelineEvent)
            /// A frame was analyzed; whether the screen could be corrected.
            case frame(screenFound: Bool)
            case state(ConnectionMonitor.State)
            case effect(ConnectionMonitor.Effect)
            /// About once a second while calibrating: a downscaled frame (`scale` preview pixels per
            /// camera pixel), the proposed corners in camera pixels, and how readable text would be.
            case preview(CGImage, scale: Double, proposal: Quad?, quality: QualityReport?)
            /// Corners confirmed; save them with this bezel reference.
            case calibrated(Quad, reference: GrayImage)
            /// Meter exposure here (0–1, top-left origin): the dialogue box.
            case meter(Point)
            /// A line for the session log (bezel differences, slow samples, frame size).
            case log(String)
        }

        private let queue = DispatchQueue(label: "hablamon.live", qos: .utility)
        private let profile: GameProfile
        private let onMessage: @Sendable (Message) -> Void
        private let start: Date
        private let context = CIContext()
        private let recognizer = VisionTextRecognizer()
        private let finder = RectangleFinder()
        private var controller: LiveController
        private var pipeline: DialoguePipeline
        private var corrector: ScreenCorrector?
        private var lastImage: CIImage?
        private var lastPreview: Date?
        private var wantsPreview = false
        private var lastState: ConnectionMonitor.State
        private let busy = NSLock()
        private var inFlight = false
        /// When the camera last delivered a frame, including ones dropped while busy. Guarded by `busy`.
        private var lastArrival: Date?
        private var loggedSize = false

        public init(
            profile: GameProfile, characters: CharacterTable, calibration quad: Quad?, reference: GrayImage?,
            settings: Settings, startingAt date: Date, onMessage: @escaping @Sendable (Message) -> Void
        ) {
            self.profile = profile
            self.onMessage = onMessage
            self.start = date
            controller = LiveController(
                calibration: quad, reference: reference,
                scheduler: SampleScheduler(
                    idleInterval: settings.idleSampleInterval, dialogueRate: settings.dialogueSampleRate),
                startingAt: date)
            pipeline = DialoguePipeline(profile: profile, characters: characters)
            lastState = controller.state
            if let quad { corrector = ScreenCorrector(quad: quad, size: profile.frameSize) }
        }

        /// The controller's state as of the last processed input.
        /// Blocks until the queue is free; for tests, not the main thread.
        public var state: ConnectionMonitor.State { queue.sync { controller.state } }

        /// Hands over a frame. Frames arriving while the last one is still being analyzed are
        /// dropped; `wait` processes synchronously, for tests.
        public func feed(_ image: CIImage, at date: Date, wait: Bool = false) {
            if wait {
                busy.withLock { lastArrival = date }
                queue.sync { process(image, at: date) }
                return
            }
            noteArrival(date)
            let accepted = busy.withLock { () -> Bool in
                if inFlight { return false }
                inFlight = true
                return true
            }
            guard accepted else { return }
            queue.async { [self] in
                process(image, at: date)
                busy.withLock { inFlight = false }
            }
        }

        /// The latest frame, flattened with the calibrated corners when there are any, for reading
        /// the whole screen.
        public func snapshot(_ completion: @escaping @Sendable (CIImage?) -> Void) {
            queue.async { [self] in
                guard let image = lastImage else { return completion(nil) }
                completion(corrector?.correct(image) ?? image)
            }
        }

        public func signal(_ signal: ConnectionMonitor.Signal, at date: Date) {
            queue.async { [self] in run(controller.handle(.camera(signal, date: date)), image: nil, at: date) }
        }

        /// Records that the camera delivered a frame, whether or not it gets analyzed.
        func noteArrival(_ date: Date) {
            busy.withLock { lastArrival = date }
        }

        public func tick(_ date: Date) {
            // Frames dropped while a slow sample was being read still prove the camera is alive,
            // so a long OCR pass doesn't look like the phone being picked up.
            let arrival = busy.withLock { lastArrival }
            queue.async { [self] in
                if let arrival {
                    run(controller.handle(.camera(.frameReceived, date: arrival)), image: nil, at: arrival)
                }
                run(controller.handle(.tick(date)), image: nil, at: date)
            }
        }

        /// The player accepted these corners on the latest frame.
        public func confirm(_ quad: Quad, at date: Date, wait: Bool = false) {
            let work: @Sendable () -> Void = { [self] in
                guard let image = lastImage,
                    let reference = try? BezelThumbnail.make(from: image, quad: quad, context: context)
                else { return }
                run(
                    controller.handle(.calibrationConfirmed(quad, reference: reference, date: date)), image: image,
                    at: date)
                onMessage(.calibrated(quad, reference: reference))
            }
            if wait { queue.sync(execute: work) } else { queue.async(execute: work) }
        }

        /// Sends previews even while tracking, as when the player opens calibration on purpose.
        public func setWantsPreview(_ on: Bool) {
            queue.async { [self] in
                wantsPreview = on
                lastPreview = nil
            }
        }

        public func updateCharacters(_ table: CharacterTable) {
            queue.async { [self] in pipeline.updateCharacters(table) }
        }

        // MARK: On the queue

        private func process(_ image: CIImage, at date: Date) {
            if !loggedSize {
                loggedSize = true
                onMessage(.log("first frame \(Int(image.extent.width))×\(Int(image.extent.height))"))
            }
            lastImage = image
            let time = date.timeIntervalSince(start)
            run(
                controller.handle(.frame(time: time, date: date, inDialogue: pipeline.wantsFastSampling)), image: image,
                at: date)
            sendPreviewIfDue(image, at: date)
        }

        private func run(_ outputs: [LiveOutput], image: CIImage?, at date: Date) {
            for output in outputs {
                switch output {
                case .process(let time):
                    guard let image, let corrector else { continue }
                    let flat = corrector.correct(image)
                    onMessage(.frame(screenFound: flat != nil))
                    guard let flat else { continue }
                    let frame = CorrectedFrame(image: flat, context: context, recognizer: recognizer)
                    let started = ContinuousClock.now
                    do {
                        for event in try pipeline.process(frame, at: time) { onMessage(.pipeline(event)) }
                    } catch {
                        onMessage(.log("pipeline error: \(error)"))
                    }
                    let elapsed = (ContinuousClock.now - started) / .seconds(1)
                    if elapsed > 0.5 { onMessage(.log(String(format: "slow sample: %.2f s", elapsed))) }
                case .findRectangles:
                    guard let image, let candidates = try? finder.candidates(in: image) else { continue }
                    let area = Double(image.extent.width * image.extent.height)
                    run(controller.handle(.rectangles(candidates, frameArea: area, date: date)), image: image, at: date)
                case .checkBezel(let quad):
                    guard let image, let thumbnail = try? BezelThumbnail.make(from: image, quad: quad, context: context)
                    else { continue }
                    let next = controller.handle(.bezel(quad: quad, thumbnail: thumbnail, date: date))
                    if let difference = controller.lastBezelDifference {
                        onMessage(.log(String(format: "bezel %.3f (%@)", difference, "\(controller.state)")))
                    }
                    run(next, image: image, at: date)
                case .useQuad(let quad):
                    corrector = ScreenCorrector(quad: quad, size: profile.frameSize)
                    if let image {
                        onMessage(
                            .meter(
                                QualityGate.meteringPoint(
                                    quad: quad, profile: profile, cameraWidth: Double(image.extent.width),
                                    cameraHeight: Double(image.extent.height))))
                    }
                case .effect(let effect):
                    if effect == .stopPipeline { pipeline.reset() }
                    onMessage(.effect(effect))
                }
            }
            if controller.state != lastState {
                lastState = controller.state
                onMessage(.state(controller.state))
            }
        }

        private func sendPreviewIfDue(_ image: CIImage, at date: Date) {
            guard wantsPreview || controller.state != .tracking else { return }
            if let lastPreview, date.timeIntervalSince(lastPreview) < 1 { return }
            lastPreview = date
            let scale = 640 / image.extent.width
            let small = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            guard let picture = context.createCGImage(small, from: small.extent) else { return }
            let proposal = controller.proposal ?? controller.quad
            let quality = proposal.map { quad -> QualityReport in
                var body: RGBAImage?
                if let flat = ScreenCorrector(quad: quad, size: profile.frameSize).correct(image) {
                    body = try? CorrectedFrame(image: flat, context: context, recognizer: recognizer)
                        .rgba(profile.regions.bodyText, profile)
                }
                return QualityGate.report(quad: quad, profile: profile, bodyCrop: body)
            }
            onMessage(.preview(picture, scale: Double(scale), proposal: proposal, quality: quality))
        }
    }
#endif
