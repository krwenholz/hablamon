# Hablamon: Live Spanish Audio for Pokémon Scarlet

Oct 11, 2026 · @Kyle

## Overview

Hablamon is a native macOS app that watches Pokémon Scarlet on the TV through an iPhone camera and reads each Spanish dialogue box aloud, offline, in a consistent voice per character. The game is played in Spanish (Spain localization) and has no voice acting; the goal is listening practice alongside reading.

**Goals**

- Detect a dialogue box on screen, wait for the typewriter text to finish, OCR it, and speak it in Spanish.
- Identify the speaker from the name tag and use the same voice for that character every time, matching gender where known.
- Run fully offline on a MacBook Air (Apple Silicon, fanless) for multi-hour sessions without thermal throttling.
- Recover gracefully when the iPhone camera is picked up, moved, or paused.
- Keep an append-only transcript of every line for later study and translation.
- Make the speech engine swappable so better local voice models can be added later.

**Non-goals for v1**

- Translation to English (v2, run offline in batch against the transcript).
- Capture cards, Windows, Linux, mobile, or any hosted/server component.
- Reading menus, move lists, or battle UI text. Dialogue boxes only.
- Other games. Box detection is tuned to Scarlet; keep it isolated so a second game profile is possible later.

## Platform and stack

Swift on macOS, using Apple frameworks for everything in v1. Rust and Go were considered, but nearly every hard part here is already solved by a built-in macOS framework, and binding to those from another language would cost more than it saves.

| Concern | Choice | Why |
| --- | --- | --- |
| Language | Swift 6, Swift Package Manager | Direct access to the frameworks below; builds with `swift build`, no Xcode project required |
| Camera | AVFoundation (`AVCaptureSession`) | Exposes the iPhone via Continuity Camera as a normal capture device, with connect/disconnect notifications |
| Screen finding + perspective | Vision `VNDetectRectanglesRequest` + Core Image `CIPerspectiveCorrection` | Finds the TV quad and flattens it; GPU-backed, no OpenCV dependency |
| OCR | Vision `VNRecognizeTextRequest`, `.accurate`, `es-ES` | On-device, supports Spanish, returns per-line bounding boxes and confidence |
| Cheap change detection | Core Image / vImage on a downscaled grayscale crop | Microseconds per frame; gates the expensive OCR |
| Speech (v1) | `AVSpeechSynthesizer` with es-ES voices | Offline, zero setup, supports pitch and rate per utterance |
| UI | SwiftUI window + menu bar extra | Small status/transcript window facing the player; calibration preview |
| Storage | JSONL + PNG files under `~/Library/Application Support/Hablamon/` | Append-only, greppable, easy to post-process |

No OpenCV and no LLM in v1. If Vision's rectangle detection proves unreliable for the TV quad, OpenCV (via a small C++ shim) is the fallback, not the default.

## Architecture

A linear pipeline in `HablamonCore`. Everything before OCR is cheap enough to run continuously; OCR and speech run once per dialogue page. A connection state machine (see Disruption handling) can pause the whole pipeline.

&#91;embedded content: processing pipeline · 8 stages\]

Each stage is a Swift actor or plain type behind a small protocol, so stages can be tested with recorded frames and the speech engine can be swapped. Frames flow as `CIImage`. Only the downscaled crops reach the detector and settler, and only settled crops reach OCR.

## Capture and calibration

The iPhone, via Continuity Camera, is the primary camera; the MacBook's built-in camera is never used as a silent fallback because it faces the player. Calibration turns whatever angle the phone has into a flat, fixed-size image of the TV, so everything downstream works as if it had a capture card.

**Camera selection**

- Enumerate devices with `AVCaptureDevice.DiscoverySession` including `.continuityCamera`. Persist the chosen device's `uniqueID`.
- Never auto-switch to another device. If the pinned device disappears, enter the Lost state (see Disruption handling).
- Request 1080p at 30 fps; the app samples far fewer frames than that.
- Allow the built-in camera only when explicitly chosen in settings (useful for development).

**Calibration**

1. Show the live preview in the main window.
2. Run `VNDetectRectanglesRequest` to propose the TV screen quad (a bright rectangle inside a dark bezel). The user accepts it, or drags the four corners to fix it.
3. Apply `CIPerspectiveCorrection` with that quad to every sampled frame, producing a canonical 1280×720 image.
4. Save the quad, the device ID, and a small grayscale reference thumbnail of the corrected bezel region.

**Designing for both phone placements**

