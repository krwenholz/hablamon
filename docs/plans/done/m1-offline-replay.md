# M1: offline replay

Oct 14, 2026 · done, with the leftovers listed at the end · design in [init.md](../init.md), measurements in [spike-a-ocr.md](spike-a-ocr.md)

## Outcome

`hablamon run --replay <video> --calibration <file>` reads a recorded video end to end and writes a session transcript; `--speak` reads the pages aloud afterwards. On `Tests/Fixtures/videos/far.mp4` (far placement, 123 s) it speaks 15 pages in about 25 s of processing. Every well-exposed line comes out right apart from small slips, and the remaining errors trace back to the phone overexposing the TV. A macOS test replays the video against the golden transcript on every CI run.

## What was built

| Area | Where | Notes |
| --- | --- | --- |
| Data files | `Sources/HablamonModels/`, `schemas/` | Six `VersionedDocument` types; loader validates before parsing and reports JSON paths; `hablamon schema export`; a test fails on stale schemas |
| Character table | `Resources/characters.default.json` | 44 speakers from the base game and both DLCs, checked against WikiDex, with aliases (Cael → Clavel) |
| Game profile | `Resources/profiles/scarlet.json` | Box, text, name-tag, and arrow regions measured from the far video |
| Detection | `Detection/` | `BoxFeatures` (name tag, else blank margins), `DialoguePresence` debounce, `SettleDetector` with contrast-scaled tolerance |
| Text and speakers | `Text/`, `Speakers/` | `DialogueText` cleanup, `PageSequencer` (repeats and scrolling), `SpeakerResolver` (accent folding, small misreads, ties stay unknown) |
| OCR | `OCR/` | Vision `.accurate`, `es-ES`, honors EXIF orientation; `hablamon ocr` for images and sampled video |
| Pipeline and replay | `Pipeline/`, `Replay/` | `DialoguePipeline` over a `DialogueFrame` protocol; Core Image perspective correction; AVAssetReader frames at 4 Hz |
| Voices and speech | `Speech/` | `VoiceSelector` (gender, age group, FNV-1a nudge); `Narrator` (one line in flight, Apple fallback); `AppleSpeechEngine` |
| Transcript | `Transcript/` | Append-only JSONL writer that resumes sequence numbers; validating reader; `hablamon export` to CSV |
| Disruptions (ahead of M3) | `Connection/ConnectionMonitor.swift` | Pure state machine with tests; not yet wired to a camera |
| Tooling | `mise.toml`, `scripts/`, `.github/workflows/ci.yml` | `verify.sh` with photo-privacy check, fixture download pinned by SHA-256, macOS CI with per-step timeouts |

## Where it differs from the original design

- **Box detection is structural.** The plan's luminance and saturation statistics fail when the phone overexposes the TV. The box counts as visible when the blue name tag is present, or, for narration, when the rows around the text are blank.
- **Settle tolerance scales with contrast,** and the next page is detected against the snapshot taken at settle, so faint pages still settle and advance.
- **Scrolling text is handled:** when a page starts with the previous page's last line, only the new lines are spoken.
- **`characters.json` wraps the table** in `{ "schemaVersion", "characters" }` and adds `englishName`, `ageGroup`, `role`, `aliases`, and `version`.
- **No low-confidence re-read.** Vision reports 0.5 even on correct reads, so re-reading would double OCR on most pages for unclear gain.
- **Replay samples at a fixed 4 Hz.** Adaptive idle sampling belongs with the live camera (M2).
- **Tests run serially** (`--no-parallel`): the Vision and video tests block threads and starved the concurrency pool when run in parallel, which once hung CI for hours.

## Leftovers

Carried into the remaining work in [init.md](../init.md):

- Hear `--speak` on a real Mac; the speech path is untested on hardware.
- Kyle to check the `certain: false` lines in `Tests/Fixtures/videos/far.expected.json`.
- Box crops are not saved with transcript lines yet (`crop` stays empty).
- Test layers not built: synthetic camera, speech round trip, performance budgets.
- `HablamonApp` is still a placeholder window.
