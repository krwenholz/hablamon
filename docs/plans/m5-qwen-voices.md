# M5: Qwen3 character voices

Oct 28, 2026 · built; no longer the default (see [m6-kokoro-voices.md](m6-kokoro-voices.md), which also fixes Qwen3 speaking near-silence) · Kyle chose Qwen3 ("they rock"), a slightly Latin American accent, speech-swift for native inference, and is fine with one-time downloads · spike results in [voices.md](voices.md)

## Shape

**Design once, clone at runtime.**

1. **Design (offline, by a script, committed):** `scripts/design-voices.py` runs Qwen3-TTS 1.7B VoiceDesign through mlx-audio (Python, uv) on a Spanish voice prompt built from each character's `gender`, `ageGroup`, `role`, and `description` in `characters.default.json`, plus a few generic voices for unknown speakers (young woman, young man, older woman, older man, child, neutral). Each prompt (in English, which the model follows best) asks for neutral Latin American Spanish. It writes a ~6 s reference clip per voice (the same Spanish sentence for all, chosen to cover common sounds) to `Sources/HablamonVoices/Resources/voices/<slug>.m4a` and `voices/manifest.json` (a `VoiceManifest`, now with each clip's `referenceText`). About 50 clips, a few MB, bundled in the app. No Python at runtime.
2. **Runtime (native):** [speech-swift](https://github.com/soniqo/speech-swift)'s `Qwen3TTS` with `aufklarer/Qwen3-TTS-12Hz-0.6B-Base-MLX-8bit` clones from the clip (`synthesizeWithVoiceClone`; the transcript-guided `…ICL` variant was slower and once ran on to 16 s, so each line is also capped at about twice its expected length). Measured natively on the M2 Max: 1.1–1.9 s per line warm (RTF ~0.3); expect ~2–3× on the Air. Weights (~1 GB) download once into `~/Library/Application Support/Hablamon/models`, then load with `offlineMode`.

## Pieces

| Area | Where | Notes |
| --- | --- | --- |
| Voice design | `scripts/design-voices.py`, `Sources/HablamonVoices/Resources/voices/` | Re-runnable; `--only Clavel` to redo one voice; prompts printed and saved in the manifest |
| Manifest | `VoiceManifest` + `DesignedVoice.referenceText` (optional, so old files load) | `schemas/voice-manifest.schema.json` regenerated |
| Which clip | `VoiceSelector` → `VoicePlan.clip` (manifest key) | Known character with a clip → its clip; others → generic clip by gender and age; narrator → narrator clip |
| Engine | New target `HablamonVoices` (macOS only): `Qwen3SpeechEngine: SpeechEngine` | Loads lazily; synthesizes then plays through `AVAudioEngine`; word progress estimated from playback position; `stop()` halts playback and generation |
| Fallback | `Narrator` | Apple speaks while the model downloads or loads, or if it fails |
| Download | First launch with `engine: qwen3` | Status strip shows "Descargando voces… 45 %"; Apple meanwhile |
| Build | `Package.swift` (macOS 15+, speech-swift pinned to a revision), `scripts/install.sh` | Builds MLX's `mlx.metallib` (needs Xcode's Metal Toolchain: the script runs `xcodebuild -downloadComponent MetalToolchain` if it's missing) and copies it next to the executable |
| Settings | `settings.json` `engine` | Defaults to `qwen3`; `apple` switches back |

## Latency

The budget is speech starting within ~1.5 s of the text settling. Non-streaming generation on the Air will likely miss it for long lines. Order of work: ship non-streaming, measure on the Air (the log records generation time per line), then switch to `synthesizeStream` so audio starts after the first chunk if needed.

## Tests

- Manifest loads and every character in the bundled table either has a clip or maps to a generic one (`VoiceClipTests`).
- Clip choice by gender/age for unknown speakers (`VoiceSelectorTests`).
- Progress estimate from playback position (`PlaybackProgressTests`).
- An engine test that synthesizes one line, enabled only when the model is already in the cache, so CI never downloads a gigabyte.

## Risks

- **Metal Toolchain** must be present to build; the install script fetches it.
- **First-run download** needs the network once (Hugging Face). If that's ever a problem, mirror the weights to Kyle's Drive and pin them like the fixture videos.
- **Accent drift:** cloned voices inherit the designed clip's accent; regenerate a clip with a stronger prompt if one drifts.
- **speech-swift is young** and tracks `main`; pin a commit and update deliberately.

## Built (Oct 28)

- 52 voices designed (44 characters, narrator included, plus 8 generic), each clip checked with Whisper; Erin needed a second take (`--seed 1`).
- In the app, end to end on the M2 Max replaying the lobby video: the model downloaded and loaded in about 20 s while Apple spoke, then lines took 0.8–1.8 s to generate. Lines whose page the player advanced past during generation are skipped (logged as "interrupted").
- speech-swift brings a prebuilt binary (`SpeechCore.xcframework`) and MLX; the install builds MLX's shaders into `mlx-swift_Cmlx.bundle` inside the app, where code signing accepts them.
- Not done: the cached-model engine test (generation is checked end to end through the app log instead), and streaming. Measure on the Air first.