Placement is not decided, so calibration must handle both and tell the user which they have.

| Placement | Expected | Handling |
| --- | --- | --- |
| Near: stand on the TV console, roughly square to the screen | Mild keystone, large text | Default path; should just work |
| Far: propped near the couch, steeper angle | Strong keystone, smaller text, more glare | Same correction; quality gate below decides whether it is usable |

**Quality gate** (run after calibration and shown in the UI):

- Measure the corrected dialogue box's body text cap height in source-camera pixels. Starting thresholds, to tune in the camera spike: target ≥ 18 px, warn below 14 px ("move the phone closer or zoom").
- Run a test OCR on the next real dialogue box and show its confidence.
- Expose the iPhone's zoom factor (`videoZoomFactor`) as a setting so a far phone can zoom in on the TV.
- Warn on clipped highlights (glare) inside the box region.

## Box detection, polling and settle

Most of the time there is no dialogue on screen, so the app idles at about one cheap check every 2 seconds and only speeds up while a box is visible. OCR runs once per page, after the typewriter animation stops.

**Box detection (no OCR).** Scarlet's dialogue box occupies a fixed region near the bottom of the corrected frame, with a separate name tag above its top-left corner. Detection on the corrected 1280×720 frame:

- Crop the box region and the name-tag region using rectangles stored in a per-game profile (`profiles/scarlet.json`), measured once from reference screenshots.
- Decide "box present" from simple statistics on the crop: mean luminance and saturation inside the expected panel color range, plus edge density along the box border. No ML.
- Require two consecutive positive samples to enter Dialogue mode, to ignore transient flashes.

**Adaptive sampling**

| Mode | Sample rate | Work per sample |
| --- | --- | --- |
| Idle | Every 2 s (setting: 1–3 s) | Correct the frame, box-present check |
| Dialogue | \~4 per second | Box-present check + change detection on the text crop |
| Settled | — | One OCR pass, then hand off to speech |

The 2-second idle lag is mostly hidden: the typewriter effect takes about that long to finish anyway. Dialogue mode returns to Idle after the box has been absent for 3 s.

**Settle logic (typewriter handling)**

- Downscale the body-text crop to grayscale \~160×40 and compute the mean absolute difference from the previous sample.
- "Settled" = difference below threshold for 3 consecutive Dialogue samples (\~750 ms). Optionally also detect the blinking ▼ advance indicator in the box's bottom-right as a confirming signal.
- On settle, run OCR once. A later large change in the text crop with the box still present means a new page: reset and wait for settle again.
- If the player advances mid-speech, the new page interrupts the current utterance (see Speech).

**Deduplication.** Normalize OCR text (trim, collapse whitespace, strip the ▼ glyph) and skip speaking if it equals the last spoken page within the same box session. This prevents repeats from small camera jitter.

## OCR and speaker identification

OCR runs on two crops from the corrected frame: the body text and the name tag. Both use Vision with `recognitionLevel = .accurate`, `recognitionLanguages = ["es-ES"]`, and `usesLanguageCorrection = true`.

**Body text**

- Upscale the crop 2× and apply mild contrast normalization before OCR; camera frames are softer than screenshots.
- Join observations top to bottom into one string, joining wrapped lines with a space (and rejoining words hyphenated across a line break).
- Record mean and minimum line confidence. If the minimum is below a threshold, OCR the next Dialogue sample too and keep the higher-confidence result.
- Strip UI glyphs (▼, button icons) and normalize quotes. Keep ¡ ¿ ñ and accents intact.

**Speaker name**

- If the name-tag region is empty or the box-present check says no tag, the speaker is `narrator` (item pickups, system messages such as "Has obtenido el Bocadillo").
- Otherwise OCR the tag and fuzzy-match it (normalized Levenshtein ≤ 2) against known names in the character table, so a misread "Clavei" still resolves to Clavel.
- An unmatched name becomes a new `unknown` character entry, voiced with the default for its slot until the user tags it (see Character table).

**Accuracy fixtures.** Collect real camera frames from both near and far placements into `Tests/Fixtures/` with the expected text, and run them as tests. Screenshots already shared in this project are a good starting set for expected strings, but camera frames are the real test.

## Character table and voice assignment

Voices come from a hand-editable character table, not from guessing gender from names. Spanish localized names don't reliably signal gender, and a small table is cheap to maintain.

`characters.json` lives in Application Support and is seeded from a bundled default:

