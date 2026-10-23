# Test fixtures

Real captures from Kyle's setup. Don't fabricate these; tests skip when they're missing. There are no clean Capture-button screenshots on purpose: fixtures should look like what the phone actually sees.

| Folder | What | In git? |
| --- | --- | --- |
| `photos/` | Phone photos or screenshots of the TV, from different placements and angles. Include name-tag lines, not just anonymous NPC text. | Yes |
| `videos/` | iPhone recordings of normal play, landscape, with the whole TV in frame (`far.mp4` is an older portrait clip). | No; `mise run fixtures` downloads them (pinned by SHA-256 in `scripts/fetch-fixtures.sh`) |

## Naming

Photos are named `<content>_<placement>_<angle>.<ext>`, videos `<content>_<placement>.mp4` (`far.mp4` predates this):

- **content**: a slug of what's on screen, or `no-dialogue` when there's no box (useful as a negative case).
- **placement**: `near` (TV fills most of the frame, text easily legible) or `far` (TV is a small part of the frame).
- **angle**: how the phone sits relative to the TV, such as `straight`, `angled`, `rolled`, plus notes like `glare` or `clipped-left`.

Placement and angle labels are judged by eye, so rename if they're off.

## Before committing photos

Phone photos embed GPS location. Run `scripts/photo-privacy.py strip Tests/Fixtures` first; it removes location, XMP, and IPTC data without re-encoding and keeps the orientation flag. `scripts/verify.sh` fails if any JPEG still has them.

## Notes

- iPhone photos are stored sideways with an EXIF orientation flag (value 6 here). Anything that loads them must honor it, or the TV looks rotated 90°.
- Expected text and speakers go in an `expected.json` next to the images once the OCR spike starts.
- Not every box is the standard white one. `buenas-cinio-shout_*` is a spiky shout box with no name tag, `casiopea-call_*` is a dark phone-call box with green text, and `director-announcement_*` is a pale blue PA announcement with no name tag.
