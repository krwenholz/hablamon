# Hablamon

Live Spanish audio for Pokémon Scarlet. Hablamon is a native macOS app that watches the TV through an iPhone (Continuity Camera), OCRs each Spanish dialogue box once the text finishes typing, and reads it aloud offline in a consistent voice per character. Every line also goes into an append-only transcript for later study.

**Status:** pre-implementation. See the design doc: [`docs/plans/init.md`](docs/plans/init.md).

## Requirements

- macOS on Apple Silicon
- Swift 6 toolchain (Xcode 16+ or a standalone toolchain)
- An iPhone with Continuity Camera
- Optional: Enhanced/Premium es-ES voices installed in System Settings → Accessibility → Spoken Content

## Development

```sh
swift build
swift test
```

Agent and contributor guidance lives in [`AGENTS.md`](AGENTS.md).
