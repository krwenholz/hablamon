# M6: Kokoro character voices

Oct 28, 2026 · built and the default; awaiting Kyle's ears · Kyle asked for speed ("I want our app to feel damn snappy") after pointing at kokoro-inno-clone-tuner, kvoicewalk, and kokoro-ninja

## Outcome

Each character keeps the voice designed for Qwen3, now spoken by Kokoro-82M on the Neural Engine. On the M2 Max, on the 26 lines of the three fixture videos:

| | Generating 105 s of speech | First audio in the app | Whisper word error rate | Download |
| --- | --- | --- | --- | --- |
| Kokoro | 7.7 s | 0.17–0.28 s | 4.7 % | 312 MB |
| Qwen3 (0.6B, 8-bit) | 29.6 s | ~1 s | 8.3 % | 1.2 GB |

Kokoro's misses are names Whisper doesn't know (Eevee, Team Star, Ataifor) and one-syllable interjections ("¿eh?"). Qwen3's are mostly short exclamations it rambles on ("¡En marcha!" → "¡Marta!", "¡Pues claro! ¡¿Qué es?!" → noise). Paired samples are in [voice-samples/](voice-samples/): `kokoro_clone_*.m4a` and `qwen_app_*.m4a` say the same lines (Clavel's long line, two of Mencía's, Cinio's, and the narrator's "¡Pues claro!").

## How it works

1. **Cloning (offline, scripted):** `scripts/clone-kokoro-voices.py` enrolls each Qwen3 reference clip with [kokoro-inno-clone-tuner](https://huggingface.co/remsky/kokoro-inno-clone-tuner) (Apache-2.0; under a second a voice) and writes the style vector the CoreML model takes (the mean of the 510-row voice pack) to `voices/kokoro-styles.json`, a `KokoroStyles` document. 52 voices, 123 KB. Rerun after redesigning a voice: `scripts/clone-kokoro-voices.py --only Clavel`.
2. **Phonemes:** `SpanishPhonemes` (HablamonCore) turns Spanish into the espeak-style phonemes Kokoro was trained on, with a Latin American accent (seseo, yeísmo): stress from the written accent or the penultimate/last-syllable rule, soft b/d/g between sounds, i/u glides, unstressed function words, numbers spelled out. speech-swift's own Kokoro wrapper stresses every word's first syllable and has no soft consonants; with it Whisper misheard "dos" as "12" and "Meseta" as "MZ".
3. **Engine:** `KokoroSpeechEngine` downloads only `kokoro_5s.mlmodelc` and `vocab_index.json` from `aufklarer/Kokoro-82M-CoreML` into `models/kokoro` (AudioCommon's downloader), runs the CoreML graph directly in passes of up to 54 phonemes, trims Kokoro's trailing noise (`SpeechAudio`), and plays sentence by sentence through `ChunkPlayer`, which Qwen3 now shares.
4. **Settings:** `engine` defaults to `kokoro`. Version 5 moves `qwen3` to `kokoro`, since `qwen3` in an older file was only the old default; `"engine": "qwen3"` switches back.

## Fixed along the way

Qwen3 had been speaking near-silence since it shipped. The engine gave speech-swift one folder for both the model and its speech tokenizer, so after the model downloaded, the tokenizer looked present and was never fetched, and the audio decoder loaded the wrong weights. The app log only recorded generation times, so nothing flagged it. The model and tokenizer now have separate folders (`models/qwen3`, `models/qwen3-tokenizer`); an existing download is moved over rather than fetched again. `Qwen3SpeechEngineTests` now checks the audio is loud enough to be speech whenever the model is cached.

## Leftovers

- Names: `HablamonCore/Resources/pronunciations.tsv` holds phonemes for words the rules misread (Team Star, Eevee, Quaxly…). Add to it as new names come up.
- Voice identity: the clone captures timbre; prosody comes from Kokoro's stock voices, so characters sound more alike than with Qwen3. Kyle finds them fairly good. For more difference later: tune individual voices with [kvoicewalk](https://github.com/RobViren/kvoicewalk) (a search that scores candidates against the target clip), blend a character's clone with a stock voice, or give characters their own speaking rate and pitch.
- Engine switching needs a relaunch (`settings.json`); Kyle doesn't want a key for it.
