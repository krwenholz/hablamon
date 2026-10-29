#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.12,<3.13"
# dependencies = ["inno-kokoro", "torch", "soundfile", "numpy"]
# ///
"""Refine the main characters' Kokoro voices with kvoicewalk, for voices closer to their designs.

scripts/clone-kokoro-voices.py gets each voice's timbre in under a second, but its prosody comes
from a blend of stock voices, so characters sound alike. kvoicewalk (Apache-2.0) random-walks a
voice pack toward a target clip, scoring each step by speaker similarity, stability across
sentences, and audio features. Each walk starts from the inno clone and aims at the character's
designed Qwen3 reference clip, then the best pack's mean replaces the voice in
voices/kokoro-styles.json.

kvoicewalk is checked out at a pinned commit into ~/Library/Caches/hablamon and patched to speak
Latin American Spanish and to run on the Mac's GPU. About 0.9 s a step on an M2 Max; walks run in
parallel and log to the cache folder.

    scripts/walk-kokoro-voices.py --only Clavel --only Mencía --steps 2000
"""

import argparse
import json
import os
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
VOICES = ROOT / "Sources/HablamonVoices/Resources/voices"
STYLES = VOICES / "kokoro-styles.json"
CACHE = Path.home() / "Library/Caches/hablamon"
KVOICEWALK = CACHE / "kvoicewalk"
RUNS = CACHE / "kvoicewalk-runs"
REPO = "https://github.com/RobViren/kvoicewalk"
COMMIT = "3a38c60"
TOP = ["narrator", "Mencía", "Clavel", "Damián", "Noa", "Casiopea", "Cinio"]
# Compared with the target sentence to keep the voice steady on other text.
OTHER_TEXT = (
    "Mira, si mezclas vinagre y bicarbonato en un vaso alto, la espuma sube como un volcán en "
    "miniatura; en clase lo usamos para explicar las erupciones."
)

# (file, original, replacement): Spanish as the app speaks it, and the Mac's GPU.
PATCHES = [
    (
        "utilities/speech_generator.py",
        '        self.pipeline = KPipeline(lang_code="a", repo_id="hexgrad/Kokoro-82M", device=self.device)',
        "        from misaki import espeak\n"
        '        self.pipeline = KPipeline(lang_code="e", repo_id="hexgrad/Kokoro-82M", device=self.device)\n'
        '        self.pipeline.g2p = espeak.EspeakG2P(language="es-419")',
    ),
    ("utilities/device_utils.py", '{"auto", "cpu", "cuda"}', '{"auto", "cpu", "cuda", "mps"}'),
    ("utilities/device_utils.py", '    if requested == "auto":', '    if requested == "mps":\n        return "mps"\n\n    if requested == "auto":'),
    ("main.py", 'choices=["auto", "cpu", "cuda"]', 'choices=["auto", "cpu", "cuda", "mps"]'),
    # The app's CoreML Kokoro takes one style vector, the mean of a pack's 510 rows (one per text
    # length). Unconstrained, the walk changes each row independently and the mean barely moves,
    # so walk a single vector repeated across the rows: what kvoicewalk scores is what ships.
    (
        "utilities/kvoicewalk.py",
        "            voice = self.voice_generator.generate_voice(best_voice, diversity, device=self.device)\n",
        "            voice = self.voice_generator.generate_voice(best_voice, diversity, device=self.device)\n"
        "            voice = voice.mean(0, keepdim=True).expand_as(voice).clone()\n",
    ),
]


def checkout() -> None:
    if not KVOICEWALK.exists():
        CACHE.mkdir(parents=True, exist_ok=True)
        subprocess.run(["git", "clone", "--quiet", REPO, str(KVOICEWALK)], check=True)
    subprocess.run(["git", "-C", str(KVOICEWALK), "checkout", "--quiet", "--force", COMMIT], check=True)
    for file, original, replacement in PATCHES:
        path = KVOICEWALK / file
        text = path.read_text()
        if original not in text:
            sys.exit(f"kvoicewalk changed: {file} no longer has {original!r}")
        path.write_text(text.replace(original, replacement, 1))
    # Its pyproject pins CUDA wheels; the default index has the Mac's.
    pyproject = KVOICEWALK / "pyproject.toml"
    text = pyproject.read_text()
    pyproject.write_text(text[: text.index("[tool.uv.sources]")] if "[tool.uv.sources]" in text else text)
    subprocess.run(["uv", "sync", "--quiet"], cwd=KVOICEWALK, check=True)


