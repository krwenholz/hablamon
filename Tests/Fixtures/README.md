# Test fixtures

Real captures from Kyle's setup. Don't fabricate these; tests skip when they're missing.

| Folder | What | In git? |
| --- | --- | --- |
| `screenshots/` | Clean Switch Capture-button screenshots of dialogue boxes (1280×720 JPG). Mix of speakers, narrator lines, short and long text. | Yes |
| `photos/` | Phone photos or screenshots of the TV, from different placements and angles. | Yes |
| `videos/` | iPhone recordings of normal play, one per placement: `near.mov`, `far.mov`. | No (too large; kept on the Mac) |

## Naming

Photos are named `<content>_<placement>_<angle>.<ext>`:

- **content**: a slug of what's on screen, or `no-dialogue` when there's no box (useful as a negative case).
- **placement**: `near` (TV fills most of the frame, text easily legible) or `far` (TV is a small part of the frame).
- **angle**: how the phone sits relative to the TV, such as `straight`, `angled`, `rolled`, plus notes like `glare` or `clipped-left`.

Placement and angle labels are judged by eye, so rename if they're off.

## Notes

- iPhone photos are stored sideways with an EXIF orientation flag (value 6 here). Anything that loads them must honor it, or the TV looks rotated 90°.
- Expected text and speakers go in an `expected.json` next to the images once the OCR spike starts.
