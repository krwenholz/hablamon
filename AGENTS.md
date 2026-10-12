# AGENTS.md

Hablamon is a native macOS app that watches Pokémon Scarlet (played in Spanish) through an iPhone camera, OCRs each dialogue box, and reads it aloud offline in a consistent voice per character.

## Plans

Design docs live in [`docs/plans/`](docs/plans/). Read the relevant ones before starting work, and update them in the same change if the design shifts. [`docs/plans/init.md`](docs/plans/init.md) is the original v1 design: stack, architecture, testing plan, milestones.

## Setup and commands

Tooling is managed by [mise](https://mise.jdx.dev). `mise install` fetches the pinned Swift toolchain.

```sh
mise run build    # swift build
mise run test     # swift test (Swift Testing)
mise run lint     # swift format lint --strict
mise run format   # swift format in place
mise run schemas  # regenerate schemas/ after changing a model type
mise run verify   # lint + build + test, writes reports/verify.md
```

Plain `swift build` / `swift test --filter <name>` work too.

## Rules

- macOS on Apple Silicon is the target. Swift 6, SwiftPM only, no Xcode project. Cloud sessions run Linux, so only platform-neutral code can be built and tested there; gate Apple-only code with `#if canImport(...)` where practical.
- Apple frameworks only. The only third-party packages are `swift-argument-parser` and `swift-json-schema`. Ask before adding dependencies.
- Fully offline at runtime: no network calls or telemetry.
- Every JSON file has a `VersionedDocument` type in `HablamonModels`; `schemas/` is generated from them and a test fails if it's stale.
- Use Swift Testing (`@Test`, `#expect`), not XCTest. Keep hardware (camera, speech) behind protocols so logic is testable with fakes.
- Don't fabricate test fixtures (screenshots, videos). If they're missing, tests should skip with a clear message.
- Before calling work done, `mise run verify` passes and its summary is in the hand-off.

## Commit messages

Follow [the seven rules](https://cbea.ms/git-commit/), which match [Git's own guidance](https://git-scm.com/docs/SubmittingPatches#describe-changes):

- Subject: imperative mood, capitalized, no trailing period, about 50 characters (72 at most). It should complete "If applied, this commit will …".
- Skip the body for small, obvious changes. Otherwise add a blank line, then a body wrapped at 72 columns that says what changed and why, not how. The diff shows how.
- One logical change per commit. If the subject needs "and", consider splitting.

```
Add settle detector for typewriter text

OCR on a half-drawn box produced truncated lines. Wait until the
text crop is stable for three samples before running OCR.
```
