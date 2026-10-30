# Spike C: Hablamon on the iPhone

Oct 28, 2026 · research only, nothing built · questions for Kyle at the end

## The idea

Today the iPhone is only a camera: Continuity Camera streams it to the Mac, and the Mac does everything else. An iOS app would move the whole pipeline onto the phone. It points its back camera at the TV, reads each box, and speaks it, and the screen facing the player shows the line and its translation. No Mac during play.

The goal is a personal build on Kyle's own phone, not an App Store release. That's much simpler: no review, no store listing, no privacy questionnaire. You do still need Xcode on a Mac and an Apple ID to sign the app.

## What a personal build involves

iOS only runs signed apps. For an app you build yourself, Xcode signs it with a *development* certificate and a *provisioning profile* that lists which devices may run it. Xcode handles both automatically when you tick "Automatically manage signing". The only choice is which account signs.

| | Free Apple ID ("Personal Team") | Apple Developer Program ($99/year) |
| --- | --- | --- |
| How it installs | Xcode → Run, phone on a cable (or Wi-Fi after pairing once) | Same, or over the air with TestFlight |
| How long it runs | **7 days**, then the app won't launch until you rebuild and run it from Xcode again | 1 year for a development build; 90 days for a TestFlight build |
| Limits | 3 apps per device, 10 app IDs per week | None that matter here |
| Install without a Mac at hand | No | Yes: TestFlight. CI could build and upload, and Kyle installs from the phone |
| Extra capabilities (e.g. the increased memory limit, below) | Some aren't available; unclear for this one | All |

**Recommendation:** start free. If the 7-day rebuilds get annoying, or the voice model needs the memory entitlement, pay for the program then. Nothing in the code depends on which account signs.

### First run, step by step

1. **Install full Xcode** from the App Store on the Mac. The Command Line Tools alone can't sign or install iOS apps. The Mac may already have it, since the voices install uses `xcodebuild`.
2. **Xcode › Settings › Accounts**: add the Apple ID. A "Personal Team" appears.
3. **Plug the iPhone in** and tap "Trust This Computer". Xcode may take a few minutes to prepare the phone the first time.
4. **Turn on Developer Mode** on the iPhone: Settings › Privacy & Security › Developer Mode (iOS 16+). The phone restarts. The setting only shows up after the phone has been connected to Xcode.
5. **Open the project, choose the team, choose the phone, and press Run.** The first launch is blocked until the developer certificate is trusted under Settings › General › VPN & Device Management.
6. Optional: in Xcode's Devices window, tick "Connect via network" so later installs don't need the cable.

From the terminal, roughly the same steps can be a mise task. `xcodebuild -allowProvisioningUpdates` builds and signs, and `xcrun devicectl device install app` installs on the phone. A `mise run install-phone` would mirror `mise run install`.

## How much of the code carries over

Most of it. The pipeline is plain Swift on Apple frameworks that also exist on iOS.

| Area | On iOS | Work |
| --- | --- | --- |
| `HablamonModels`, transcript, vocab, speakers, settle, box detection, page sequencing | Platform-neutral | None |
| Vision OCR, Core Image correction, NaturalLanguage, `Translation` | Same APIs (iOS 18) | None expected; check the Translation download prompt |
| Apple speech (`AVSpeechSynthesizer`) | Same | Set an `AVAudioSession` (`.playback`) so it speaks with the silent switch on |
| Replay from a video file | Works, and is the only way to test in the Simulator, which has no camera | Pick the file with `fileImporter` instead of `--replay` |
| Camera (`LiveCamera`) | Different, and **better**: iOS gives full control of the back cameras | New `PhoneCamera` (below) |
| Window, panels, `AppModel` | SwiftUI, but laid out for a 1470-pt Mac window | New compact layout; shared state moves into a library |
| AppKit bits: `NSEvent` keys, `NSSound`, `NSOpenPanel`, `MenuBarExtra`, full-screen window | Not on iOS | Taps and buttons (or a Bluetooth keyboard via `.onKeyPress`), `AudioServices` chimes, `fileImporter` |
| Data folder (`AppSupportStore`) | `homeDirectoryForCurrentUser` doesn't exist on iOS | Use `FileManager.url(for: .applicationSupportDirectory, …)` on both platforms; expose transcripts and logs in the Files app |
| Qwen3 voices (`HablamonVoices`) | speech-swift supports iOS 18 | Unproven on a phone: see Voices |

### The camera gets better

The [M2 record](done/m2-live-camera.md) notes that macOS can't set exposure bias or zoom on the phone. All it can do is meter on the dialogue box. A native iOS app has the whole `AVCaptureDevice` API:

- **Exposure bias and lock**, so the bright box doesn't blow out.
- **Zoom and lens choice.** With the telephoto lens the phone can sit beside the player and still fill the frame with the TV. That makes the phone screen readable and the phone easy to reach.
- **Focus lock** on the TV, so it doesn't hunt.
- **No Continuity rules.** The phone doesn't have to be locked, and it can't drop off the Mac's camera list. Instead the app must stay in front (iOS stops the camera in the background), keep the screen awake (`isIdleTimerDisabled`), and handle session interruptions such as a phone call. These map onto the existing `ConnectionMonitor` signals.

Calibration, the bezel check, and recovery stay as they are: the phone can still be bumped.

