#if canImport(SwiftUI)
    import SwiftUI

    @main
    struct HablamonApp: App {
        var body: some Scene {
            WindowGroup {
                Text("Hablamon")
                    .padding()
            }
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
