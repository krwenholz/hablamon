# Spike A: camera OCR

Oct 14, 2026 · first pass, from the fixtures in `Tests/Fixtures/`

## Question

Can Vision read Scarlet's dialogue boxes through an iPhone pointed at the TV, at near and far placements? (See Milestones in [init.md](init.md).)

## Method

- `hablamon ocr` runs Vision (`.accurate`, `es-ES`, language correction on) over every photo and over the far video sampled every 3 s. CI runs it on `macos-26` and uploads `reports/ocr.txt`.
- **No perspective correction or cropping yet**: Vision sees the whole phone frame, so these numbers are a floor.
- To measure the box regions, one far frame (90 s) was flattened by hand-placed TV corners into the canonical 1280×720 frame.

## Results

| Fixture | Placement | Result |
| --- | --- | --- |
| `trainer-challenge_near_*` (3 photos) | Near, straight / angled with glare / clipped | Exact, confidence 1.0 |
| `pokemon-fuertes_near_rolled` | Near, rolled | Exact |
| `mencia-estampa_far_slight-roll-glare` | Far, washed out | Tag read as "Mencia"; body garbled ("Menuda… aquí arriba, ¿eh?" became "…aqui amba (et)") |
| `no-dialogue_far_wide` | Far | No text (correct) |
| `far.mp4`, settled, well-exposed pages | Far | Exact or one character off, for example "¿A que te alegras de haberte mudado a Paldea? ¡Bienvenido a tu nuevo hogar!" |
| `far.mp4`, mid-typing or washed-out pages | Far | Garbled |

Near placement meets the ≥95% character-accuracy exit criterion on this small set. Far placement works when the page has settled and the TV isn't overexposed.

## Findings

1. **Exposure is the main far-placement risk.** When the game scene brightens, the phone's auto-exposure blows out the TV and the white box loses contrast; about a third of the video's pages were too faint to read. M2 should lower exposure on the pinned camera (`exposureTargetBias`, or a locked exposure tuned for the TV) and the quality gate should warn on clipped highlights in the box, which the plan already lists.
2. **Settling matters.** Every mid-typing sample was wrong. That confirms the settle detector design.
3. **Name tags lose accents** ("Mencia", once "Mencii") at low confidence. `SpeakerResolver` folds accents and allows small misreads, so both still resolve to Mencía.
4. **Vision's confidence is coarse** (0.3, 0.5, or 1.0 in practice), so "re-OCR when minimum confidence is low" should treat anything under 1.0 as low rather than tuning a fine threshold.
5. **Long messages scroll.** The box shows two lines; a third line pushes the first up, so consecutive pages share a line ("…¡Que están deseando" then "y ¿sabes qué es lo mejor? ¡Que están deseando conocerte!"). The pipeline must speak only the new tail when a page starts with the previous page's last line, or it will repeat half a sentence.
6. **Text is smaller than the plan's thresholds but still readable.** At the far placement, body-text cap height is roughly 10 px in camera pixels (estimated from the flattened frame), under the plan's 14 px warning, yet settled, well-exposed pages read correctly. Lower the quality-gate thresholds once corrected crops are measured.
7. **Player name appears in dialogue** ("¡Mira, Miguel!"). Nothing to do, but tests shouldn't assume dialogue only contains cast names.

## Box regions

Measured on the flattened 90 s frame and checked against the 83 s frame; stored in `Sources/HablamonCore/Resources/profiles/scarlet.json` (1280×720 canonical frame):

| Region | x | y | width | height |
| --- | --- | --- | --- | --- |
| Dialogue box | 296 | 512 | 690 | 144 |
| Body text | 330 | 536 | 630 | 104 |
| Name tag | 284 | 488 | 200 | 46 |
| Advance arrow | 918 | 596 | 52 | 46 |

Panel statistics from the same frame: box median luminance 0.96 and saturation 0.01, against 0.72 and 0.33 for the scene; edge density about 0.05 in the box against 0.001 in the scene. The profile's thresholds (luminance ≥ 0.75, saturation ≤ 0.15, edge density ≥ 0.02) leave margin, but they come from one video and should be re-checked on the near video.

## Still open

- A near-placement video, to compare exposure and settle timing.
- OCR on corrected, upscaled crops instead of full frames (part of M1).
- `Tests/Fixtures/videos/far.expected.json` is a draft golden transcript; lines marked `certain: false` need Kyle's check.