### Voices

| Option | On iPhone | Notes |
| --- | --- | --- |
| Apple voices | Works today | Download the Enhanced es-ES voices on the phone too |
| Qwen3-TTS 0.6B clone (today's engine) | speech-swift lists iOS 18, but publishes no iPhone numbers for Qwen3-TTS | About 1 GB of weights on the GPU, next to the camera and Vision. Probably slower than the Air, which already misses the 1.5 s budget without streaming. May need the [increased memory limit](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.kernel.increased-memory-limit) entitlement. Measure, don't assume |
| Kokoro-82M (speech-swift, CoreML) | Measured by speech-swift at RTF 0.08 on an iPhone 16 Pro, 676 MB peak | Fast, but a few fixed Spanish voices rather than one per character |

One upside: an Xcode build compiles MLX's Metal shaders itself, so the `build-metallib.sh` workaround the Mac install needs goes away.

### Heat and battery

The phone would run the camera, the screen, Vision, and possibly a GPU voice model for hours, while charging. That's the biggest unknown. The sampling is already light (every 2 s when idle, 4 per second in dialogue). Watching `ProcessInfo.thermalState` and slowing down, or falling back to Apple voices, when it reaches `.serious` is cheap insurance.

## Repo changes

1. **An Xcode project, small on purpose.** SwiftPM alone can't produce an iOS app bundle. A tiny project (say `Apps/HablamonPhone.xcodeproj`) holds just the app target, Info.plist (camera usage string), and signing settings, and it depends on the local package. All code stays in the package. This breaks the AGENTS.md rule "SwiftPM only, no Xcode project", so the rule would change to "SwiftPM for all code; one thin Xcode project for the iOS shell". Alternatives: generate the project with XcodeGen (a new tool, needs a yes), or a Swift Playgrounds `.swiftpm` app package (no project file, but fewer build settings and odder tooling).
2. **`Package.swift`:** add `.iOS(.v18)` to `platforms`. Move `AppModel` and the platform-neutral panels from the `HablamonApp` executable into a `HablamonUI` library, so the Mac app and the phone app share them. Add `.iOS` to the speech-swift platform conditions once the voices are tried on the phone.
3. **`#if os(macOS)` / `#if os(iOS)`** around the camera and the AppKit pieces. Behind protocols, `LiveCamera` and `PhoneCamera` look the same to `LiveEngine`.
4. **CI:** an iOS Simulator build job (`xcodebuild -sdk iphonesimulator`, no signing) with a `timeout-minutes`, so the phone target doesn't silently rot. It runs on paid macOS minutes, so build only and leave tests to the existing job.
5. **Cloud sessions** (Linux) can still build and test everything platform-neutral. The iOS shell, like the Mac app today, only builds on the Mac.

## Proposed spike, in steps

Each step ends with something Kyle can try on the phone.

1. **Hello, phone** (half a day). The thin Xcode project, signed with the free team. It shows the back camera full screen with zoom and exposure-bias sliders and reports what OCR reads in a fixed box. Answers: does signing work, can the telephoto lens read the box from the couch, does exposure bias fix blow-out?
2. **Pipeline on the phone.** `LiveEngine` running on `PhoneCamera` with calibration and Apple voices, showing the current line in large text. Answers: is it accurate, and how warm does the phone get after 30 minutes?
3. **Voices.** Qwen3 clone and Kokoro on the phone, timing settle-to-first-audio and peak memory, and checking whether the memory entitlement is needed. Decide on the engine and on the paid program.
4. **Companion layout.** The line, its English, and key words sized for a phone at arm's length; the recap behind a swipe or button.

Steps 1–2 decide whether this is worth more than a curiosity. If they go well, write the plan as a milestone and record this spike in `done/`.

## Questions for Kyle

1. Which iPhone (model and iOS version)? A Pro has the telephoto lens and 8 GB of RAM, which matters for both the camera and the voices. Is there an iPad you'd use instead? It has a bigger screen but usually a weaker camera.
2. Where would the phone sit: by the TV (as now), or next to you using the telephoto lens?
3. Is Xcode installed on the Mac, and are you OK with one thin Xcode project in the repo (an exception to "SwiftPM only")?
4. Free account with weekly rebuilds to start, or pay $99/year straight away for TestFlight and installs without the Mac?
5. Should the Mac app stay the main one, with the phone as an experiment? Or is the goal to replace it?

## Sources

- [Apple: choosing a membership](https://developer.apple.com/support/compare-memberships/) (free-team limits: 7-day profiles, 3 apps per device, 10 app IDs)
- [Apple Developer Forums: limits on apps deployed with a free account](https://developer.apple.com/forums/thread/724896)
- [Free-team iOS signing notes](https://takazudo-zudo-tauri.pages.dev/pj/zudo-tauri/docs/mobile/ios-signing-free-team)
- [Increased memory limit entitlement](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.kernel.increased-memory-limit), and [Apple DTS on entitlements needing a provisioning profile](https://developer.apple.com/forums/thread/740831)
- [speech-swift](https://github.com/soniqo/speech-swift) README (macOS 15 / iOS 18) and its [iPhone CoreML benchmarks](https://github.com/soniqo/speech-swift/blob/main/docs/benchmarks/ios-coreml.md)
