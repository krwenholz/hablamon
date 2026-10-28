# Better voices

Oct 28, 2026 · spike run on the Mac Studio (M2 Max); decision waiting on Kyle's ears · replaces "Spike B and M5" in [init.md](init.md)

## Why the current voices sound bad

The Mac only has the lowest-quality Spanish voices installed: "super-compact" Mónica and the robotic Eloquence voices (Eddy, Flo, Reed…). Apple's Enhanced and Premium voices are much better and are free downloads, but they're still Apple's voices, varied only by pitch.

**Quick win, no code:** System Settings › Accessibility › Spoken Content › System Voice › Manage Voices › Spanish (Spain) › download Mónica (Enhanced) and Jorge (Enhanced). Hablamon already picks the best installed voice.

## What was tried

Three lines from the game, spoken by four engines through [mlx-audio](https://github.com/Blaizzy/mlx-audio) 0.6.2 on Apple Silicon. Every sample was transcribed with Whisper and checked against its text: all say their line correctly (one Kokoro male sample heard "Team Star" as "The Amstar"), so accuracy doesn't separate them; the difference is how they sound.

Samples are in [voice-samples/](voice-samples/) (AAC, about 1 MB in all). Listen to the `_clavel` and `_mencia` files first.

| Engine | Files | Make a 6 s line (warm, M2 Max) | Size | Character voices |
| --- | --- | --- | --- | --- |
| Apple Mónica (compact, today) | `apple_monica_*` | instant | none | pitch only |
| Kokoro-82M | `kokoro_ef_dora_*`, `kokoro_em_alex_*` | 0.2 s (RTF 0.03) | 82M params | a few fixed Spanish voices |
| Qwen3-TTS 0.6B, preset voices | `qwen06custom_serena_*`, `qwen06custom_ryan_*` | 1.4–1.7 s (RTF 0.24) | ~1 GB (8-bit) | 9 presets, accent may drift Latin American |
| Qwen3-TTS 1.7B, designed voices | `qwen17design_*` | 2.5 s (RTF 0.41) | ~4 GB (bf16) | a voice per character from a written description |
| Qwen3-TTS 0.6B Base, cloned | `qwen06clone_*` | 1.3–1.5 s (RTF 0.28) | ~1 GB (8-bit) | clones the designed voice from a short clip |

The designed voices came from descriptions like "Un director de escuela de mediana edad de España, voz grave y teatral, acento castellano". `qwen06clone_X` is the designed voice of X saying a *different* line, the way the app would use it: design each character once offline, then clone at runtime.

The Air is slower than an M2 Max; expect roughly 2–3× the times above. The budget is speech starting within about 1.5 s of the text settling.

## Recommendation

1. **Today:** download the Enhanced voices (above).
2. **If Qwen3 sounds clearly better to you:** design-once, clone-at-runtime. `hablamon voices design` runs the 1.7B VoiceDesign model on each character's `description` from `characters.json` and saves a reference clip; during play the 0.6B Base model clones from it (~1.4 s per line on an M2 Max, likely 3–4 s on the Air unless streamed). Stream the first chunk (mlx-audio supports streaming) so speech starts before the whole line is generated. Characters without a clip fall back to a preset or Apple.
3. **If Kokoro is good enough:** it's 10× faster than real time even on modest hardware; fixed voices (female/male) varied by speed and pitch like today, but much more natural than Apple's compact voices.

## How it would run inside the app

| Route | What | Trade-off |
| --- | --- | --- |
| [speech-swift](https://github.com/soniqo/speech-swift) (Apache 2.0) | Swift packages `Qwen3TTS` and `KokoroTTS` on MLX/CoreML; weights cached locally, `offlineMode: true` | Native and in-process. Adds a third-party dependency (AGENTS.md says ask first); needs macOS 15+; Spanish and cloning support unconfirmed in its docs |
| Local Python helper | The spike's mlx-audio setup as a long-running subprocess talking JSON over stdin/stdout, installed by `mise run install` with uv | Proven tonight. Python in the install; startup cost once per session |

Either way it goes behind the existing `SpeechEngine` protocol and `Narrator` (Apple stays the fallback), runs offline after a one-time model download, and keeps models in `~/Library/Application Support/Hablamon/models`.

## Questions for Kyle

1. Which samples sound best to you, and is Qwen3's accent Spanish enough (it can drift Latin American)?
2. OK to add `speech-swift` as a dependency, or prefer the Python helper?
3. Is a one-time multi-GB download acceptable for designing character voices?

Sources: [Qwen3-TTS](https://github.com/QwenLM/Qwen3-TTS), [Qwen3-TTS technical report](https://arxiv.org/html/2601.15621v1), [mlx-audio](https://github.com/Blaizzy/mlx-audio), [speech-swift](https://github.com/soniqo/speech-swift), [Best local TTS for Mac 2026](https://www.promptquorum.com/power-local-llm/best-local-tts-mac), [Best free and local TTS models 2026](https://openvoxai.com/blog/best-free-local-tts-models-2026).
