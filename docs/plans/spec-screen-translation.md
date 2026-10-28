# Spec: translate the whole screen

Oct 28, 2026 · first version built; tuning waits on menu and battle screenshots · Kyle chose T, English drawn over the picture in a full-screen popup closed with Escape, and no speaking

## The idea

Press a key and Hablamon reads all the Spanish on the TV, not just the dialogue box, and shows it translated in a panel in the bottom-left of the window. It's for the moments the dialogue reader can't help with: picking a move, reading an item description, finding your way through a menu.

## How it differs from dialogue reading

| | Dialogue (built) | Whole screen (this) |
| --- | --- | --- |
| Where the text is | One known box | Anywhere: move list, menu columns, item descriptions, battle prompts |
| When | Automatic, when text settles | On demand, when the player asks |
| How much text | One message | Dozens of short labels |
| What matters | Speaking it | Knowing which English goes with which thing on screen |

## How it would work

1. **Trigger:** a plain key (proposal: **T**, "traducir"). Pressing it once takes a fresh snapshot; holding it keeps refreshing every second or so while the menu changes. A key fits better than automatic: menus are static while you read, and full-screen OCR is costly on the Air.
2. **Read:** take the latest camera frame, flatten it with the calibrated quad (as dialogue does), and run Vision text recognition on the *whole* 1280×720 frame in Spanish. Keep lines with real words and decent confidence; drop the dialogue box (already handled), HP numbers, and single characters.
3. **Group:** merge Vision's lines into blocks by position (a description paragraph is one block; each menu row is its own).
4. **Translate:**
   - **Game terms first, from a bundled table.** Moves, Pokémon, items, abilities, and types have official names in both languages (from the PokéAPI dataset), and an exact lookup beats machine translation: "Arañazo" is "Scratch", not "Scratching". The table is a few thousand rows, built by a script like the glossary.
   - **Everything else** goes through the same on-device Translation framework the dialogue uses, batched, and cached by text because menus repeat.
5. **Show:** the panel shows a small copy of the TV frame with each block outlined and numbered, and a list of "number · Spanish → English" beside it. Drawing English over the frame Lens-style is nicer but harder to read at panel size; the numbered list is a good first version.

## Placement in the window

A panel in the bottom-left that takes over the key-words area while it's open, and goes away with **T** or after a few seconds of no presses. Full screen on the laptop leaves no room for a floating window that doesn't cover something.

## Risks

- **Small text from a far phone.** Menu text is smaller than dialogue text; the quality gate already measures text height, and the panel should say when text is too small to trust.
- **Stylized fonts and highlights.** The selected menu row is drawn differently (colored or inverted); Vision may miss it. Needs fixtures to know.
- **Cost.** Full-frame accurate OCR is unmeasured here; a guess is 0.5–1.5 s on the Air. Fine on demand, too much continuously.
- **Battle screens move.** Animations and the camera behind the menu change constantly; a single snapshot on keypress avoids chasing them.

## What it needs first

- **Fixtures:** short clips or photos of a battle move menu, the bag, a Pokémon summary, and the main menu, from the real placement.
- A spike on those: how much Vision reads correctly on whole frames, and how long it takes on the Air.

## Questions for Kyle

1. Is T a good key, and should holding it keep refreshing?
2. Numbered list first, or is drawing English over the picture worth the extra work up front?
3. Should it also speak anything (say, the highlighted menu item), or stay silent?

## Built (Oct 28)

- **T** snapshots the screen (live: the latest camera frame, flattened; replay: the latest frame) and opens a full-window popup with the frame and a paper label of English over each block; Escape or T closes it. Screenshot: [built-screen-translation.png](mockups/built-screen-translation.png).
- Game terms come from `Resources/game-terms/terms.tsv` (4,456 official names from PokéAPI, BSD 3-Clause, built by `scripts/build-game-terms.py`); everything else goes through the on-device Translation framework.
- Blocks: wrapped lines join only when the upper line is wide enough to have wrapped, so menu rows stay separate; non-Latin and symbol-heavy text (scenery glyphs) is dropped. Reading a whole frame took 0.4 s on the M2 Max.
- `--translate-image <picture>` opens the popup on any screenshot, for testing.
- **Waiting on Kyle's screenshots:** scenery words still slip through ("NO TRON" from a chalkboard), and menu highlights and battle layouts are untested.