```json
{
  "Clavel": {
    "gender": "male",
    "description": "stiff, theatrical academy director",
    "voices": {
      "apple": { "voice": "es-ES male", "pitch": 0.9, "rate": 0.95 },
      "qwen3": { "referenceClip": "voices/clavel.wav" }
    }
  },
  "narrator": { "gender": "neutral", "voices": { "apple": { "pitch": 1.0, "rate": 1.0 } } }
}
```

**Assignment rules**

- Known character: use its entry for the active engine.
- New name: create an `unknown` entry. Assign the next voice in the default pool, cycling round-robin, with a pitch offset derived from a stable hash of the name. The same unknown name therefore always sounds the same, even before it is tagged.
- The UI shows recent unknown speakers with one-click tags (male, female, neutral). Tagging moves the character into that gender's pool and persists the change.
- `description` is unused by the Apple engine; it is the input for designing Qwen3-TTS voices (next section).

**Seeding.** Bundle a starter table for the main Scarlet cast using their Spanish names, gender only. Leave the exact list to the implementer; it is easy to extend, and `unknown` handling covers gaps.

## Speech engines

All speech goes through one protocol, so engines can be swapped in settings without touching the pipeline. v1 ships only the Apple engine; Qwen3-TTS is the planned upgrade, and Kokoro is a fallback.

```swift
protocol SpeechEngine: AnyObject {
    var id: String { get }                  // "apple", "qwen3", "kokoro"
    func prepare() async throws            // load models; may take seconds
    func speak(_ line: Line, as voice: VoiceSpec, rate: Float) async throws
    func stop()                            // interrupt immediately
}
```

**Shared behavior (in the pipeline, not each engine)**

- A single-slot queue: a new page interrupts the current line via `stop()`. Lines never pile up behind each other.
- Global speed multiplier with a slow default (0.85×) and a hotkey to toggle normal speed.
- "Repeat last line" and "repeat slowly" hotkeys replay the last line through the same engine.
- If an engine fails to prepare or throws, fall back to the Apple engine and show a warning. Never go silent.

**Engines, in priority order**

