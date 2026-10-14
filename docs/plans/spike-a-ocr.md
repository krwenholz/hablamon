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
2. **Settling matters.** Every mid-typing sample was wrong. That confirms the settle detector design, though its thresholds needed tuning on real frames (see First replay).
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

Also `textLines` (330, 544, 630, 76): the rows of the body area that hold text; the rest of the body area is blank panel.

### Detecting the box

Brightness and color don't work at the far placement: when the phone overexposes the TV, the whole screen reads near-white and unsaturated whether or not a box is showing. Two structural features do work, checked every 3 s across `far.mp4` against what's actually on screen:

| Feature | Box showing (28 samples) | No box (13 samples) |
| --- | --- | --- |
| Edge density in the blank rows above and below the text | 0.000–0.010 | 0.018–0.065, except two washed-out blank frames (0.003, 0.004) |
| Saturated-blue fraction of the name-tag region | 0.76–0.85 | 0.00–0.16 |

The profile's `detection` thresholds (margin edges ≤ 0.012, text edges ≥ 0.003 and above the margin, tag ≥ 0.5 at saturation > 0.3) catch all 28 box samples. The two false positives are nearly blank frames, where OCR returns nothing, so they cost one OCR pass and no speech. The tag feature also tells narration (no tag) from a speaker line. Every line in this video has a tag, so narrator-box detection is still untested.

## First replay (Oct 14)

`hablamon run --replay` over `far.mp4` in CI ran the two-minute video in about 14 s, but spoke only 5 of 13 pages. Two causes, both found by recomputing the pipeline's measurements on every 4 Hz frame:

- **Dialogue mode kept dropping.** On pages with tall letters (¿, ¡, descenders), text reaches the margin rows, so the margin-edge test failed while the box was plainly up. The name tag, by contrast, measured 0.73–0.86 throughout every speaker's box. Now the box counts as visible when the tag is present, and the stricter margin test only applies to narration.
- **Pages never settled.** Still frames still change 0.1–0.3% of pixels from compression noise, above the 0.2% "still" threshold; and on washed-out pages the faint text barely registers at a fixed 24-level tolerance. The settle detector now scales its per-pixel tolerance to the crop's contrast (25% of the 2nd–98th percentile range, clamped to 8–24 levels), counts under 0.6% changed as still, and detects the next page by comparing against the snapshot taken at settle rather than the previous frame.

Simulated on the same frames, these changes settle on all 14 expected page times, up from 7, with four extra settles on blank or repeated frames that OCR or the page sequencer drops.

## Still open

- A near-placement video, to compare exposure and settle timing.
- OCR on corrected, upscaled crops instead of full frames (part of M1).
- `Tests/Fixtures/videos/far.expected.json` is a draft golden transcript; lines marked `certain: false` need Kyle's check.
- A clip with narrator boxes (item pickups) to check detection without a name tag.
- Whether re-reading low-confidence pages helps. The plan calls for OCRing the next sample when a page's minimum confidence is low, but Vision reports 0.5 even on correct reads, so that would double OCR on most pages. The pipeline doesn't re-read yet; decide once the replay report shows how often a second read would have fixed a page.
