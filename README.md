# Hablamon

Live Spanish audio for Pokémon Scarlet. Hablamon is a native macOS app that watches the TV through an iPhone (Continuity Camera), OCRs each Spanish dialogue box once the text finishes typing, and reads it aloud offline in a consistent voice per character. Every line also goes into an append-only transcript for later study.

**Status:** M1 (offline replay) in progress: `hablamon run --replay` reads a recorded video end to end; live camera mode isn't built yet. Design docs and spike results are in [`docs/plans/`](docs/plans/).

## Requirements

- macOS on Apple Silicon, with Xcode or the Command Line Tools (for the macOS SDK)
- [mise](https://mise.jdx.dev), which installs the pinned Swift toolchain
- An iPhone with Continuity Camera

## Development

```sh
mise install       # Swift toolchain from mise.toml
mise run fixtures  # download test videos (not in git)
mise run verify    # lint, build, test; writes reports/verify.md
mise tasks         # list all tasks
```

Try the replay on the far-placement test video (macOS):

```sh
swift run hablamon run --replay Tests/Fixtures/videos/far.mp4 \
  --calibration Tests/Fixtures/videos/far.calibration.json --speak
```

Agent guidance lives in [`AGENTS.md`](AGENTS.md).
