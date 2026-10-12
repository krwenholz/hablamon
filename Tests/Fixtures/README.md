# Test fixtures

Real captures from Kyle's setup. Don't fabricate these; tests skip when they're missing.

| Folder | What | In git? |
| --- | --- | --- |
| `screenshots/` | Switch Capture-button screenshots of dialogue boxes (1280×720 JPG). Mix of speakers, narrator lines, short and long text. | Yes |
| `videos/` | iPhone recordings of normal play, one per placement: `near.mov`, `far.mov`. | No (too large; kept on the Mac) |

Name screenshots so the expected speaker is obvious, e.g. `clavel-01.jpg`, `narrator-01.jpg`. Expected text and speakers go in `screenshots/expected.json` once the OCR spike starts.
