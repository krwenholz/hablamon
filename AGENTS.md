# AGENTS.md

Guidance for coding agents (Claude Code, Codex, etc.) working in this repo.

## What this is

Hablamon is a native macOS app that watches Pokémon Scarlet (Spanish, Spain localization) on a TV through an iPhone via Continuity Camera, OCRs each dialogue box once the typewriter text settles, and reads it aloud offline in a consistent voice per character. It also keeps an append-only JSONL transcript.

**The design doc is the source of truth: [`docs/plans/init.md`](docs/plans/init.md).** Read it before starting any milestone. If you change the design, update that doc in the same change.

Two diagrams in the plan didn't survive export (they show as `[embedded content: ...]`). What they covered:

- **Processing pipeline (8 stages):** capture → perspective correction → box detection → settle (typewriter) → OCR (body + name tag) → speaker resolution → speech → transcript log.
- **Connection state machine (5 states):** Tracking, Paused, Lost, Re-finding, Recalibrate. Transitions are described in "Disruption handling".

## Current status

Nothing is implemented yet. The repo holds only the plan and these scaffolding files. Work proceeds in the milestone order from the plan:

0. **Scaffold** (do this first): create `Package.swift` and the empty target layout below, get `swift build` and `swift test` passing with a placeholder test, then add `scripts/verify.sh` and `.github/workflows/ci.yml`.
1. **Spike A:** camera OCR feasibility (near and far phone placement).
2. **M1:** offline replay end to end (`hablamon run --replay clip.mov`). Schema types, `verify.sh`, and CI must be in place by the end of this milestone.
3. **M2:** live Continuity Camera, calibration UI, quality gate, adaptive sampling.
4. **M3:** disruption handling state machine.
5. **M4:** character table, unknown-speaker tagging, companion UI, hotkeys, menu bar.
6. **Spike B:** Qwen3-TTS on a MacBook Air, via mlx-audio.
7. **M5:** second speech engine.

Update this section as milestones land.

## Platform and toolchain

- macOS on Apple Silicon only. Swift 6 language mode, Swift Package Manager. **No Xcode project**; everything builds with `swift build`.
- Apple frameworks only in v1: AVFoundation, Vision, Core Image, vImage, AVSpeechSynthesizer, SwiftUI, Speech (tests only).
- Allowed third-party packages: `swift-argument-parser` (CLI) and `swift-json-schema` (`@Schemable`, schema export and validation). Ask before adding anything else. Notably: **no OpenCV and no LLM in v1.**
- Fully offline at runtime. No network calls, telemetry, or hosted components.

## Layout (target)

```
Package.swift
Sources/
  HablamonCore/     # pipeline: Capture, Calibration, Detector, Settler, OCR,
                    # Speakers, Speech (protocol + engines), Transcript, StateMachine
  HablamonModels/   # @Schemable Codable types for every JSON file
  HablamonApp/      # SwiftUI window, menu bar extra, hotkeys
  HablamonCLI/      # swift-argument-parser: run, calibrate, voices, export, ocr, schema
Resources/
  profiles/scarlet.json
  characters.default.json
  Info.plist        # NSCameraUsageDescription
schemas/            # exported *.schema.json, checked in, verified by tests
Tests/
  HablamonCoreTests/
  HablamonModelsTests/
  Fixtures/         # screenshots, phone videos, golden transcripts
scripts/
  install.sh        # build, bundle, ad-hoc sign, install
  verify.sh         # run every test layer, write reports/verify.md
docs/plans/         # design docs
```

The package root is the repo root (not a nested `Hablamon/` folder as the plan's sketch shows).

## Commands

```sh
swift build                        # debug build
swift build -c release             # release build
swift test                         # all Swift Testing suites
swift test --filter <SuiteName>    # one suite
scripts/verify.sh                  # every test layer + reports/verify.md (once it exists)
scripts/install.sh                 # build, bundle, sign, install Hablamon.app (once it exists)
swift run hablamon schema export   # regenerate schemas/*.schema.json (once it exists)
swift format lint -r Sources Tests # lint (config in .swift-format)
swift format -i -r Sources Tests   # format in place
```

## Conventions

- **Testing:** Swift Testing (`import Testing`, `@Test`, `#expect`), not XCTest. Core logic must be testable without a camera, microphone, or speaker: put hardware behind small protocols and inject fakes (fake clock, fake camera, recorded frames).
- **Concurrency:** Swift 6 strict concurrency. Pipeline stages are actors or plain `Sendable` types behind small protocols. Frames flow as `CIImage`. Run capture and OCR work at `.utility` QoS so the fanless Air prefers efficiency cores.
- **Models:** every JSON file read or written has a `@Schemable` Codable type in `HablamonModels`. Types are the source of truth; `schemas/` is generated, never hand-edited. A test fails if the committed schemas drift. Every file carries an integer `schemaVersion` (`v` on transcript lines) with explicit, tested migrations. Transcript schema changes are additive only.
- **Validation:** validate user-editable JSON against its schema *before* decoding, and report errors with a JSON path.
- **Game specifics:** keep anything Scarlet-specific (box rectangles, colors) in `Resources/profiles/scarlet.json`, not in code, so another game profile can be added later.
- **Spanish text:** keep `¡ ¿ ñ` and accents intact throughout OCR normalization, logging, and tests. Files are UTF-8.
- **Speech:** all engines go through the `SpeechEngine` protocol. If an engine fails, fall back to Apple's. The app should never go silent.
- **Camera:** never silently fall back to the built-in camera, and never auto-switch devices. Pin the chosen device by `uniqueID`.
- **Permissions:** camera access attaches to the signed `.app` bundle. Running the bare CLI from Terminal borrows Terminal's permission, so live-camera paths must run through the bundled app. Replay, OCR on images, and tests don't need the camera.
- **Hotkeys:** use Carbon `RegisterEventHotKey` (no Accessibility permission needed).

## Definition of done for a milestone

1. `swift build` and `swift test` pass with no new warnings.
2. `scripts/verify.sh` passes and `reports/verify.md` is regenerated. Paste its summary into the PR or hand-off message.
3. `schemas/` is up to date if any model changed.
4. The plan and this file are updated if behavior or layout changed.
5. List the human play-test checklist items from the plan that Kyle should run.

## Things that need a human

- Capturing fixtures: Switch screenshots and iPhone videos (see "Testing plan" in the design doc). Don't fabricate fixture data. If fixtures are missing, write the tests so they skip with a clear notice.
- Granting camera permission, installing Enhanced/Premium es-ES voices, and the on-device Spanish speech recognition model.
- The five-minute play test per milestone.
