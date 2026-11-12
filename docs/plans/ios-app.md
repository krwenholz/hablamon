# Hablamon on the iPhone

Oct 30, 2026 · @Kyle · phases 0–2 built and running in the simulator (not yet run on a phone); the rest planned · research in [done/spike-c-ios.md](done/spike-c-ios.md)

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
| 4. Phone companion UI | Key words, recap, speaker tagging, settings, Files export | Feature parity where it makes sense | Planned |
| 5. Hardening | Thermal back-off, iPad layout, TestFlight if paid | Usable every day | Planned |

### Phase 0: groundwork (built)

- `Package.swift`: platforms `.macOS(.v15), .iOS(.v18)`; `HablamonKit` library product; speech-swift's `AudioCommon` (the model downloader Kokoro uses) on iOS too. Qwen3TTS stays Mac-only.
- Mac-only code is gated: `LiveCamera` (Continuity Camera, Center Stage) is `#if os(macOS)`. `AppSupportStore` uses the app's Documents folder on iOS, since `homeDirectoryForCurrentUser` doesn't exist there. Documents is shown in the Files app (On My iPhone › Hablamon), so logs and transcripts can be shared from the phone.
- `Apps/iOS/Hablamon.xcodeproj` with a shared `HablamonPhone` scheme. **Run builds Release**: the pipeline does pixel work in Swift, and an unoptimized Debug build would make the phone look slower and hotter than it is.
- Signing: `DEVELOPMENT_TEAM` comes from `Apps/iOS/Local.xcconfig` (gitignored). `scripts/phone.sh` (`mise run phone`) finds the team (see Setup), writes that file, then builds, installs, and launches on the connected phone with `xcodebuild` and `xcrun devicectl`.
- App icon: `Apps/iOS/HablamonPhone/Assets.xcassets`, rendered by `scripts/build-icon.sh` from the Mac's `Assets/AppIcon.svg`, cropped to the body so iOS can round the corners itself.
- CI: a second job builds the iPhone app for a generic iOS device without signing, so a change to shared code can't silently break the phone.

### Phase 1: camera bench (built)

`PhoneCamera` mirrors `LiveCamera` for the rest of the pipeline: frames arrive upright, and interruptions report as suspended or resumed. It adds:

- **Zoom buttons** 0.5×, 1×, 2×, and 4×, as in the Camera app. Each picks the most magnifying physical lens that doesn't overshoot, measured by field of view, and zooms the rest of the way (`PhoneZoom`): 2× is the main camera at 2, and 4× is a 3× telephoto at 1.33, or the main camera at 4 when the telephoto is 5×. A phone without an ultra-wide has no 0.5×. A fixed physical lens, rather than the virtual multi-camera, so the phone never switches lenses on its own, which would look like the phone moving.
- **Focus and metering at the dialogue box**, with **exposure bias** on top and **focus lock** (not restored at launch, where it would lock before the camera has focused).
- **4K capture**, so 2× and 4× crop real detail. The first phone captures (Nov 8) came out 5–20× softer than the Mac fixtures by the box detector's edge measure (text edges 0.000–0.006 against 0.016–0.056): 1080p enlarged to 2×, with no focus point. Corners saved at another frame size or rotation aren't reused.
- **Reading the screen's text, not detecting the box.** The phone's `LiveEngine` uses `.screenText`: twice a second it OCRs the whole corrected screen and classifies the blocks (`FreeSpeech.find(dialogue: true)`): a finished line low on the screen within the box's span is dialogue, whatever the box's colours, with a capitalized name just above as the speaker; bubbles and subtitles elsewhere as before; notifications in the upper right skipped. A line is spoken once two reads agree (`FreeSpeechTracker`), so text still typing out waits, and a spoken dialogue line isn't repeated when it comes back after a bump. This replaced the Mac's chain of box detector, presence, settle detector, crop OCR, and page dedup on the phone. On Kyle's first captures (Nov 8–9) that chain missed most boxes: soft or tinted pictures, corners on the TV's bezel, and Mencía's green-on-black calls broke its brightness and edge thresholds, a noisy text crop cut lines off as "new pages", and the name-tag colour check gave her lines to the narrator. Whole-screen OCR read all eight captures, speakers included, in about 0.1 s each (on the Mac; the phone's time is logged as `slow read` past 0.5 s). The Mac keeps `.dialogueBox` until this proves out. `Tests/Fixtures/phone-captures/` holds the captures as regression tests.
- **Guardar captura** (in Datos) saves the camera frame and corrected screen to `captures/` and logs the box detector's measurements against its thresholds, for looking into a missed line.
- **15 frames a second** instead of 30, since the engine samples at most 4 a second. That costs no accuracy and saves power.
- **Portrait or landscape**, as the phone is stood. Frames are turned upright for how the screen is turned (`PhoneLens.captureRotation`), not for the phone's tilt, so the picture always matches the screen and stays put when the phone lies flat. Turning the phone makes the engine find the TV again, like a zoom change, and corners saved in the other orientation aren't reused. Portrait costs detail: the TV spans about 1,080 pixels of the picture instead of 1,920, so the text is about half as tall and 2× or 4× matter more.

