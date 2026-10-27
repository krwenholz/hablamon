#if canImport(AVFoundation) && canImport(CoreImage)
    @preconcurrency import AVFoundation
    import CoreImage
    import Foundation

    /// Captures from the pinned camera (the iPhone via Continuity Camera) and reports frames and
    /// camera events. Never switches devices on its own; if the pinned one goes away it reports
    /// `.cameraDisconnected` and waits for it to come back.
    public final class LiveCamera: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
        public enum Failure: Error, CustomStringConvertible {
            case notAuthorized
            case deviceMissing(String)
            case cannotAddInput

            public var description: String {
                switch self {
                case .notAuthorized: "camera access was denied (System Settings › Privacy › Camera)"
                case .deviceMissing(let id): "camera \(id) isn't connected"
                case .cannotAddInput: "the camera couldn't be opened"
                }
            }
        }

        /// Called on a background queue with each frame, upright, and when it arrived.
        public var onFrame: (@Sendable (CIImage, Date) -> Void)?
        /// Called with suspension and connection changes.
        public var onSignal: (@Sendable (ConnectionMonitor.Signal, Date) -> Void)?

        private let session = AVCaptureSession()
        private let queue = DispatchQueue(label: "hablamon.camera", qos: .utility)
        private var device: AVCaptureDevice?
        private var deviceID: String?
        private var suspension: NSKeyValueObservation?
        private var observers: [NSObjectProtocol] = []

        /// Cameras the Mac can see now.
        public static func available() -> [CameraInfo] {
            let discovery = AVCaptureDevice.DiscoverySession(
                deviceTypes: [.continuityCamera, .builtInWideAngleCamera, .external], mediaType: .video,
                position: .unspecified)
            return discovery.devices.map { device in
                let kind: CameraInfo.Kind =
                    switch device.deviceType {
                    case .continuityCamera: .continuity
                    case .builtInWideAngleCamera: .builtIn
                    default: .external
                    }
                return CameraInfo(id: device.uniqueID, name: device.localizedName, kind: kind)
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

        public func start(deviceID: String) throws {
            guard AVCaptureDevice.authorizationStatus(for: .video) == .authorized else { throw Failure.notAuthorized }
            guard let device = AVCaptureDevice(uniqueID: deviceID) else { throw Failure.deviceMissing(deviceID) }
            self.deviceID = deviceID
            try configure(device)
            watchConnections()
            queue.async { [session] in session.startRunning() }
        }

        public func stop() {
            queue.async { [session] in session.stopRunning() }
            suspension = nil
            for observer in observers { NotificationCenter.default.removeObserver(observer) }
            observers = []
        }

        /// Meters exposure on this point (0–1, top-left origin) — the dialogue box, so the phone
        /// exposes for the bright box instead of blowing it out. macOS has no exposure bias or zoom
        /// for capture devices, so this is the one lever.
        public func meterExposure(at point: CGPoint) {
            guard let device, device.isExposurePointOfInterestSupported,
                device.isExposureModeSupported(.continuousAutoExposure),
                (try? device.lockForConfiguration()) != nil
            else { return }
            device.exposurePointOfInterest = point
            device.exposureMode = .continuousAutoExposure
            device.unlockForConfiguration()
        }

        private func configure(_ device: AVCaptureDevice) throws {
            session.beginConfiguration()
            defer { session.commitConfiguration() }
            for input in session.inputs { session.removeInput(input) }
            for output in session.outputs { session.removeOutput(output) }
            if session.canSetSessionPreset(.hd1920x1080) { session.sessionPreset = .hd1920x1080 }
            let input = try AVCaptureDeviceInput(device: device)
            guard session.canAddInput(input) else { throw Failure.cannotAddInput }
            session.addInput(input)
            let output = AVCaptureVideoDataOutput()
            output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
            // Only the newest frame matters; the app samples a few per second at most.
            output.alwaysDiscardsLateVideoFrames = true
            output.setSampleBufferDelegate(self, queue: queue)
            if session.canAddOutput(output) { session.addOutput(output) }
            self.device = device
            suspension = device.observe(\.isSuspended, options: [.new]) { [weak self] device, _ in
                self?.onSignal?(device.isSuspended ? .cameraSuspended : .cameraResumed, Date())
            }
        }

        private func watchConnections() {
            let center = NotificationCenter.default
            for observer in observers { center.removeObserver(observer) }
            observers = [
                center.addObserver(forName: AVCaptureDevice.wasDisconnectedNotification, object: nil, queue: nil) {
                    [weak self] note in
                    guard let self, (note.object as? AVCaptureDevice)?.uniqueID == self.deviceID else { return }
                    self.onSignal?(.cameraDisconnected, Date())
                },
                center.addObserver(forName: AVCaptureDevice.wasConnectedNotification, object: nil, queue: nil) {
                    [weak self] note in
                    guard let self, let device = note.object as? AVCaptureDevice, device.uniqueID == self.deviceID
                    else { return }
                    // The old input is dead once the device disconnects; rebuild the session on it.
                    try? self.configure(device)
                    self.queue.async { [session = self.session] in
                        if !session.isRunning { session.startRunning() }
                    }
                    self.onSignal?(.cameraReconnected, Date())
                },
            ]
        }

        public func captureOutput(
            _ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection
        ) {
            guard let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
            onFrame?(CIImage(cvPixelBuffer: buffer), Date())
        }
    }
#endif
