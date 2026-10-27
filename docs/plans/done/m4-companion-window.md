# M4: companion window

Oct 26, 2026 · window done on replay; live camera is M2 · design in [init.md](../init.md#m4-characters-and-companion-ui), plan in [m4-companion-window.md](../m4-companion-window.md)

## Outcome

`swift run HablamonApp --replay <video>` opens the full-screen window from [built-main-window.png](../mockups/built-main-window.png) and plays the recording in real time as if it were the camera: each settled line appears in the game-style box and is spoken with its words lighting up as they're said, earlier lines move to the conversation, and the words panel ranks vocabulary from the scene. On the landscape lobby video it reads 8 of 8 lines with the right speakers.

## What was built

| Area | Where | Notes |
| --- | --- | --- |
| Window | `Sources/HablamonApp/` | Layout B: hero box, conversation, words, status strip; Spanish labels, English while ⌥⌘E is held |
| State | `Companion/CompanionState.swift` | One reducer for the current line, speech progress, conversation and gaps, unknown speakers, status pill, and five lights |
| Vocabulary | `Vocab/`, `Resources/dictionary/` | `VocabRanker` (newness, frequency, word class; "Ya la sé" hides a word for good); bundled Wiktionary glossary, 91k lemmas with inflections, accent-folded lookups; `NLWordAnalyzer` |
| Data folder | `Storage/AppSupportStore.swift` | `~/Library/Application Support/Hablamon`: settings, characters, known words, `sessions/`, `replays/`, `logs/`; seeded on first run, broken files fall back with a visible issue |
| Speakers | `Speech/VoiceSelector.swift`, `SpeakersPanel.swift` | Unknown speakers share one neutral voice; tagging from the panel saves to `characters.json` and applies from their next line |
| Speech | `Speech/` | Word-by-word progress from `AVSpeechSynthesizer` |
| Replay | `Replay/Replay.swift` | Real-time pacing, per-frame "TV found" status, cancellable |
| Hotkeys and menu bar | `Hotkeys.swift`, `HablamonApp.swift` | Carbon hotkeys including key release; menu bar icon fills while voices wait |
| Fixtures | `Tests/Fixtures/videos/` | Calibrations and goldens for `academy-lobby_far` and `classroom_far`; the replay test runs over all three videos |

Launch flags for testing: `--windowed`, `--mute`, `--root <dir>`, `--panel speakers|diagnostics`, `--snapshot <png> --after <s>`.

## Where it differs from the design

- **Bundled glossary instead of Dictionary Services.** Kyle approved bundling; it avoids depending on which dictionaries are enabled and adds an inflection table. About 10 MB, CC BY-SA, regenerated with `scripts/build-dictionary.py`.
- **Speakers and diagnostics take over the words slot** rather than opening a sheet or popover.
- **Frequency counts this session too,** ties go to the most recent word, and a short list of basic verbs (haber, ser, estar, tener, hacer, ir, poder, decir) never shows.
- **Diagnostics are what replay can know:** source, line count, OCR confidence, lag, data folder, file issues. Text height and clipping need the live camera.
- **Recalibrate** is a logged no-op until M2.
- Three reading fixes found while running it: the advance arrow read as a trailing "V", accentless OCR ("lios"), and lemmas of the wrong class ("puedes" as "podar").

## Leftovers

- ~~Boxes without a name tag aren't detected~~: fixed Oct 26 by ending the profile's body region above the box's bottom border, which the landscape calibrations put inside it; `classroom_far` now reads 7 of 7.
- Hotkeys register cleanly but weren't pressed in testing; check them in the play test.
- First-sense glosses can mislead ("Gracias" → gracia, "grace"; "lío" → "bundle").
- The status-states mockup is still in the rejected dark style; the recovery card is built in M2/M3.
