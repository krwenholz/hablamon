# Hablamon on the iPhone

Oct 30, 2026 · @Kyle · phases 0–2 built (not yet compiled for iOS or run on a phone); the rest planned · research in [done/spike-c-ios.md](done/spike-c-ios.md)

## Goal

Run the whole of Hablamon on the iPhone: its back camera watches the TV, and it reads each box aloud in the character's Kokoro voice and shows the line with its English translation. No Mac during play. The Mac app keeps working, and both apps share one codebase. This is a personal build on Kyle's phone, not an App Store app.

**Why now:** Kokoro made the voices light enough for a phone. speech-swift [measures Kokoro at 0.08× real time on an iPhone 16 Pro](https://github.com/soniqo/speech-swift/blob/main/docs/benchmarks/ios-coreml.md), against about 1 GB and a GPU for Qwen3. A native iOS app also gets what the Mac can't get through Continuity Camera: the choice of lens, zoom, exposure bias, and focus lock ([M2 record](done/m2-live-camera.md)).

**Is it worth it?** Phases 0–2 answer that cheaply. They put the existing pipeline on the phone with a bare-bones screen. Phases 3–5 are only worth doing if the play test says yes.

## Layout: one package, two app shells

```
Package.swift              the shared package, as today
Sources/
  HablamonModels/          data files and schemas (all platforms)
  HablamonCore/            pipeline, camera, OCR, speech, storage (all platforms)
    Live/LiveCamera.swift    Mac: Continuity Camera (#if os(macOS))
    Live/PhoneCamera.swift   iPhone: its own back cameras (#if os(iOS))
  HablamonVoices/          Kokoro on both platforms; Qwen3 on the Mac only
  HablamonApp/             the Mac app (a SwiftPM executable, built by scripts/install.sh)
  HablamonCLI/             the `hablamon` CLI (Mac, and Linux for tests)
Apps/iOS/
  Hablamon.xcodeproj       thin shell: one app target, signing, Info.plist keys
  HablamonPhone.xcconfig   build settings; Local.xcconfig (gitignored) holds the signing team
  HablamonPhone/           the iPhone app's SwiftUI code
```

- **The package stays the source of truth.** It gains `.iOS(.v18)` and a `HablamonKit` library product (Models, Core, Voices) for the Xcode project to link. Cloud sessions keep building and testing all of it on Linux.
- **The Xcode project is as thin as possible.** SwiftPM can't build an iOS app bundle, so the project holds one target whose sources are a folder Xcode syncs automatically. Adding a file needs no project edit. Build settings live in the `.xcconfig`, so `project.pbxproj` rarely changes. This is the exception to AGENTS.md's "no Xcode project" rule; the rule is updated to say so.
- **The Mac app stays a SwiftPM executable.** Moving it into Xcode too would gain nothing.

## Phases

| Phase | What | Question it answers | State |
| --- | --- | --- | --- |
| 0. Groundwork | Package builds for iOS; Xcode shell; `mise run phone`; CI builds the iPhone app | Does the monorepo hold together? | Built |
| 1. Camera bench | `PhoneCamera` with lens, zoom, exposure bias, focus lock; calibration screen showing text size | Can the phone read the box from where you'd put it? | Built |
| 2. Pipeline on the phone | `LiveEngine`, Kokoro voices, translation, transcript, and a heat and battery log on a bare-bones screen | Accurate, quick, and cool enough over an hour? | Built |
| **Decision** | Kyle's play test (below) | Worth carrying on? | Waiting |
| 3. Shared app layer | `HablamonUI` library with the app model and the panels, used by both shells; the phone's stand-in model goes away | One app, two screens | Planned |
| 4. Phone companion UI | Key words, recap, speaker tagging, whole-screen translation, settings, Files export | Feature parity where it makes sense | Planned |
| 5. Hardening | Thermal back-off, iPad layout, app icon, TestFlight if paid | Usable every day | Planned |

### Phase 0: groundwork (built)

- `Package.swift`: platforms `.macOS(.v15), .iOS(.v18)`; `HablamonKit` library product; speech-swift's `AudioCommon` (the model downloader Kokoro uses) on iOS too. Qwen3TTS stays Mac-only.
- Mac-only code is gated: `LiveCamera` (Continuity Camera, Center Stage) is `#if os(macOS)`. `AppSupportStore` uses the app's Documents folder on iOS, since `homeDirectoryForCurrentUser` doesn't exist there. Documents is shown in the Files app (On My iPhone › Hablamon), so logs and transcripts can be shared from the phone.
- `Apps/iOS/Hablamon.xcodeproj` with a shared `HablamonPhone` scheme. **Run builds Release**: the pipeline does pixel work in Swift, and an unoptimized Debug build would make the phone look slower and hotter than it is.
- Signing: `DEVELOPMENT_TEAM` comes from `Apps/iOS/Local.xcconfig` (gitignored). `scripts/phone.sh` (`mise run phone`) reads the team from the Apple Development certificate in the keychain, writes that file, then builds, installs, and launches on the connected phone with `xcodebuild` and `xcrun devicectl`.
- CI: a second job builds the iPhone app for a generic iOS device without signing, so a change to shared code can't silently break the phone.

### Phase 1: camera bench (built)

`PhoneCamera` mirrors `LiveCamera` for the rest of the pipeline: frames arrive upright, and interruptions report as suspended or resumed. It adds:

- **Lens choice** between the physical back cameras (0.5×, 1×, and the telephoto, labelled by field of view). A fixed physical lens, rather than the virtual multi-camera, so the phone never switches lenses on its own, which would look like the phone moving.
- **Zoom**, **exposure bias** on top of metering at the dialogue box, and **focus lock**.
- **15 frames a second** instead of 30, since the engine samples at most 4 a second. That costs no accuracy and saves power.
- **Upright frames** whichever way the phone is held, via `AVCaptureDevice.RotationCoordinator`.

The calibration screen shows the live picture with the proposed TV corners (drag to adjust), the text-height readout and warnings from `QualityGate`, and the camera controls. Changing lens or zoom reopens calibration, because the old corners no longer fit. Lens, zoom, bias, and focus lock are remembered.

### Phase 2: pipeline on the phone (built)

`PhoneModel` is a cut-down stand-in for the Mac's `AppModel`. It runs `LiveEngine` on `PhoneCamera` frames and applies its events to `CompanionState`. It speaks through `Narrator` with Kokoro (Apple voices while Kokoro downloads, about 312 MB the first time), translates with Apple's Translation framework, and writes the same transcript and log files.

The screen: the current line, large, with the spoken part highlighted; speaker; English below; a bottom bar (Repetir, Lento, Pausa, Cámara, Datos). **Datos** shows the bench numbers: thermal state, battery, lines spoken, and the last log lines (Kokoro first-audio and generation times, slow samples, bezel checks). The log records thermal state and battery every minute, so a long session can be read afterwards.

Deliberately left out: key words, recap, speaker tagging, whole-screen translation, settings UI. Phase 3 brings them over shared rather than copied.

### Kyle's play test (the decision)

1. `mise run phone` with the iPhone plugged in. The first time, Xcode needs your Apple ID (see Setup below).
2. Mount the phone, open **Cámara**, try 1× and the telephoto from where you'd sit, and drag the corners if needed. Note the text height it reports, and whether exposure bias stops the box blowing out.
3. Play for 30–60 minutes, plugged in.

- [ ] Lines are read correctly and start quickly after the text finishes.
- [ ] Which lens and distance work; is the phone readable from where you sit?
- [ ] Thermal state after an hour (Datos, or `thermal` lines in the log): nominal or fair is fine, serious is a problem.
- [ ] Battery holds while charging.
- [ ] Afterwards: Files › On My iPhone › Hablamon › logs › the latest log, sent back for tuning.

If it's worth it, phase 3 starts. If not, the phone code stays as an experiment that CI keeps building, and nothing in the Mac app changed.

### Phase 3: shared app layer (planned)

Move what both apps need into a `HablamonUI` library target in the package:

- `AppModel` minus AppKit: replay, live session, speech, translation, words, speakers. Platform bits go behind small protocols: `CameraFeed` (`LiveCamera` and `PhoneCamera` already expose the same `onFrame`/`onSignal`/`onLog` shape), cues (`NSSound` / `AudioServices`), and "bring the window forward".
- The panels that don't depend on window size: `HeroBox`, `ConversationPanel`, `WordsPanel`, `SpeakersPanel`, `CalibrationPanel`, `Theme`, `TranslationDriver`.
- The Mac shell keeps the window, menu bar, keys, and launch options. The phone shell keeps the layout, camera controls, and lifecycle. `PhoneModel` goes away.
- Done when the Mac app looks and behaves the same (snapshot with `--replay … --snapshot`), `mise run verify` passes, and the phone runs on the shared model.

### Phase 4: phone companion UI (planned)

- Landscape layout for a phone at arm's length: line, English, and key words; recap and words in a sheet; tap a line to repeat it.
- Speaker tagging from a sheet; whole-screen translation (T on the Mac) from a button.
- Settings screen for speed and engine, instead of editing `settings.json` (which is still in Files for hand edits).
- Share or export the transcript.

### Phase 5: hardening (planned)

- **Thermal back-off:** at `.serious`, sample less often and stop the free-speech whole-frame OCR; at `.critical`, pause and say why.
- iPad layout, if the iPad turns out to be the better screen.
- App icon from `Assets/`.
- Commit the Xcode project's `Package.resolved` once resolved on the Mac, so the phone builds against the same dependency versions as the Mac app.
- If the 7-day free signing gets tiresome: the paid program, then TestFlight uploads from CI.

## Setup (once)

1. Install Xcode (not just the Command Line Tools). In Xcode › Settings › Accounts, add your Apple ID; a "Personal Team" appears.
2. Plug the iPhone in and trust the Mac. Turn on Settings › Privacy & Security › Developer Mode (it appears after the phone has met Xcode) and restart.
3. `mise run phone`. If it can't find your team (no development certificate yet), open `Apps/iOS/Hablamon.xcodeproj` once, pick the Personal Team under Signing & Capabilities, press Run, and use `mise run phone` from then on. The script writes `Apps/iOS/Local.xcconfig`; you can also write `DEVELOPMENT_TEAM = <team ID>` there yourself.
4. On the phone, the first launch is blocked until you trust the developer: Settings › General › VPN & Device Management.
5. Xcode asks to "Trust & Enable" the swift-json-schema macros the first time; the script passes `-skipMacroValidation`.

With a free Apple ID the app stops launching after 7 days; `mise run phone` again re-signs it.

## Risks

- **None of the iOS code has been compiled yet.** It was written in a Linux cloud session. The CI job and the first `mise run phone` will surface any mistakes, which should be small.
- **Heat.** Camera, screen, Vision, and the Neural Engine for hours while charging. Phase 2 measures it; phase 5 backs off.
- **Free-account signing.** The bundle ID `dev.krw.hablamon.phone` must be unique to the team. Change it in `Local.xcconfig` (`PRODUCT_BUNDLE_IDENTIFIER`) if Xcode complains.
- **Kokoro's first download** needs Wi-Fi once (312 MB from Hugging Face), as on the Mac.

## Questions for Kyle

1. ~~Which iPhone?~~ A Pro (Oct 30): the telephoto is there, so try the phone beside you as well as by the TV, and 8 GB of RAM leaves room for the voices.
2. After the test: worth phase 3?
