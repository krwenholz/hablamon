# Hablamon: Live Spanish Audio for Pokémon Scarlet

Oct 11, 2026 · @Kyle · trimmed Oct 16 to the remaining work; finished work is in [done/](done/)

## Overview

Hablamon is a native macOS app that watches Pokémon Scarlet on the TV through an iPhone camera and reads each Spanish dialogue box aloud, offline, in a consistent voice per character. The game is played in Spanish (Spain localization) and has no voice acting; the goal is listening practice alongside reading.

**Goals**

- Detect a dialogue box on screen, wait for the typewriter text to finish, OCR it, and speak it in Spanish.
- Identify the speaker from the name tag and use the same voice for that character every time.
- Run fully offline on a MacBook Air (Apple Silicon, fanless) for multi-hour sessions without thermal throttling.
- Recover gracefully when the iPhone camera is picked up, moved, or paused.
- Keep an append-only transcript of every line for later study and translation.
- Make the speech engine swappable so better local voice models can be added later.

**Non-goals for v1**

- Translation to English (v2, run offline in batch against the transcript).
- Capture cards, Windows, Linux, mobile, or any hosted/server component.
- Reading menus, move lists, or battle UI text. Dialogue boxes only.
- Other games. Everything Scarlet-specific lives in `profiles/scarlet.json` so a second game profile is possible later.

## Platform and stack

Swift 6 on macOS with SwiftPM, using Apple frameworks only: AVFoundation (camera, video, speech), Vision (rectangle detection, OCR), Core Image (perspective correction), SwiftUI (window, menu bar). No OpenCV and no LLM in v1. Data files are JSON validated against schemas generated from the Swift types; transcripts are JSONL under `~/Library/Application Support/Hablamon/`.

## Status

| Milestone | State | Record |
| --- | --- | --- |
| Spike A: camera OCR | Done | [done/spike-a-ocr.md](done/spike-a-ocr.md) |
| M1: offline replay | Done, with leftovers below | [done/m1-offline-replay.md](done/m1-offline-replay.md) |
| M2: live Continuity Camera | Not started | This doc |
| M3: disruption handling | State machine built and tested; not wired to a camera | This doc |
| M4: characters and companion UI | Character table, matching, and voices built; UI designed (mockups), not built | This doc |
| Spike B: Qwen3-TTS on the Air | Not started | This doc |
| M5: second speech engine | Not started | This doc |

Built so far: the full pipeline from frame to transcript (perspective correction, box detection, settle, OCR, scroll-aware page sequencing, speaker matching, voice choice, Apple speech, JSONL transcript), the data-file types and schemas, the Scarlet profile and character table, `hablamon run --replay`, `ocr`, `export`, and `schema export`, and macOS CI. The [M1 record](done/m1-offline-replay.md) lists what lives where and how it differs from the first design.

## M1 leftovers

- Save box crops with transcript lines (the `crop` field stays empty today).
- Decide on low-confidence re-reads once more video is available (Vision reports 0.5 even on correct reads).

## M2: live Continuity Camera

The iPhone, via Continuity Camera, is the primary camera; the MacBook's built-in camera is never used as a silent fallback because it faces the player. Calibration turns whatever angle the phone has into the canonical 1280×720 frame the pipeline already consumes.

**Camera selection**

- Enumerate devices with `AVCaptureDevice.DiscoverySession` including `.continuityCamera`. Persist the chosen device's `uniqueID` in `calibration.json`.
- Never auto-switch to another device. If the pinned device disappears, enter the Lost state (M3).
- Request 1080p at 30 fps; the app samples far fewer frames than that.
- Allow the built-in camera only when `settings.json` says so (useful for development).

**Exposure control (new, from Spike A).** The phone's auto-exposure blows out the TV whenever the game scene brightens, and that caused every remaining replay error. Lower exposure on the pinned camera (`exposureTargetBias`, or a locked exposure tuned on the box) and re-check the far video's faint pages with it.

**Calibration**

1. Show the live preview in the main window.
2. Run `VNDetectRectanglesRequest` to propose the TV screen quad. The user accepts it, or drags the four corners to fix it.
3. Feed `ScreenCorrector` (already built) with that quad.
4. Save the quad, device ID, zoom, and a small grayscale reference thumbnail of the corrected bezel.

**Quality gate** (after calibration, shown in the UI)

- Measure body-text cap height in camera pixels. Spike A read text correctly at about 10 px, so start the warning around 8 px rather than the 14 px first planned.
- Run a test OCR on the next real dialogue box and show the result.
- Expose `videoZoomFactor` as a setting so a far phone can zoom in.
- Warn on clipped highlights inside the box region.

