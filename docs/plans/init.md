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
| M2: live Continuity Camera | Built and unit-tested; awaiting a play test with the iPhone | [done/m2-live-camera.md](done/m2-live-camera.md) |
| M3: disruption handling | Wired to the live camera; awaiting the play test | [done/m2-live-camera.md](done/m2-live-camera.md) |
| M4: characters and companion UI | Window, calibration panel, and recovery built | [done/m4-companion-window.md](done/m4-companion-window.md) |
| Spike B: Qwen3-TTS on the Air | Not started | This doc |
| M5: second speech engine | Not started | This doc |

Built so far: the full pipeline from frame to transcript (perspective correction, box detection, settle, OCR, scroll-aware page sequencing, speaker matching, voice choice, Apple speech, JSONL transcript), the data-file types and schemas, the Scarlet profile and character table, `hablamon run --replay`, `ocr`, `export`, and `schema export`, and macOS CI. The [M1 record](done/m1-offline-replay.md) lists what lives where and how it differs from the first design.

## M1 leftovers

- Save box crops with transcript lines (the `crop` field stays empty today).
- Decide on low-confidence re-reads once more video is available (Vision reports 0.5 even on correct reads).

## M2 and M3: live camera and recovery

Built and unit-tested; see the [record](done/m2-live-camera.md) for what changed from the original design (no exposure bias or zoom on macOS; exposure is metered on the dialogue box) and the play-test checklist. What's left depends on that play test: exposure if the box still blows out, and threshold tuning for the bezel check and rectangle picking on the Air.

## M4: characters and companion UI

The window, vocabulary, speakers panel, hotkeys, and menu bar are built and run on replayed video; see the [M4 record](done/m4-companion-window.md) and the [design mockups](mockups/main-window.png). Still to do:

- **CLI still to add:** `hablamon voices design` (M5). Calibration and live watching live in the app.

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