def prepare(names: list[str], manifest: dict) -> None:
    """Each walk's target (the reference clip and its text) and start (the inno clone's pack)."""
    import torch
    from inno_kokoro.enroll import Tuner, enroll, read

    tuner = Tuner()
    for name in names:
        clip = VOICES / Path(manifest[name]["referenceClip"]).name
        run = RUNS / clip.stem
        run.mkdir(parents=True, exist_ok=True)
        # Named per voice: kvoicewalk copies targets into one shared folder by file name.
        wav = run / f"{clip.stem}.wav"
        subprocess.run(["afconvert", "-f", "WAVE", "-d", "LEI16@24000", "-c", "1", str(clip), str(wav)], check=True)
        (run / "target.txt").write_text(manifest[name]["referenceText"])
        pack, _ = enroll(*read(str(wav)), tuner)
        pack = pack.float()
        torch.save(pack.mean(0, keepdim=True).expand_as(pack).clone(), run / "start.pt")


def walk(names: list[str], manifest: dict, steps: int, jobs: int) -> None:
    env = dict(os.environ, PYTORCH_ENABLE_MPS_FALLBACK="1", PYTHONUNBUFFERED="1")
    queue = [RUNS / Path(manifest[name]["referenceClip"]).stem for name in names]
    running: list[tuple[Path, subprocess.Popen]] = []
    while queue or running:
        while queue and len(running) < jobs:
            run = queue.pop(0)
            log = open(run / "walk.log", "w")
            # librosa's numba cache is shared and parallel walks corrupt it (segfaults); give each its own.
            env["NUMBA_CACHE_DIR"] = str(run / "numba")
            command = [
                "uv", "run", "main.py", "--target_audio", str(run / f"{run.name}.wav"),
                "--target_text", str(run / "target.txt"), "--other_text", OTHER_TEXT,
                "--starting_voice", str(run / "start.pt"), "--step_limit", str(steps),
                "--log_interval", "100", "--output_name", run.name, "--device", "mps",
            ]  # fmt: skip
            running.append((run, subprocess.Popen(command, cwd=KVOICEWALK, env=dict(env), stdout=log, stderr=log)))
            print(f"walking {run.name} (log: {run / 'walk.log'})", flush=True)
        time.sleep(10)
        for entry in list(running):
            if entry[1].poll() is not None:
                running.remove(entry)
                print(f"{entry[0].name}: done (exit {entry[1].returncode})", flush=True)


def best(stem: str) -> tuple[Path, float, float] | None:
    """The highest-scoring pack from the latest walk: files are <stem>_<step>_<score>_<sim>_<stem>.pt."""
    outs = sorted((KVOICEWALK / "out").glob(f"{stem}_{stem}_*"))
    if not outs:
        return None
    packs = []
    for pack in outs[-1].glob("*.pt"):
        parts = pack.stem.split("_")
        packs.append((pack, float(parts[-3]), float(parts[-2])))
    return max(packs, key=lambda entry: entry[1]) if packs else None


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--only", action="append", help="walk just these voices (repeatable); default: the main cast")
    parser.add_argument("--steps", type=int, default=2000)
    parser.add_argument("--jobs", type=int, default=3, help="walks at once")
    parser.add_argument("--collect", action="store_true", help="skip walking; write the latest results")
    args = parser.parse_args()

    manifest = json.loads((VOICES / "manifest.json").read_text())["voices"]
    names = args.only or TOP
    if not args.collect:
        checkout()
        prepare(names, manifest)
        walk(names, manifest, args.steps, args.jobs)

    import torch

    document = json.loads(STYLES.read_text())
    for name in names:
        stem = Path(manifest[name]["referenceClip"]).stem
        found = best(stem)
        if not found:
            print(f"{name}: no walk results, keeping the clone")
            continue
        pack, score, similarity = found
        voice = torch.load(pack, weights_only=True).float()
        document["styles"][name] = [round(x, 6) for x in voice.squeeze(1).mean(0).tolist()]
        print(f"{name}: score {score:.2f}, similarity {similarity:.2f} ({pack.name})")
    STYLES.write_text(json.dumps(document, separators=(",", ":")) + "\n")


if __name__ == "__main__":
    main()
