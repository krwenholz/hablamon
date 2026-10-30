#if os(iOS)
    @preconcurrency import AVFoundation
    import CoreImage
    import Foundation

    /// Captures from one of the iPhone's own back cameras, for running Hablamon on the phone itself.
    /// It reports frames and camera events like `LiveCamera` does on the Mac, but here the app
    /// controls the lens, zoom, exposure bias, and focus. Frames arrive upright however the phone is
    /// held; interruptions (the app leaving the screen, a call) report as suspension.
    public final class PhoneCamera: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
        public enum Failure: Error, CustomStringConvertible {
            case notAuthorized
            case noCamera
            case cannotAddInput

            public var description: String {
                switch self {
                case .notAuthorized: "camera access was denied (Settings › Hablamon › Camera)"
                case .noCamera: "no back camera found"
                case .cannotAddInput: "the camera couldn't be opened"
                }
            }
        }

        /// What the camera controls show and can set. Zoom is the lens's own factor (1 = none).
        public struct Controls: Equatable, Sendable {
            public var zoom = 1.0
            public var maxZoom = 1.0
            public var exposureBias = 0.0
            public var minBias = 0.0
            public var maxBias = 0.0
            public var focusLocked = false

            public init() {}
        }

        /// The engine samples at most four frames a second; fewer frames save power.
        public static let frameRate = 15
        /// Digital zoom past this only magnifies noise.
        public static let zoomLimit = 10.0

        /// Called on a background queue with each frame, upright, and when it arrived.
        public var onFrame: (@Sendable (CIImage, Date) -> Void)?
        /// Called with suspension changes.
        public var onSignal: (@Sendable (ConnectionMonitor.Signal, Date) -> Void)?
        /// Called with lines worth keeping in the session log.
        public var onLog: (@Sendable (String) -> Void)?

        // The session, device, and rotation belong to `queue`; `observers` to the caller of start/stop.
        private let session = AVCaptureSession()
        private let output = AVCaptureVideoDataOutput()
        private let queue = DispatchQueue(label: "hablamon.phone-camera", qos: .utility)
        private var device: AVCaptureDevice?
        private var coordinator: AVCaptureDevice.RotationCoordinator?
        private var rotationObservation: NSKeyValueObservation?
        private var rotation = 0.0
        private var observers: [NSObjectProtocol] = []

        private static let lensTypes: [AVCaptureDevice.DeviceType] = [
            .builtInUltraWideCamera, .builtInWideAngleCamera, .builtInTelephotoCamera,
        ]

        private static func backCameras() -> [AVCaptureDevice] {
            AVCaptureDevice.DiscoverySession(deviceTypes: lensTypes, mediaType: .video, position: .back).devices
        }

        /// The phone's physical back cameras, widest first. A fixed lens rather than the virtual
        /// multi-camera, so the phone never switches lenses on its own, which would look like it moved.
        public static func lenses() -> [PhoneLens] {
            let devices = backCameras()
            let main = devices.first { $0.deviceType == .builtInWideAngleCamera }
            return devices.map { device in
                let magnification =
                    main.map {
                        PhoneLens.magnification(
                            fieldOfView: Double(device.activeFormat.videoFieldOfView),
                            mainFieldOfView: Double($0.activeFormat.videoFieldOfView))
                    } ?? 1
                return PhoneLens(id: device.uniqueID, magnification: magnification)
            }
            .sorted { $0.magnification < $1.magnification }
        }

        public static var authorizationDescription: String {
            switch AVCaptureDevice.authorizationStatus(for: .video) {
            case .authorized: "authorized"
            case .notDetermined: "not asked yet"
            case .denied: "denied"
            case .restricted: "restricted"
            @unknown default: "unknown"
            }
        }

        /// Asks for camera access if it hasn't been decided yet.
        public static func authorize() async -> Bool {
            switch AVCaptureDevice.authorizationStatus(for: .video) {
            case .authorized: true
            case .notDetermined: await AVCaptureDevice.requestAccess(for: .video)
            default: false
            }
        }

        /// Starts on the lens with this ID, or the main camera.
        public func start(lensID: String?) throws {
            guard AVCaptureDevice.authorizationStatus(for: .video) == .authorized else { throw Failure.notAuthorized }
            let device = try Self.camera(lensID)
            try queue.sync { try configure(device) }
            watchInterruptions()
            queue.async { [session] in session.startRunning() }
        }

        public func stop() {
            queue.async { [self] in
                session.stopRunning()
                rotationObservation = nil
                coordinator = nil
            }
            for observer in observers { NotificationCenter.default.removeObserver(observer) }
            observers = []
        }

        /// Switches to another lens while running.
        public func useLens(_ id: String) throws {
            let device = try Self.camera(id)
            try queue.sync { try configure(device) }
        }

        /// The current zoom, bias, and focus, with their limits.
        public func controls() -> Controls {
            queue.sync {
                var controls = Controls()
                guard let device else { return controls }
                controls.zoom = Double(device.videoZoomFactor)
                controls.maxZoom = min(Double(device.maxAvailableVideoZoomFactor), Self.zoomLimit)
                controls.exposureBias = Double(device.exposureTargetBias)
                controls.minBias = Double(device.minExposureTargetBias)
                controls.maxBias = Double(device.maxExposureTargetBias)
                controls.focusLocked = device.focusMode == .locked
                return controls
            }
        }

        public func setZoom(_ factor: Double) {
            adjust("zoom") { device in
                let limit = min(Double(device.maxAvailableVideoZoomFactor), Self.zoomLimit)
                device.videoZoomFactor = CGFloat(min(max(factor, Double(device.minAvailableVideoZoomFactor)), limit))
            }
        }

        /// Brighter (positive) or darker (negative) than auto exposure, in stops. Negative keeps the
        /// bright dialogue box from blowing out.
        public func setExposureBias(_ bias: Double) {
            adjust("exposure bias") { device in
                let clamped = min(max(Float(bias), device.minExposureTargetBias), device.maxExposureTargetBias)
                device.setExposureTargetBias(clamped, completionHandler: nil)
            }
        }

        /// Locks focus where it is now (on the TV), or goes back to autofocus.
        public func setFocusLocked(_ locked: Bool) {
            adjust("focus") { device in
                if locked, device.isFocusModeSupported(.locked) {
                    device.focusMode = .locked
                } else if device.isFocusModeSupported(.continuousAutoFocus) {
                    device.focusMode = .continuousAutoFocus
                }
            }
        }

        /// Meters exposure on this point of the upright frame (0–1, top-left origin): the dialogue box.
        public func meterExposure(at point: CGPoint) {
            queue.async { [self] in
                let sensor = PhoneLens.sensorPoint(x: Double(point.x), y: Double(point.y), rotation: rotation)
                guard let device, device.isExposurePointOfInterestSupported,
                    device.isExposureModeSupported(.continuousAutoExposure),
                    (try? device.lockForConfiguration()) != nil
                else {
                    onLog?("exposure point not supported")
                    return
                }
                device.exposurePointOfInterest = CGPoint(x: sensor.x, y: sensor.y)
                device.exposureMode = .continuousAutoExposure
                device.unlockForConfiguration()
                onLog?(String(format: "metering exposure at %.2f, %.2f", point.x, point.y))
            }
        }

        // MARK: On the queue

        private static func camera(_ id: String?) throws -> AVCaptureDevice {
            let devices = backCameras()
            guard
                let device = devices.first(where: { $0.uniqueID == id })
                    ?? devices.first(where: { $0.deviceType == .builtInWideAngleCamera }) ?? devices.first
            else { throw Failure.noCamera }
            return device
        }

        private func configure(_ device: AVCaptureDevice) throws {
            session.beginConfiguration()
            do {
                for input in session.inputs { session.removeInput(input) }
                if session.canSetSessionPreset(.hd1920x1080) { session.sessionPreset = .hd1920x1080 }
                let input = try AVCaptureDeviceInput(device: device)
                guard session.canAddInput(input) else { throw Failure.cannotAddInput }
                session.addInput(input)
                if session.outputs.isEmpty {
                    output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
                    // Only the newest frame matters; the engine samples a few per second at most.
                    output.alwaysDiscardsLateVideoFrames = true
                    output.setSampleBufferDelegate(self, queue: queue)
                    if session.canAddOutput(output) { session.addOutput(output) }
                }
                // Stabilization crops and shifts the picture, which the bezel check would read as movement.
                if let connection = output.connection(with: .video), connection.isVideoStabilizationSupported {
                    connection.preferredVideoStabilizationMode = .off
                }
            } catch {
                session.commitConfiguration()
                throw error
            }
            session.commitConfiguration()
            self.device = device
            // After the commit: the session preset resets the frame rate.
            if (try? device.lockForConfiguration()) != nil {
                let rate = Double(Self.frameRate)
                if device.activeFormat.videoSupportedFrameRateRanges.contains(where: {
                    $0.minFrameRate <= rate && rate <= $0.maxFrameRate
                }) {
                    let duration = CMTime(value: 1, timescale: CMTimeScale(Self.frameRate))
                    device.activeVideoMinFrameDuration = duration
                    device.activeVideoMaxFrameDuration = duration
                }
                device.unlockForConfiguration()
            }
            followRotation(of: device)
            onLog?("phone camera \(device.localizedName) (\(device.deviceType.rawValue))")
        }

        /// Keeps frames upright for however the phone is held.
        private func followRotation(of device: AVCaptureDevice) {
            let coordinator = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: nil)
            self.coordinator = coordinator
            applyRotation(Double(coordinator.videoRotationAngleForHorizonLevelCapture))
            rotationObservation = coordinator.observe(\.videoRotationAngleForHorizonLevelCapture, options: [.new]) {
                [weak self] coordinator, _ in
                guard let self else { return }
                let angle = Double(coordinator.videoRotationAngleForHorizonLevelCapture)
                queue.async { self.applyRotation(angle) }
            }
        }

        private func applyRotation(_ angle: Double) {
            guard let connection = output.connection(with: .video),
                connection.isVideoRotationAngleSupported(CGFloat(angle))
            else { return }
            connection.videoRotationAngle = CGFloat(angle)
            if angle != rotation { onLog?("camera rotation \(Int(angle))°") }
            rotation = angle
        }

        /// Runs on `adjust`'s caller; the change itself happens on the queue.
        private func adjust(_ what: String, _ change: @escaping @Sendable (AVCaptureDevice) -> Void) {
            queue.async { [self] in
                guard let device, (try? device.lockForConfiguration()) != nil else {
                    onLog?("couldn't adjust \(what)")
                    return
                }
                change(device)
                device.unlockForConfiguration()
            }
        }

        private func watchInterruptions() {
            let center = NotificationCenter.default
            for observer in observers { center.removeObserver(observer) }
            observers = [
                center.addObserver(forName: AVCaptureSession.wasInterruptedNotification, object: session, queue: nil) {
                    [weak self] note in
                    let reason = (note.userInfo?[AVCaptureSessionInterruptionReasonKey] as? NSNumber)?.intValue
                    self?.onLog?("camera interrupted (reason \(reason.map(String.init) ?? "unknown"))")
                    self?.onSignal?(.cameraSuspended, Date())
                },
                center.addObserver(
                    forName: AVCaptureSession.interruptionEndedNotification, object: session, queue: nil
                ) { [weak self] _ in
                    self?.onLog?("camera resumed")
                    self?.onSignal?(.cameraResumed, Date())
                },
                center.addObserver(forName: AVCaptureSession.runtimeErrorNotification, object: session, queue: nil) {
                    [weak self] note in
                    let error = note.userInfo?[AVCaptureSessionErrorKey] as? NSError
                    self?.onLog?("camera error: \(error.map { "\($0.code) \($0.localizedDescription)" } ?? "unknown")")
                    self?.restart()
                },
            ]
        }

        private func restart() {
            queue.async { [self] in
                if !session.isRunning { session.startRunning() }
            }
        }

        public func captureOutput(
            _ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection
        ) {
            guard let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
            onFrame?(CIImage(cvPixelBuffer: buffer), Date())
        }
    }
#endif
