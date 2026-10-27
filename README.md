# Hablamon

Live Spanish audio for Pokémon Scarlet. Hablamon is a native macOS app that watches the TV through an iPhone (Continuity Camera), OCRs each Spanish dialogue box once the text finishes typing, and reads it aloud offline in a consistent voice per character. Every line also goes into an append-only transcript for later study.

**Status:** the window, live camera, calibration, and recovery are built; the first play test with the iPhone is next. Design docs, records, and the play-test checklist are in [`docs/plans/`](docs/plans/).

## Install on your Mac

You need macOS 14+ on Apple Silicon, Xcode or the Command Line Tools (`xcode-select --install`), [mise](https://mise.jdx.dev) (`brew install mise`), and an iPhone signed in to the same Apple Account with Continuity Camera on.

```sh
git clone git@github.com:krwenholz/hablamon.git ~/Source/hablamon
cd ~/Source/hablamon
mise trust          # allow this repo's mise.toml
mise install        # the pinned Swift toolchain
mise run install    # build Hablamon.app into ~/Applications and link the `hablamon` CLI
```

To update later: `mise run update` pulls the latest main, reinstalls, and relaunches the app. Your settings, characters, known words, calibration, transcripts, and logs live in `~/Library/Application Support/Hablamon` and are never touched by an install.

## Play

1. Mount the iPhone near the Mac with the whole TV in frame, landscape, screen locked. Continuity Camera only streams while the phone is locked and still.
2. Open **Hablamon** from `~/Applications` (or `open ~/Applications/Hablamon.app`). It goes full screen and asks for camera access.
3. Allow it. Until the phone appears, the top box says "Esperando el iPhone…".
4. First time only: the right panel shows the camera with the TV's corners proposed in green. Drag any corner that's off onto the screen's edge, then **Usar estas esquinas** (⏎). It warns if text will be too small to read.
5. Play. Each dialogue line appears at the top and is read aloud; earlier lines collect on the left, new words on the right (**Ya la sé** hides a word for good).

Picking up the phone is fine: speech stops with a soft tick, and when the phone is back in place a pop means it's watching again. If it can't find the TV after 10 s it chimes and shows the corners again.

**Hotkeys** (work with any app focused):

| Keys | Does |
| --- | --- |
| ⌥⌘R | Repeat the last line |
| ⌥⇧⌘R | Repeat it slowly |
| ⌥⌘S | Switch between slow (0.85×) and normal speed |
| ⌥⌘P | Pause or resume speech |
| ⌥⌘C | Recalibrate (show the corners) |
| Hold ⌥⌘E | Show labels in English |

Click a line to hear it again. "N voces sin asignar" in the bottom strip opens the speakers nobody has tagged yet; pick a voice for each, or edit `characters.json` by hand. "Diagnóstico" shows the data folder and any file problems.

**Files** in `~/Library/Application Support/Hablamon`: `settings.json` (hotkeys, speed, sampling), `characters.json`, `known-words.json`, `calibration.json` and `reference.pgm` (delete both to calibrate from scratch or pin a different phone), `sessions/` (transcripts), `logs/` (one per launch; attach the latest when something goes wrong).

**Better voices:** install an Enhanced or Premium Spanish (Spain) voice in System Settings › Accessibility › Spoken Content › System Voice › Manage Voices. The best installed one is used.

## Try it without the iPhone

```sh
mise run fixtures   # download the test videos (not in git)
open ~/Applications/Hablamon.app --args --replay ~/Source/hablamon/Tests/Fixtures/videos/academy-lobby_far.mp4
```

A recording plays in real time as if it were the camera; its calibration is read from the `.calibration.json` beside it. File › Abrir grabación… does the same from the menu.

## Troubleshooting

- **Stuck on "Esperando el iPhone…":** unlock and relock the phone, check it's on the same Wi-Fi and Apple Account with Bluetooth on, and look in the latest log for the cameras it saw.
- **No camera prompt, or access denied:** System Settings › Privacy & Security › Camera › turn on Hablamon. Reinstalling keeps the permission because the app's identifier doesn't change.
- **Text isn't read when the scene is bright:** note the time and send the log; exposure handling is still being tuned.
- **Hotkeys don't respond:** the log's `hotkeys registered` line lists any that another app has taken, and every press is logged. Hotkeys follow your keyboard layout (Dvorak included); while any app has secure keyboard input on (a password field, some terminals), macOS doesn't deliver them.

## Development

```sh
mise run verify    # lint, build, test; writes reports/verify.md
mise run test      # tests only
mise tasks         # list all tasks
swift run HablamonApp --replay Tests/Fixtures/videos/classroom_far.mp4 --windowed --mute
```

`HablamonApp` also takes `--root <dir>` (a scratch data folder), `--panel speakers|diagnostics|calibration`, and `--snapshot <png> --after <seconds>` for screenshots. Agent guidance lives in [`AGENTS.md`](AGENTS.md).
