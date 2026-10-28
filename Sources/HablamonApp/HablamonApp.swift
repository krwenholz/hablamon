#if canImport(SwiftUI) && canImport(AVFoundation)
    import AppKit
    import HablamonCore
    import SwiftUI
    import UniformTypeIdentifiers

    /// Launch options, read from the command line:
    /// `--replay <video> [--calibration <file>]` plays a recording as if live;
    /// `--camera mac` watches through the Mac's own camera instead of the iPhone;
    /// `--translate-image <file>` opens the whole-screen translation on a picture;
    /// `--windowed` skips full screen; `--mute` starts with speech paused; `--root <dir>` uses another
    /// data folder instead of Application Support; `--panel speakers|diagnostics` opens that panel;
    /// `--snapshot <png> --after <seconds>` saves the window and quits.
    struct LaunchOptions {
        var replay: URL?
        var calibration: URL?
        var windowed = false
        var mute = false
        var camera: CameraSource = .iphone
        var translateImage: URL?
        var root: URL?
        var panel: SidePanel = .words
        var snapshot: URL?
        var snapshotDelay = 20.0

        init(arguments: [String] = CommandLine.arguments) {
            var iterator = arguments.dropFirst().makeIterator()
            while let argument = iterator.next() {
                switch argument {
                case "--replay": replay = iterator.next().map { URL(fileURLWithPath: $0) }
                case "--calibration": calibration = iterator.next().map { URL(fileURLWithPath: $0) }
                case "--windowed": windowed = true
                case "--mute": mute = true
                case "--camera": camera = iterator.next().flatMap(CameraSource.init(rawValue:)) ?? camera
                case "--translate-image": translateImage = iterator.next().map { URL(fileURLWithPath: $0) }
                case "--root": root = iterator.next().map { URL(fileURLWithPath: $0, isDirectory: true) }
                case "--panel": panel = iterator.next().flatMap(SidePanel.init(rawValue:)) ?? panel
                case "--snapshot": snapshot = iterator.next().map { URL(fileURLWithPath: $0) }
                case "--after": snapshotDelay = iterator.next().flatMap(Double.init) ?? snapshotDelay
                default: break
                }
            }
        }

        /// `<name>.calibration.json` next to the video.
        static func calibration(besides video: URL) -> URL {
            video.deletingPathExtension().appendingPathExtension("calibration.json")
        }
    }

    final class AppDelegate: NSObject, NSApplicationDelegate {
        func applicationDidFinishLaunching(_ notification: Notification) {
            // A SwiftPM executable starts as a background process; make it a normal app with a Dock icon.
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
        }

        func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    }

    @main
    struct HablamonApp: App {
        @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
        @State private var model: AppModel
        private let options: LaunchOptions

        init() {
            let options = LaunchOptions()
            self.options = options
            _model = State(
                initialValue: AppModel(store: options.root.map(AppSupportStore.init(root:)) ?? AppSupportStore()))
        }

        var body: some Scene {
            Window("Hablamon", id: "main") {
                MainWindow(model: model)
                    .task { await start() }
            }
            .defaultSize(width: 1470, height: 956)

            MenuBarExtra {
                Text(text(model.state.pill, english: model.english))
                Button(model.paused ? "Reanudar" : "Pausa") { model.togglePause() }
                Button("Abrir ventana") { NSApp.activate(ignoringOtherApps: true) }
                Button(text(.recalibrate, english: false)) { model.recalibrate() }
                if model.source != nil || model.liveStatus != nil {
                    Button(model.cameraSource == .iphone ? "Usar la cámara del Mac" : "Usar el iPhone") {
                        model.useCamera(model.cameraSource == .iphone ? .mac : .iphone)
                    }
                }
                if !model.state.unknownSpeakers.isEmpty {
                    Button(unassignedVoices(model.state.unknownSpeakers.count, english: false)) {
                        model.side = .speakers
                        NSApp.activate(ignoringOtherApps: true)
                    }
                }
                Divider()
                Button("Salir") { NSApp.terminate(nil) }
            } label: {
                // A filled dot while unknown speakers wait for a voice.
                Image(systemName: model.state.unknownSpeakers.isEmpty ? "bubble.left" : "bubble.left.fill")
            }
            .commands {
                CommandGroup(after: .newItem) {
                    Button("Abrir grabación…") { openRecording() }.keyboardShortcut("o")
                }
            }
        }

        @MainActor private func start() async {
            model.installKeyHandler()
            if !options.windowed, let window = NSApp.windows.first, !window.styleMask.contains(.fullScreen) {
                window.toggleFullScreen(nil)
            }
            if options.mute { model.paused = true }
            model.side = options.panel
            if let file = options.translateImage {
                model.openScreen(file: file)
            } else if let video = options.replay {
                if options.panel == .calibration {
                    model.previewCalibration(from: video)
                } else {
                    model.startReplay(
                        video: video, calibration: options.calibration ?? LaunchOptions.calibration(besides: video))
                }
            } else {
                model.cameraSource = options.camera
                model.startLive()
            }
            if let snapshot = options.snapshot {
                try? await Task.sleep(for: .seconds(options.snapshotDelay))
                saveSnapshot(to: snapshot)
                NSApp.terminate(nil)
            }
        }

        @MainActor private func openRecording() {
            let panel = NSOpenPanel()
            panel.allowedContentTypes = [.movie, .mpeg4Movie, .quickTimeMovie]
            panel.message = "Elige un vídeo; su calibración debe estar al lado (<nombre>.calibration.json)."
            guard panel.runModal() == .OK, let video = panel.url else { return }
            model.startReplay(video: video, calibration: LaunchOptions.calibration(besides: video))
        }

        /// Renders the window's content to a PNG without needing screen-recording permission.
        @MainActor private func saveSnapshot(to url: URL) {
            guard let view = NSApp.windows.first?.contentView,
                let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds)
            else { return }
            view.cacheDisplay(in: view.bounds, to: bitmap)
            try? bitmap.representation(using: .png, properties: [:])?.write(to: url)
        }
    }
#else
    // The app is macOS-only. This stub keeps `swift build` working on Linux.
    @main
    enum HablamonApp {
        static func main() {
            print("Hablamon.app requires macOS.")
        }
    }
#endif