**Adaptive sampling.** Idle: one box check every 2 s (setting: 1–3 s). Dialogue: about 4 per second, as in replay. Dialogue mode ends after the box has been absent for 3 s (`DialoguePresence` already does this).

**App bundle and install** (`scripts/install.sh`, not written yet)

1. `swift build -c release`, assemble `Hablamon.app` with `Info.plist` (`NSCameraUsageDescription`) and resources.
2. Ad-hoc codesign with the camera entitlement; a stable bundle ID keeps the permission across rebuilds.
3. Copy to `~/Applications/` and symlink the CLI into `~/.local/bin/hablamon`.

Gotchas: camera permission attaches to the app bundle, so live `hablamon run` should launch or talk to the bundled app rather than borrow Terminal's permission. Mark capture and OCR work `.utility` QoS so the Air prefers efficiency cores.

## M3: disruption handling

Picking up the phone is expected, not an error. `ConnectionMonitor` already turns signals into states and effects (stop the pipeline, log a gap with its first cause, log a recalibration, ask for help after 10 s). What's left is producing the signals and performing the effects:

- **Paused:** key-value observe `AVCaptureDevice.isSuspended` on the pinned device; the monitor's frame timeout covers frames simply stopping.
- **Lost / reconnected:** `wasDisconnectedNotification` / `wasConnectedNotification` for the pinned `uniqueID`.
- **Phone bumped:** in Tracking, every ~10 s compare the corrected bezel against the reference thumbnail; a large mismatch, or box detection failing on every sample, is `screenMismatch`.
- **Re-finding:** run rectangle detection on each sample; accept a ~16:9 quad whose corrected bezel matches the reference.
- **Effects:** wire `stopPipeline` to `Narrator.interrupt()` and `DialoguePipeline.reset()`, the log effects to `TranscriptWriter`, and the cues to short, quiet system sounds (stopped watching, resumed, needs attention).

