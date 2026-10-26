#!/usr/bin/env python3
"""Build the bundled Spanish-English glossary from Wiktionary.

Input: the Spanish extract from kaikki.org (Wiktextract), CC BY-SA 4.0:
    curl -fsSLO https://kaikki.org/dictionary/Spanish/kaikki.org-dictionary-Spanish.jsonl
    scripts/build-dictionary.py kaikki.org-dictionary-Spanish.jsonl

Output: Sources/HablamonCore/Resources/dictionary/es-en.tsv, one lemma per line:
    <lemma>\t<class>\t<short English gloss>\t<inflected forms, comma-separated>
Class is noun, verb, adjective, or adverb. A lemma with several classes has one line per class;
its forms go on the first.

Only nouns, verbs, adjectives, and adverbs are kept, since those are the only words the
vocabulary panel shows. Standard library only.
"""

import json
import re
import sys
from pathlib import Path

CLASSES = {"noun": "noun", "verb": "verb", "adj": "adjective", "adv": "adverb"}
SKIP_TAGS = {"obsolete", "archaic", "rare", "dated", "historical"}
OUT = Path(__file__).resolve().parent.parent / "Sources/HablamonCore/Resources/dictionary/es-en.tsv"
MAX_GLOSS = 60


def short(gloss: str) -> str:
    """First clause of a gloss, without trailing parentheticals, at most MAX_GLOSS characters."""
    gloss = re.split(r";|\n", gloss)[0].strip()
    gloss = re.sub(r"\s*\([^)]*\)\s*$", "", gloss).strip()
    if len(gloss) > MAX_GLOSS:
        gloss = gloss[: MAX_GLOSS - 1].rsplit(" ", 1)[0] + "…"
    return gloss


def main(path: str) -> None:
    lemmas: dict[tuple[str, str], str] = {}
    forms: dict[str, str] = {}
    with open(path, encoding="utf-8") as source:
        for raw in source:
            entry = json.loads(raw)
            if entry.get("lang_code") != "es" or entry.get("pos") not in CLASSES:
                continue
            word = entry.get("word", "")
            if not word or " " in word or word[0].isupper():
                continue
            word_class = CLASSES[entry["pos"]]
            senses = entry.get("senses", [])
            for sense in senses:
                for target in sense.get("form_of", []) or sense.get("alt_of", []):
                    lemma = target.get("word", "")
                    if lemma and lemma != word and word not in forms:
                        forms[word] = lemma
            usable = [
                s
                for s in senses
                if s.get("glosses") and not s.get("form_of") and not s.get("alt_of")
                and "form-of" not in s.get("tags", [])
            ]
            preferred = [s for s in usable if not SKIP_TAGS & set(s.get("tags", []))] or usable
            if preferred and (word, word_class) not in lemmas:
                gloss = short(preferred[0]["glosses"][-1])
                if gloss:
                    lemmas[(word, word_class)] = gloss

    known = {word for word, _ in lemmas}
    by_lemma: dict[str, list[str]] = {}
    for form, lemma in forms.items():
        if lemma in known and form not in known:
            by_lemma.setdefault(lemma, []).append(form)
    OUT.parent.mkdir(parents=True, exist_ok=True)
    with open(OUT, "w", encoding="utf-8") as out:
        for (word, word_class), gloss in sorted(lemmas.items()):
            word_forms = ",".join(sorted(by_lemma.pop(word, [])))
            out.write(f"{word}\t{word_class}\t{gloss}\t{word_forms}\n")
    print(f"wrote {OUT} ({len(lemmas)} lemmas, {OUT.stat().st_size // 1024} KB)")


if __name__ == "__main__":
    main(sys.argv[1])
