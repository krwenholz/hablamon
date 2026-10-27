#if canImport(AVFoundation) && canImport(CoreImage) && canImport(Vision)
    import AVFoundation
    import CoreImage
    import HablamonModels

    public enum ReplayError: Error, CustomStringConvertible {
        case noVideoTrack(String)
        case unreadable(String)

        public var description: String {
            switch self {
            case .noVideoTrack(let path): "no video track in \(path)"
            case .unreadable(let path): "could not read \(path)"
            }
        }
    }

    /// Runs the dialogue pipeline over a recorded video, as if it were the live camera.
    public enum Replay {
        /// Calls `onEvent` with each pipeline event and the video time it happened at.
        /// With `realTime`, frames are handed over no faster than the video plays, as if live.
        /// `onFrame` gets each sampled frame's time and whether the screen corrector found the TV.
        public static func run(
            video: URL,
            calibration: Calibration,
            profile: GameProfile,
            characters: CharacterTable,
            every interval: Double = 0.25,
            realTime: Bool = false,
            onProgress: ((_ videoTime: Double, _ frames: Int) -> Void)? = nil,
            onFrame: ((_ screenFound: Bool, _ videoTime: Double) -> Void)? = nil,
            onEvent: (PipelineEvent, Double) throws -> Void
        ) async throws {
            let corrector = ScreenCorrector(quad: calibration.screenQuad, size: profile.frameSize)
            let context = CIContext()
            let recognizer = VisionTextRecognizer()
            var pipeline = DialoguePipeline(profile: profile, characters: characters)
            var frames = 0
            try await forEachFrame(in: video, every: interval, realTime: realTime) { image, time in
                frames += 1
                if frames % 40 == 0 { onProgress?(time, frames) }
                let flat = corrector.correct(image)
                onFrame?(flat != nil, time)
                guard let flat else { return }
                let frame = CorrectedFrame(image: flat, context: context, recognizer: recognizer)
                for event in try pipeline.process(frame, at: time) {
                    try onEvent(event, time)
                }
            }
        }

        /// Decodes a video and hands over one frame per `interval` seconds, upright, with its origin at zero.
        public static func forEachFrame(
            in url: URL,
            every interval: Double,
            realTime: Bool = false,
            _ body: (CIImage, Double) throws -> Void
        ) async throws {
            let asset = AVURLAsset(url: url)
            guard let track = try await asset.loadTracks(withMediaType: .video).first else {
                throw ReplayError.noVideoTrack(url.path)
            }
            let transform = try await track.load(.preferredTransform)
            let reader = try AVAssetReader(asset: asset)
            let output = AVAssetReaderTrackOutput(
                track: track,
                outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
            )
            output.alwaysCopiesSampleData = false
            reader.add(output)
            guard reader.startReading() else { throw reader.error ?? ReplayError.unreadable(url.path) }
            var next = 0.0
            let clock = ContinuousClock()
            let start = clock.now
            defer { reader.cancelReading() }
            while let sample = output.copyNextSampleBuffer() {
                let time = CMSampleBufferGetPresentationTimeStamp(sample).seconds
                guard time + 0.001 >= next, let buffer = CMSampleBufferGetImageBuffer(sample) else { continue }
                next = time + interval
                try Task.checkCancellation()
                if realTime { try await clock.sleep(until: start + .seconds(time)) }
                var image = CIImage(cvPixelBuffer: buffer)
                if !transform.isIdentity {
                    image = image.transformed(by: transform)
                    image = image.transformed(
                        by: CGAffineTransform(translationX: -image.extent.minX, y: -image.extent.minY)
                    )
                }
                try body(image, time)
            }
            if reader.status == .failed { throw reader.error ?? ReplayError.unreadable(url.path) }
        }
    }
#endif