The calibration screen shows the live picture with the proposed TV corners (drag to adjust), the text-height readout and warnings from `QualityGate`, the zoom buttons, and the confirm button; exposure bias and focus lock are folded away under **Ajustes**, since Kyle found the first version's sliders and lens picker too busy. The controls sit beside the picture in landscape and below it in portrait. It opens by itself only on a first run (no corners saved) or when the engine can't find the TV for 10 s (`ConnectionMonitor`'s `.recalibrating`); **Cámara** opens it on purpose. Otherwise calibration is automatic: at launch the saved corners are checked against the picture, every 10 s the bezel check confirms nothing moved, and after a move, a turn, or a zoom change the engine finds the TV again on its own, usually within a second. Kyle found the proposed corners right nearly every time and his hand-dragged ones worse (Nov 11), so the app stopped opening the screen at every launch and turn. Lens, zoom, bias, and focus lock are remembered.

### Phase 2: pipeline on the phone (built)

`PhoneModel` is a cut-down stand-in for the Mac's `AppModel`. It runs `LiveEngine` on `PhoneCamera` frames and applies its events to `CompanionState`. It speaks through `Narrator` with Kokoro (Apple voices while Kokoro downloads, about 312 MB the first time), translates with Apple's Translation framework, and writes the same transcript and log files.

The screen: the current line, large, with the spoken part highlighted, in the game's cream dialogue box with the speaker's navy tab; English below; dark pills (Repetir, Lento, Pausa, Lenta, Traducir, Cámara, Datos) in a row in landscape, or under the box in portrait as a row of the four speech controls over a row of three for the screen. It wears the Mac app's theme (striped orange background, heavy ink outlines with hard shadows, Gill Sans and Avenir Next) from `PhoneTheme.swift`, a copy of the Mac's `Theme.swift` and `HeroBox` pieces until phase 3 shares them. Motion is quiet and shared there too: buttons press down with a light tick, new lines and their English fade in, Datos and the camera screen fade in and out, and Reduce Motion turns movement into plain fades. **Datos** shows the bench numbers: thermal state, battery, lines spoken, and the last log lines (Kokoro first-audio and generation times, slow samples, bezel checks). The log records thermal state and battery every minute, so a long session can be read afterwards.

**Traducir** is the Mac's whole-screen translation (T): it snapshots the corrected TV picture (`LiveEngine.snapshot`, or the replay's latest corrected frame in the simulator), reads every block with `ScreenReader`, fills in official names from `GameTerms` at once, and machine-translates the rest. The English sits on paper labels over the picture, full screen; tap to close. When Translation can't run (the simulator, or no language pack), the blocks without a game term stay in Spanish on grey-edged labels and the status line says so, rather than waiting. Speech carries on underneath, as on the Mac.

