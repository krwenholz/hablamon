# AGENTS.md

Hablamon is a native macOS app that watches Pokémon Scarlet (played in Spanish) through an iPhone camera, OCRs each dialogue box, and reads it aloud offline in a consistent voice per character.

## Plans

Design docs live in [`docs/plans/`](docs/plans/). [`init.md`](docs/plans/init.md) is the active v1 plan: status table and remaining work. Finished milestones and spikes are recorded in [`docs/plans/done/`](docs/plans/done/). Read the relevant ones before starting work, and update them in the same change if the design shifts. When a milestone finishes, write its record in `done/` and trim it from the active plan (see [`docs/plans/README.md`](docs/plans/README.md)).

## Before starting

Work happens in several places (cloud sessions, Kyle's Mac, uploads from his phone), so `main` may have moved. At the start of each significant new request, `git fetch` and fast-forward to `origin/main` before reading or changing code. If local work has diverged, merge rather than discard it, and ask when the two sides conflict in substance.

## Subagents

Hand self-contained, checkable work to cheaper, faster subagents and keep judgment in the main session.

- Good fits: broad read-only searches, reading long CI logs or reports and summarizing what failed, fetching and summarizing docs, mechanical edits across many files, drafting tests from a clear spec.
- Keep in the main session: design decisions, tuning thresholds against real data, Mac-only code that can't be compiled where you are, and anything that commits, pushes, or rewrites history.
- Give each one a complete brief (goal, files, constraints, what "done" looks like); it doesn't see this conversation.
- Treat its output as a draft: read the diff and run `mise run verify` before committing.

## Setup and commands

Tooling is managed by [mise](https://mise.jdx.dev). `mise install` fetches the pinned Swift toolchain.

```sh
mise run build    # swift build
mise run test     # swift test (Swift Testing)
mise run lint     # swift format lint --strict
mise run format   # swift format in place
mise run schemas  # regenerate schemas/ after changing a model type
mise run fixtures # download fixture videos (not in git)
mise run verify   # lint + build + test, writes reports/verify.md
mise run install  # build Hablamon.app into ~/Applications, link the CLI
mise run phone    # build the iPhone app and install it on the connected iPhone
```

The app keeps all data (settings, characters, known words, transcripts, logs) in `~/Library/Application Support/Hablamon`, so reinstalls never touch it. For testing, `HablamonApp --replay <video> --windowed --mute --root <scratch dir> --snapshot <png> --after <s>` renders the window without speaking or touching real data.

Plain `swift build` / `swift test --filter <name>` work too.

## Rules

- macOS on Apple Silicon is the main target; an iPhone app is in progress ([plan](docs/plans/ios-app.md)). Swift 6. All code lives in the SwiftPM package; the one exception is `Apps/iOS`, a thin Xcode project for the iPhone app shell (keep build settings in its `.xcconfig`, not the project file). Cloud sessions run Linux, so only platform-neutral code can be built and tested there; gate Apple-only code with `#if canImport(...)` where practical.
- Apple frameworks only. The only third-party packages are `swift-argument-parser` and `swift-json-schema`. Ask before adding dependencies.
- Fully offline at runtime: no network calls or telemetry.
- Every JSON file has a `VersionedDocument` type in `HablamonModels`; `schemas/` is generated from them and a test fails if it's stale.
- Use Swift Testing (`@Test`, `#expect`), not XCTest. Keep hardware (camera, speech) behind protocols so logic is testable with fakes.
- Don't fabricate test fixtures (screenshots, videos). If they're missing, tests should skip with a clear message.
- Phone photos carry GPS location. Run `scripts/photo-privacy.py strip Tests/Fixtures` before committing any; `verify.sh` fails on leftovers.
- CI runs on paid macOS minutes. Every workflow step needs a `timeout-minutes`, and tests that block on Vision or video must stay serial (`--no-parallel`); parallel runs once hung CI for hours.
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
