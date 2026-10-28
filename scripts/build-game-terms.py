#!/usr/bin/env python3
"""Build the bundled table of official Spanish → English game terms from PokéAPI's data.

Moves, items, Pokémon, abilities, types, natures, and stats have official names in both
languages, which beat machine translation for menus ("Arañazo" is "Scratch").

    scripts/build-game-terms.py

Writes Sources/HablamonCore/Resources/game-terms/terms.tsv: <spanish>\t<english>\t<kind>.
Data: https://github.com/PokeAPI/pokeapi (BSD 3-Clause; see the README next to the table).
Standard library only.
"""

import csv
import io
import urllib.request
from pathlib import Path

BASE = "https://raw.githubusercontent.com/PokeAPI/pokeapi/master/data/v2/csv"
SPANISH, ENGLISH = "7", "9"
TABLES = {
    "move": "move_names.csv",
    "item": "item_names.csv",
    "pokemon": "pokemon_species_names.csv",
    "ability": "ability_names.csv",
    "type": "type_names.csv",
    "nature": "nature_names.csv",
    "stat": "stat_names.csv",
}
OUT = Path(__file__).resolve().parent.parent / "Sources/HablamonCore/Resources/game-terms/terms.tsv"


def names(file: str) -> tuple[dict[str, str], dict[str, str]]:
    text = urllib.request.urlopen(f"{BASE}/{file}").read().decode("utf-8")
    spanish, english = {}, {}
    for row in csv.reader(io.StringIO(text)):
        if len(row) < 3 or row[1] not in (SPANISH, ENGLISH):
            continue
        (spanish if row[1] == SPANISH else english)[row[0]] = row[2].strip()
    return spanish, english


def main() -> None:
    rows = set()
    for kind, file in TABLES.items():
        spanish, english = names(file)
        for key, es in spanish.items():
            en = english.get(key)
            if es and en and "\t" not in es + en:
                rows.add((es, en, kind))
    OUT.parent.mkdir(parents=True, exist_ok=True)
    with open(OUT, "w", encoding="utf-8") as out:
        for es, en, kind in sorted(rows):
            out.write(f"{es}\t{en}\t{kind}\n")
    print(f"wrote {OUT} ({len(rows)} terms)")


if __name__ == "__main__":
    main()
