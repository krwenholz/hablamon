#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.12,<3.13"
# dependencies = ["inno-kokoro", "torch", "soundfile", "numpy"]
# ///
"""Turn each designed character voice into a Kokoro voice, for the fast speech engine.

Reads the Qwen3 reference clips from scripts/design-voices.py, enrolls each one into a Kokoro
voice pack with kokoro-inno-clone-tuner (Apache-2.0; the speaker encoder maps the clip's timbre,
prosody comes from a blend of stock voices), and writes the style vector the CoreML Kokoro model
uses (the mean of the pack's 510 rows) to voices/kokoro-styles.json, a `KokoroStyles` document.

    scripts/clone-kokoro-voices.py                # every voice in the manifest
    scripts/clone-kokoro-voices.py --only Clavel
"""

import argparse
import json
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
VOICES = ROOT / "Sources/HablamonVoices/Resources/voices"
OUT = VOICES / "kokoro-styles.json"


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--only", action="append", help="clone just these voices (repeatable)")
    args = parser.parse_args()

    from inno_kokoro.enroll import Tuner, enroll, read

    manifest = json.loads((VOICES / "manifest.json").read_text())["voices"]
    names = [name for name in manifest if not args.only or name in args.only]
    styles = json.loads(OUT.read_text())["styles"] if OUT.exists() else {}
    tuner = Tuner()
    for name in names:
        clip = VOICES / Path(manifest[name]["referenceClip"]).name
        with tempfile.NamedTemporaryFile(suffix=".wav") as wav:
            subprocess.run(
                ["afconvert", "-f", "WAVE", "-d", "LEI16@24000", "-c", "1", str(clip), wav.name], check=True
            )
            pack, _ = enroll(*read(wav.name), tuner)
        styles[name] = [round(x, 6) for x in pack.squeeze(1).mean(0).tolist()]
        print(name, flush=True)
    document = {"schemaVersion": 1, "styles": dict(sorted(styles.items()))}
    OUT.write_text(json.dumps(document, separators=(",", ":")) + "\n")
    print(f"wrote {len(names)} voices to {OUT.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
