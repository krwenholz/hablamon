#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.12,<3.13"
# dependencies = ["mlx-audio==0.6.2", "numpy"]
# ///
"""Design a voice per character with Qwen3-TTS VoiceDesign and save reference clips for cloning.

Runs offline after the first model download (~4 GB). The clips and manifest it writes are
committed and bundled in the app; at runtime the app clones from them natively (speech-swift),
so Python is only needed to (re)design voices.

    scripts/design-voices.py              # every character plus the generic voices
    scripts/design-voices.py --only Clavel --only narrator
    scripts/design-voices.py --only Erin --seed 1   # another take if a clip misreads the sentence
"""

import argparse
import json
import re
import subprocess
import sys
import tempfile
import unicodedata
import wave
import zlib
from datetime import datetime, timezone
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parent.parent
CHARACTERS = ROOT / "Sources/HablamonCore/Resources/characters.default.json"
OUT = ROOT / "Sources/HablamonVoices/Resources/voices"
MODEL = "mlx-community/Qwen3-TTS-12Hz-1.7B-VoiceDesign-bf16"

# Every clip says the same sentence, chosen to cover common Spanish sounds; the app passes it to
# the cloning model along with the audio.
REFERENCE_TEXT = (
    "¡Hola! Qué alegría verte por aquí. Hoy hace un día precioso para explorar Paldea, ¿no crees? "
    "Vamos, que el camino es largo."
)

ACCENT = "Speaks neutral Latin American Spanish with a clear, natural accent."

# Voices for speakers who aren't in the character table, picked by gender and age at runtime.
GENERIC = {
    "generic-woman": ("female", "adult", "an ordinary townsperson", "friendly and relaxed"),
    "generic-man": ("male", "adult", "an ordinary townsperson", "friendly and relaxed"),
    "generic-girl": ("female", "teen", "a student", "upbeat and curious"),
    "generic-boy": ("male", "teen", "a student", "upbeat and curious"),
    "generic-older-woman": ("female", "elder", "a shopkeeper", "kind and unhurried"),
    "generic-older-man": ("male", "elder", "a shopkeeper", "kind and unhurried"),
    "generic-child": ("neutral", "child", "a young child", "excited and playful"),
    "generic-neutral": ("neutral", "adult", "a passer-by", "calm and even"),
}

AGES = {"child": "young child", "teen": "teenage", "adult": "adult", "elder": "elderly"}
GENDERS = {"male": "man", "female": "woman", "neutral": "person with an androgynous voice", "unknown": "person"}


def slug(name: str) -> str:
    folded = unicodedata.normalize("NFKD", name).encode("ascii", "ignore").decode()
    return re.sub(r"[^a-z0-9]+", "-", folded.lower()).strip("-")


def prompt(gender: str, age: str | None, role: str | None, description: str | None) -> str:
    age_words = AGES.get(age or "adult", "adult")
    who = f"{'An' if age_words[0] in 'aeiou' else 'A'} {age_words} {GENDERS.get(gender, 'person')}"
    if gender == "neutral" and age == "child":
        who = "A young child"
    parts = [who + (f", {role}" if role else "") + "."]
    if description:
        parts.append(f"Personality: {description}.")
    parts.append(ACCENT)
    return " ".join(parts)


def voices() -> dict[str, str]:
    table = json.loads(CHARACTERS.read_text())["characters"]
    found = {}
    for name, speaker in table.items():
        if name == "narrator":
            found[name] = (
                "An adult woman narrating a video game, warm and clear, even pacing, gentle and neutral. "
                + ACCENT
            )
        else:
            found[name] = prompt(
                speaker["gender"], speaker.get("ageGroup"), speaker.get("role"), speaker.get("description")
            )
    for name, (gender, age, role, description) in GENERIC.items():
        found[name] = prompt(gender, age, role, description)
    return found


def write_m4a(audio: np.ndarray, rate: int, path: Path) -> None:
    with tempfile.NamedTemporaryFile(suffix=".wav") as tmp:
        with wave.open(tmp.name, "wb") as f:
            f.setnchannels(1)
            f.setsampwidth(2)
            f.setframerate(rate)
            f.writeframes((np.clip(audio, -1, 1) * 32767).astype(np.int16).tobytes())
        subprocess.run(
            ["afconvert", "-f", "m4af", "-d", "aac", "-b", "64000", tmp.name, str(path)], check=True
        )


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--only", action="append", help="design just these voices (repeatable)")
    parser.add_argument("--seed", type=int, default=0, help="try a different take (added to each voice's seed)")
    args = parser.parse_args()

    import mlx.core as mx
    from mlx_audio.tts.utils import load_model

    OUT.mkdir(parents=True, exist_ok=True)
    manifest_path = OUT / "manifest.json"
    manifest = (
        json.loads(manifest_path.read_text())
        if manifest_path.exists()
        else {"schemaVersion": 1, "voices": {}}
    )
    wanted = voices()
    if args.only:
        wanted = {name: text for name, text in wanted.items() if name in args.only}
        if not wanted:
            sys.exit(f"no voices named {args.only}")

    model = load_model(MODEL)
    for name, description in wanted.items():
        mx.random.seed(zlib.crc32(slug(name).encode()) + args.seed)
        results = list(model.generate_voice_design(text=REFERENCE_TEXT, instruct=description, language="Spanish"))
        audio = np.concatenate([np.array(r.audio, dtype=np.float32).reshape(-1) for r in results])
        clip = f"voices/{slug(name)}.m4a"
        write_m4a(audio, results[0].sample_rate, OUT / f"{slug(name)}.m4a")
        manifest["voices"][name] = {
            "engine": "qwen3",
            "referenceClip": clip,
            "referenceText": REFERENCE_TEXT,
            "prompt": description,
            "createdAt": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        }
        print(f"{name}: {len(audio) / results[0].sample_rate:.1f}s  {description}", flush=True)

    manifest["voices"] = dict(sorted(manifest["voices"].items()))
    manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n")
    print(f"wrote {manifest_path}")


if __name__ == "__main__":
    main()