| Order | Engine | Voices | Footprint | Status |
| --- | --- | --- | --- | --- |
| 1 | Apple `AVSpeechSynthesizer` | System es-ES voices (install Enhanced/Premium in System Settings), varied by pitch and rate | None | v1 |
| 2 | [Qwen3-TTS](https://www.mintlify.com/QwenLM/Qwen3-TTS/introduction) | A distinct voice per character | 0.6B runtime model, plus 1.7B for one-time design | Spike first |
| 3 | [Kokoro-82M](https://replicate.com/alphanumericuser/kokoro-82m) | ef\_dora (female), em\_alex and em\_santa (male) | \~82M parameters | Fallback if Qwen3 is too slow |

**Qwen3-TTS plan: design once, clone at runtime.** Qwen3-TTS covers [European and Latin American Spanish](https://www.mintlify.com/QwenLM/Qwen3-TTS/concepts/languages). Its 1.7B VoiceDesign model creates a voice from a text description, and its 0.6B Base model clones a voice from a \~3-second sample. So:

1. Offline tool `hablamon voices design` runs VoiceDesign on each character's `description` and writes a short reference clip to `voices/<name>.wav`.
2. During play, the engine runs the 0.6B Base model, cloning from that clip.
3. Characters without a clip use one of the model's preset voices by gender.

Run through [mlx-audio](https://github.com/blaizzy/mlx-audio), which targets Apple Silicon and has a Swift package (mlx-audio-swift). If the Swift port lacks Qwen3-TTS, a small local Python helper process speaking JSON over stdin/stdout is acceptable. It stays offline and local.

**Latency budget.** Speech should start within \~1.5 s of settle on the Air. The Qwen3 spike measures time to first audio for a typical 120-character line, peak memory, and sustained thermals over 30 minutes. If it misses the budget, pre-synthesis can't help (text isn't known in advance), so fall back to Kokoro.

## Disruption handling

Picking up the phone is expected, not an error. The app pauses cleanly, logs a gap, re-finds the TV when the phone is set down, and only interrupts the player when it can't find the screen on its own.

&#91;embedded content: connection state machine · 5 states\]

Apple documents that the Continuity Camera feed pauses while the phone is in use and resumes once it is [locked and mounted again](https://support.apple.com/102546); it also notes macOS may switch to another camera when the iPhone disconnects, which is why the device is pinned.

**Signals**

- **Paused:** key-value observe `AVCaptureDevice.isSuspended` on the pinned device; also treat no frames for > 1 s as paused.
- **Lost:** `AVCaptureDevice.wasDisconnectedNotification` for the pinned `uniqueID`. Return on `wasConnectedNotification` with the same ID.
- **Phone bumped:** in Tracking, every \~10 s compare the corrected frame's bezel region against the saved reference thumbnail. A large mismatch, or the box detector suddenly failing on every sample, moves to Re-finding.
- **Re-finding:** run rectangle detection on each sample. Accept a quad whose aspect ratio is \~16:9 and whose corrected bezel matches the reference, then log a `recalibrated` entry.
- **Recalibrate:** after \~10 s without a match, play a chime, bring the window forward with the calibration preview, and wait.

**On leaving Tracking:** stop any speech, discard a half-settled page, and write a `gap` log entry when Tracking resumes. Lines shown while the camera was away are not recovered.

## Transcript log

Every spoken page is appended to a JSONL file, one file per session, with raw OCR kept separate from anything derived so it can be re-translated or re-OCR'd later. Translation fields exist in the schema but stay empty in v1.

Path: `~/Library/Application Support/Hablamon/sessions/2026-10-11T19-30-00.jsonl`, with box crops in a sibling `crops/` folder.

```json
{"v":1,"type":"line","ts":"2026-10-11T19:42:07.512-07:00","session":"2026-10-11T19-30-00","seq":42,"speaker":"Clavel","speakerRaw":"Clavel","text":"Al fin y al cabo, debo hacerme responsable de las torpezas en que incurra mi academia.","ocrConfidence":{"mean":0.94,"min":0.81},"crop":"crops/000042.png","engine":"apple","voice":"es-ES male p0.9 r0.95","translation":null,"translationSource":null}
{"v":1,"type":"gap","ts":"2026-10-11T19:44:30.000-07:00","session":"2026-10-11T19-30-00","reason":"camera_paused","durationSec":48}
```

- `type`: `line` for spoken text, `gap` when the camera was paused or lost, `recalibrated` when the screen quad changed.
- `speakerRaw` keeps the OCR'd tag text; `speaker` is the resolved character.
- Crops are small grayscale PNGs of the corrected box region, used to fix OCR errors and build test fixtures.
- Writes are append-only and flushed per line, so a crash loses at most the line in flight.
- `hablamon export --since 7d --format csv` produces a flat file for later study or batch translation.

## UI and controls

The laptop faces the player, so the main window is a readable companion: who is speaking, the current line, and recent history. It must be glanceable from the couch: large type, dark background, no dense controls.

**Main window**

- Top strip: connection state (Tracking, Paused, Lost, Re-finding) as a colored dot plus a word, and the active engine.
- Center: speaker name and the current Spanish line in large type. A v2 translation line will sit under it.
- Bottom: scrolling transcript of the session, newest at the bottom. Click a line to replay it.
- Side drawer: unknown speakers awaiting a gender tag.

**Calibration view.** Live camera preview with the proposed screen quad, draggable corners, the quality-gate readout, and a zoom slider.

**Menu bar extra.** State dot, start/pause, open window, recalibrate, quit.

**Global hotkeys** (configurable; defaults avoid common game-capture shortcuts)

| Action | Default |
| --- | --- |
| Repeat last line | ⌥⌘R |
| Repeat last line slowly | ⌥⇧⌘R |
| Toggle slow/normal speed | ⌥⌘S |
| Pause/resume watching | ⌥⌘P |
| Recalibrate | ⌥⌘C |

**Audible cues.** Short, quiet system sounds on state changes: camera lost, screen re-found, recalibration needed. The player shouldn't have to look at the laptop to know it stopped listening.

**CLI.** The same binary exposes `hablamon run`, `hablamon calibrate`, `hablamon voices design`, `hablamon export`, and `hablamon ocr <image>` (one-shot OCR for debugging and fixtures).

## Project layout, build and install

One Swift package with a core library and thin app/CLI targets, so the pipeline is testable without a camera. A script assembles a signed `.app` bundle, because camera access needs one.

```
Hablamon/
  Package.swift
  Sources/
    HablamonCore/        // pipeline: Capture, Calibration, Detector, Settler, OCR,
                         // Speakers, Speech (protocol + engines), Transcript, StateMachine
    HablamonModels/      // @Schemable Codable types for every JSON file
    HablamonApp/         // SwiftUI window, menu bar extra, hotkeys
    HablamonCLI/         // swift-argument-parser: run, calibrate, voices, export, ocr, schema
  Resources/
    profiles/scarlet.json
    characters.default.json
    Info.plist           // NSCameraUsageDescription
  schemas/               // exported *.schema.json, checked in, verified by tests
  Tests/
    HablamonCoreTests/   // unit, state machine, synthetic camera, replay, speech, perf
    HablamonModelsTests/ // schema round trips, migrations, export drift
    Fixtures/            // Switch screenshots, phone videos, golden transcripts
  scripts/
    install.sh           // build, bundle, sign, install
    verify.sh            // run every test layer, write reports/verify.md
  .github/workflows/ci.yml
```

**Build and install** (`scripts/install.sh`, run on every change):

1. `swift build -c release`
2. Assemble `Hablamon.app` with `Info.plist` and resources.
3. Ad-hoc codesign (`codesign --force --sign - --entitlements ...`) with the camera entitlement. A stable bundle ID keeps the camera permission grant across rebuilds.
4. Copy to `~/Applications/` and symlink the CLI into `~/.local/bin/hablamon`.

**Gotchas to handle up front**

- Camera permission attaches to the app bundle. A bare CLI run from Terminal would borrow Terminal's permission instead, so `hablamon run` should launch or talk to the bundled app.
- Use Carbon `RegisterEventHotKey` for global hotkeys; it needs no Accessibility permission.
- Mark the capture and OCR work `.utility` QoS so the fanless Air prefers efficiency cores.

## Schemas and data contracts

Every JSON file Hablamon reads or writes has a schema. Swift `Codable` types are the single source of truth, and JSON Schema (draft 2020-12) is generated from them, so the two can't drift.

**Approach**

- Define each file's shape as a Swift struct marked `@Schemable` from [swift-json-schema](https://github.com/ajevans99/swift-json-schema). The macro generates the JSON Schema, and the library validates JSON against it and parses it into the Swift type.
- `hablamon schema export` writes every schema to `schemas/*.schema.json` in the repo. A test regenerates them and fails if the committed files differ, so a type change without a schema update breaks CI.
- At load time, validate every user-editable file *before* decoding and report errors with a JSON path, such as `characters.json: /Clavel/gender must be one of male, female, neutral`. A hand-edit typo then gives a clear message instead of a decode crash.
- User-editable files carry a `$schema` key pointing at the exported schema, so VS Code gives autocomplete and inline errors while you edit them.
- If the macro can't express a constraint (for example "pitch between 0.5 and 2.0"), add it with the library's schema options rather than an ad hoc check, so it shows up in the exported schema too.

**Contracts**

| File | Swift type | Validated | Notes |
| --- | --- | --- | --- |
| `characters.json` | `CharacterTable` | On load | User-editable; `$schema` key |
| `profiles/<game>.json` | `GameProfile` | On load | Box and name-tag rectangles, color ranges |
| `calibration.json` | `Calibration` | On load | Screen quad, device ID, zoom, reference thumbnail path |
| `settings.json` | `Settings` | On load | Engine, speed, hotkeys, sample rates |
| `voices/manifest.json` | `VoiceManifest` | On load | Designed Qwen3 reference clips per character |
| `sessions/*.jsonl` | `TranscriptEntry` (tagged union: line, gap, recalibrated) | In tests; writer is typed | One schema per line |

**Versioning.** Every file has an integer `schemaVersion` (`v` on transcript lines, to keep lines short). Loaders run explicit, tested migrations from older versions and refuse files from a newer version with a clear message. The transcript is append-only history, so its schema only gains optional fields; nothing is ever removed or renamed.

## Testing plan

Claude Code proves each milestone with automated tests and a generated report. Kyle's part is one short capture session up front and a five-minute play test per milestone.

**What Kyle provides, once (\~20 minutes)**

- 15–20 Switch screenshots of dialogue boxes from the Capture button: clean 1280×720 images with a mix of speakers, narrator lines, and long and short text.
- Two 5-minute iPhone videos of normal play, one from each placement (near and far), advancing dialogue at a normal pace.

Ground truth comes from OCR of the clean screenshots, plus a golden transcript for each video. Claude Code drafts the golden transcript from the box crops, and Kyle skims it once.

**Test layers** (Swift Testing `@Test` suites, run with `swift test`, no camera or human needed)

| Layer | What it proves | How |
| --- | --- | --- |
| Unit | Settler, dedupe, fuzzy speaker match, log writer, migrations behave correctly | Pure functions over recorded frame-difference sequences and fixture JSON |
| State machine | Every disruption path recovers or asks correctly | Fake clock and a fake camera that emits suspend, disconnect, reconnect, and bump events |
| Schemas | Files and code agree | Round-trip encode → validate → decode for every type; committed schemas match regenerated ones |
| Synthetic camera | OCR survives real-world camera conditions | Warp clean screenshots with seeded random perspective, scale, blur, noise, moiré, glare, and gamma for near and far presets; assert character error rate stays under a threshold per preset |
| Replay | The whole pipeline works end to end | Run `--replay` on the two videos; diff against the golden transcript: every line found, none duplicated, speakers correct |
| Speech round trip | Audio actually says the line | Render speech to a buffer (`AVSpeechSynthesizer.write`), transcribe it back on-device with Apple's Speech framework in es-ES, and assert word error rate is low. Also asserts per-character pitch and rate were applied. Skips with a notice if on-device recognition isn't installed. |
| Performance | It's light enough for a fanless Air | Benchmarks for idle and dialogue sample cost, OCR latency, and settle-to-first-audio time, each asserted against a budget |

The synthetic layer is what keeps this light on Kyle: from 20 screenshots it can generate thousands of camera-like frames, so OCR tuning never needs the Switch on.

**Proof of work.** `scripts/verify.sh` runs every layer and writes `reports/verify.md`: pass/fail per suite, OCR accuracy by placement preset, replay diff, speech word error rate, and performance numbers against budget. Claude Code runs it before calling any milestone done and pastes the summary. GitHub Actions on a macOS runner runs the same script on every push, except the replay and speech layers if the runner can't support them.

**Kyle's play test per milestone** (about 5 minutes)

- [ ] Lines are spoken shortly after the text finishes typing, without repeats.
- [ ] Picking up the phone and putting it back recovers with no input from you, or with one corner confirm.
- [ ] Speakers sound consistent across a conversation.

## Milestones, spikes and open questions

Build in this order. Each milestone is usable on its own, and the two spikes de-risk the parts most likely to fail.

1. **Spike A: camera OCR.** Film a few minutes of Scarlet with the iPhone from both near and far placements. Run perspective correction and Vision OCR on still frames. Exit: body text ≥ 95% character accuracy at the near placement, and a measured answer for far.
2. **M1: offline replay.** `hablamon run --replay clip.mov` end to end: correction, box detection, settle, OCR, Apple speech, JSONL log. No live camera yet. Schema types, scripts/verify.sh and CI land here, so every later milestone is tested from day one.
3. **M2: live Continuity Camera.** Device pinning, calibration UI, quality gate, adaptive sampling.
4. **M3: disruption handling.** The full state machine, audible cues, gap entries in the log, auto re-find.
5. **M4: characters and companion UI.** Character table, unknown-speaker tagging, main window, hotkeys, menu bar.
6. **Spike B: Qwen3-TTS on the Air.** Time to first audio, memory, and 30-minute thermals through mlx-audio. Exit: decide between Qwen3 and Kokoro as engine 2.
7. **M5: second engine.** Implement whichever engine Spike B picks, plus `hablamon voices design` if it's Qwen3.

**Open questions**

- Phone placement (near vs far) is undecided; Spike A should report both so the choice can be made on data.
- Exact box and name-tag rectangles for `profiles/scarlet.json` need measuring from real frames.
- Does the Switch's TV output setting (1080p vs 720p) change box legibility through the camera?
- Should battle text ("¡Sprigatito usó Arañazo!") be spoken? Its box differs from dialogue; default off, revisit after M1.

**v2 ideas (out of scope)**

- Offline batch translation of session logs into the `translation` field, shown under the line in the window.
- Feeding new vocab and idioms from the transcript into the Spanish Study Log's bank.
- Additional game profiles.

## Sources

- [Continuity Camera: Use iPhone as a webcam for Mac](https://support.apple.com/102546) (Apple Support)
- [Recognizing text in images](https://developer.apple.com/documentation/vision/recognizing-text-in-images) (Apple Vision docs)
- [Qwen3-TTS introduction](https://www.mintlify.com/QwenLM/Qwen3-TTS/introduction) and [language support](https://www.mintlify.com/QwenLM/Qwen3-TTS/concepts/languages)
- [Kokoro-82M model card](https://replicate.com/alphanumericuser/kokoro-82m)
- [mlx-audio](https://github.com/blaizzy/mlx-audio)
