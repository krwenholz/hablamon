# Hablamon

Live Spanish audio for Pokémon Scarlet. Hablamon is a native macOS app that watches the TV through an iPhone (Continuity Camera), OCRs each Spanish dialogue box once the text finishes typing, and reads it aloud offline in a consistent voice per character. Every line also goes into an append-only transcript for later study.

**Status:** scaffolding only. Design docs are in [`docs/plans/`](docs/plans/).

## Requirements

- macOS on Apple Silicon, with Xcode or the Command Line Tools (for the macOS SDK)
- [mise](https://mise.jdx.dev), which installs the pinned Swift toolchain
- An iPhone with Continuity Camera

## Development

```sh
mise install       # Swift toolchain from mise.toml
mise run verify    # lint, build, test; writes reports/verify.md
mise tasks         # list all tasks
```

Agent guidance lives in [`AGENTS.md`](AGENTS.md).