Apple documents that the Continuity Camera feed pauses while the phone is in use and resumes once it is [locked and mounted again](https://support.apple.com/102546), and that macOS may switch cameras when the iPhone disconnects, which is why the device is pinned.

## M4: characters and companion UI

- **Data files in Application Support:** seed `characters.json` from the bundled table and `settings.json` from `Settings.defaults` on first run, write a `$schema` key, and load them through `DocumentLoader` so hand edits get clear errors.
- **Unknown speakers:** unmatched tags already get a stable fallback voice. Add the UI to tag them (male, female, neutral) and persist them to `characters.json`.
- **Main window:** see [mockups/main-window.png](mockups/main-window.png) (chosen over a busier dark layout). Runs full screen on a 13" Air (1470×956 points), read from the couch, so it favors whitespace over density. The style borrows from the game: Scarlet's orange striped menus, cards with heavy ink outlines, and the in-game dialogue box (off-white, yellow tick marks, navy name tag).
  - **Top, largest:** the line being spoken in a copy of the game's box, with the not-yet-spoken words dimmed. The English translation goes under it in v2; leave the space now.
  - **Lower left:** the conversation so far, chat-style, with speaker, time, and a replay on click. Gaps from M3 (phone picked up, recalibrated) show as small inline notes.
  - **Lower right:** vocabulary from the recent lines: word, part of speech, English gloss, and the sentence it came from. Definitions come from the dictionaries macOS already ships (Dictionary Services), keeping it offline with no new dependency. Unverified: the public `DCSCopyTextDefinition` only searches the dictionaries enabled in Dictionary.app, so the Spanish–English one may need enabling, and output parsing is untested.
    - **Which words:** rank by three signals Kyle named. *Newness*: not shown in an earlier session (by lemma, so `combatir` and `combatimos` count once). *Frequency*: how often the lemma appears across all transcripts, so words the game keeps using rise. *Importance to the sentence*: content words (nouns, verbs, adjectives, adverbs) over function words and names. `NaturalLanguage`'s `NLTagger` gives Spanish lemmas and word classes offline. Treating frequency as in-game frequency rather than general Spanish frequency was our call, since it needs no word list; revisit if the panel fills with game jargon.
  - **Bottom strip:** state pill, five pipeline lights (camera, TV, box, text, voice), device and voice, a couple of timings, and hotkey hints.
  - **No live camera view.** The phone's own screen shows what it sees. The camera view appears only in the recovery card and calibration.
  - **Labels in Spanish.** Holding a hotkey switches labels to English while held (Carbon delivers key-release events, so this works globally).
- **Status and recovery:** see [mockups/status-states.png](mockups/status-states.png) for the pill in each state (Idle, Reading, Speaking, Phone in use, Finding TV, Lost camera, Needs you). When the TV can't be re-found, a recovery card with the saved view, the current view, and proposed corners replaces the vocabulary panel until resolved. Diagnostics (text height, clipped highlights, OCR time, settle-to-voice time, confidence) expand from the bottom strip. That sheet uses the rejected dark styling; build it in the main window's style.
- **Unknown speakers:** prompt to tag them in the vocabulary panel's slot, like the recovery card, rather than a separate drawer.
- **Calibration view:** live preview, proposed quad with draggable corners, quality-gate readout, zoom slider.
- **Menu bar extra:** state dot, start/pause, open window, recalibrate, quit.
- **Global hotkeys** via Carbon `RegisterEventHotKey` (no Accessibility permission); defaults are already in `Settings.defaults`: repeat last line ⌥⌘R, repeat slowly ⌥⇧⌘R, toggle slow/normal speed ⌥⌘S, pause/resume ⌥⌘P, recalibrate ⌥⌘C.
- **CLI still to add:** `hablamon calibrate`, live `hablamon run`, and `hablamon voices design` (M5).

## Spike B and M5: second speech engine

All engines go through the `SpeechEngine` protocol and `Narrator` (one line in flight, slow 0.85× default, Apple fallback), which are built. Kyle heard the Apple voices on his Mac (Oct 23): good enough for now, but better voices are wanted soon.

| Order | Engine | Voices | Footprint | Status |
| --- | --- | --- | --- | --- |
| 1 | Apple `AVSpeechSynthesizer` | Installed es-ES voices (Enhanced/Premium recommended), varied by pitch | None | Built |
| 2 | [Qwen3-TTS](https://www.mintlify.com/QwenLM/Qwen3-TTS/introduction) | A distinct voice per character | 0.6B runtime model, plus 1.7B for one-time design | Spike B |
| 3 | [Kokoro-82M](https://replicate.com/alphanumericuser/kokoro-82m) | ef_dora (female), em_alex and em_santa (male) | ~82M parameters | Fallback if Qwen3 is too slow |

**Qwen3-TTS: design once, clone at runtime.** Qwen3-TTS covers [European and Latin American Spanish](https://www.mintlify.com/QwenLM/Qwen3-TTS/concepts/languages). `hablamon voices design` runs the 1.7B VoiceDesign model on each character's `description` and writes `voices/<name>.wav` (recorded in `voices/manifest.json`); during play the 0.6B Base model clones from that clip, and characters without one use a preset voice by gender. Run through [mlx-audio](https://github.com/blaizzy/mlx-audio); if its Swift port lacks Qwen3-TTS, a local Python helper over stdin/stdout is acceptable. It stays offline.

**Latency budget.** Speech should start within ~1.5 s of settle on the Air. Spike B measures time to first audio for a typical 120-character line, peak memory, and 30-minute thermals; if Qwen3 misses the budget, use Kokoro.

## Testing still to build

The unit, state-machine, schema, OCR, and replay layers exist and run in `scripts/verify.sh` and CI. Still to add:

| Layer | What it proves | How |
| --- | --- | --- |
| Phone-shot corpus | OCR survives real camera conditions | Expected text for every photo and video in `Tests/Fixtures`; assert character error rate per placement. Replaces the synthetic-warp layer: there will be no clean Capture-button screenshots, only realistic phone shots |
| Speech round trip | Audio says the line | Render with `AVSpeechSynthesizer.write`, transcribe on-device with the Speech framework in es-ES, assert low word error rate; skip if on-device recognition isn't installed |
| Performance | Light enough for a fanless Air | Budgets for idle and dialogue sample cost, OCR latency, and settle-to-first-audio time |

**Fixtures still needed from Kyle:** a clip with item pickups. The landscape videos and photos from Oct 23 cover the real placement and three non-standard boxes (shout, phone call, PA announcement).

**Kyle's play test per milestone** (about 5 minutes)

- [ ] Lines are spoken shortly after the text finishes typing, without repeats.
- [ ] Picking up the phone and putting it back recovers with no input, or with one corner confirm.
- [ ] Speakers sound consistent across a conversation.

## Open questions

- Phone placement: near reads exactly; far works when settled and not overexposed. Decide after exposure control and a near video.
- Does the Switch's TV output setting (1080p vs 720p) change legibility through the camera?
- Should battle text ("¡Sprigatito usó Arañazo!") be spoken? Its box differs from dialogue; default off.
- Exact name-tag text for generic speakers (does a grunt's tag say "Recluta" or something longer?).

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