Deliberately left out: key words, recap, speaker tagging, settings UI. Phase 3 brings them over shared rather than copied.

### Kyle's play test (the decision)

1. `mise run phone` with the iPhone plugged in. The first time, follow the setup in the README (see Setup below).
2. Mount the phone, landscape or portrait. Open **Cámara**, try 1×, 2×, and 4× from where you'd sit, and drag the corners only if the outline is off. Note the text height it reports, and whether exposure bias stops the box blowing out.
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
- The panels that don't depend on window size: `HeroBox`, `ConversationPanel`, `WordsPanel`, `SpeakersPanel`, `CalibrationPanel`, `Theme`, `TranslationDriver`, `ScreenTranslationView`. The phone's copies (`PhoneTheme.swift`, and its `ScreenTranslationView` and `FrameBox`) go away.
- The Mac shell keeps the window, menu bar, keys, and launch options. The phone shell keeps the layout, camera controls, and lifecycle. `PhoneModel` goes away.
- Done when the Mac app looks and behaves the same (snapshot with `--replay … --snapshot`), `mise run verify` passes, and the phone runs on the shared model.

### Phase 4: phone companion UI (planned)

- Landscape layout for a phone at arm's length: line, English, and key words; recap and words in a sheet; tap a line to repeat it.
- Speaker tagging from a sheet.
- Settings screen for speed and engine, instead of editing `settings.json` (which is still in Files for hand edits).
- Share or export the transcript.

### Phase 5: hardening (planned)

- **Thermal back-off:** at `.serious`, sample less often and stop the free-speech whole-frame OCR; at `.critical`, pause and say why.
- iPad layout, if the iPad turns out to be the better screen.
- If the 7-day free signing gets tiresome: the paid program, then TestFlight uploads from CI.

## Setup

The steps are in the README's [Try it on the iPhone](../../README.md#try-it-on-the-iphone-experimental), so a fresh clone on any Mac can follow them. Behind them:

- `scripts/phone.sh` writes `Apps/iOS/Local.xcconfig` (gitignored) with the Personal Team of the Apple ID added in Xcode, falling back to the team of an Apple Development certificate in the keychain. With `-allowProvisioningUpdates`, xcodebuild makes the certificate and profile on the first build. To use another team, write `DEVELOPMENT_TEAM = <team ID>` there yourself.
- It passes `-skipMacroValidation`, so Xcode never stops to ask about trusting the swift-json-schema macros.

## Trying it without the phone

`mise run phone-sim` runs the app in the iOS Simulator with a fixture video standing in for the camera. It checks OCR, Kokoro, and the screen on iOS; its replay still uses the Mac's `.dialogueBox` reading (`Replay.run`), while `LiveEngineTests.readsTheScreenTextAsIfLive` covers the phone's. Kokoro runs on the CPU there because the simulator's CoreML can't load it otherwise, so its timings say nothing about the phone. The simulator has no camera or Apple Translation, and replay skips `LiveEngine`, so `PhoneCamera`, calibration, tracking, English lines, heat, and Neural Engine speed all still need the play test.

## Risks

- **Nothing has run on a real phone yet.** The app builds for a device and runs in the simulator, but device signing and `PhoneCamera` are untested until the first `mise run phone`.
- **Heat.** Camera, screen, Vision, and the Neural Engine for hours while charging. Phase 2 measures it; phase 5 backs off.
- **Free-account signing.** The bundle ID `dev.krw.hablamon.phone` must be unique to the team. Change it in `Local.xcconfig` (`PRODUCT_BUNDLE_IDENTIFIER`) if Xcode complains.
- **Kokoro's first download** needs Wi-Fi once (312 MB from Hugging Face), as on the Mac.

## Questions for Kyle

1. ~~Which iPhone?~~ A Pro (Oct 30): the telephoto is there, so try the phone beside you as well as by the TV, and 8 GB of RAM leaves room for the voices.
2. After the test: worth phase 3?
