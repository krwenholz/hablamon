# M2 and M3: live camera and recovery

Oct 26, 2026 · built and unit-tested; not yet run with a real iPhone (the dev Mac has no camera) · design in [init.md](../init.md), plan in [m2-live-camera.md](../m2-live-camera.md)

## Outcome

Launching Hablamon without `--replay` watches the TV through the iPhone. It waits for the phone, asks for camera permission, and, without a calibration, opens the calibration panel with Vision's proposed screen corners ([built-calibration.png](../mockups/built-calibration.png)). After that it samples every 2 s when idle and 4 per second in dialogue, checks every 10 s that the phone hasn't moved, and recovers on its own when the phone is picked up or bumped. If it can't find the TV for 10 s, it chimes and asks for the corners again.

Fed a fixture video as if it were the camera, the live engine reads the lines in order and calibrates from scratch to within 25 px of the hand calibration. Everything touching AVFoundation capture is untested on hardware.

## What was built

| Area | Where | Notes |
| --- | --- | --- |
| Camera choice | `Live/CameraChooser.swift` | Pinned device only; never the built-in camera unless settings allow it |
| Finding the TV | `Live/RectangleFinder.swift`, `Live/QuadPicker.swift` | Vision rectangles; ~16:9, not tiny, nearest the last screen, and the picture inside the TV frame rather than the frame |
| Has the phone moved? | `Live/BezelMatcher.swift`, `BezelThumbnail` | Compares the ring around the screen (TV frame and wall) at 128×72, brightness-normalized; real frames give 0.01 for a new scene vs 0.20 for a 60 px move (threshold 0.12) |
| Sampling | `Live/SampleScheduler.swift` | Idle 2 s, dialogue 4/s, bezel 10 s; a box glimpsed once switches to the dialogue rate |
| Recovery | `Live/LiveController.swift` over `ConnectionMonitor` | Paused, lost, re-finding, recalibrating; gaps and recalibrations logged to the transcript |
| Readability | `Live/QualityGate.swift` | Text height (warns under 8 px), blown-out box, and the metering point |
| Glue | `Live/LiveEngine.swift`, `Live/LiveCamera.swift`, `HablamonApp/LiveSession.swift` | Serial queue, drops frames while busy; quiet system sounds for stop, resume, and help |
| Calibration panel | `HablamonApp/CalibrationPanel.swift` | Camera view, draggable corners, text-height readout, "Usar estas esquinas" (⏎) |
| Files | `AppSupportStore` | `calibration.json` and `reference.pgm` in Application Support |
| Nameless boxes (before M2) | `profiles/scarlet.json` | Body region ends above the box's bottom border; `classroom_far` reads 7 of 7 |

## Where it differs from the design

- **No exposure bias or zoom.** macOS capture devices don't offer them. Instead, exposure is metered on the dialogue box (`exposurePointOfInterest`), which should stop the phone exposing for the bright scene and blowing out the box. If the phone is too far away, the readability warning says to move it closer.
- **The bezel check compares a ring outside the screen,** not the corrected screen, because the picture changes constantly.
- **No "box missing on every sample" mismatch signal**: the bezel check alone decides whether the phone moved.
- **No `hablamon calibrate` CLI**: calibration lives in the app.

## For Kyle's play test

- [ ] First launch: "Esperando el iPhone…" until the phone is mounted, then a camera permission prompt, then the calibration panel with corners on the screen.
- [ ] Lines are spoken shortly after the text finishes typing, without repeats.
- [ ] Pick up the phone mid-conversation: a soft tick, speech stops; put it back: a pop and a "Móvil en uso · N s" note.
- [ ] Nudge the phone: it re-finds the TV without asking. Move it a lot: after 10 s, a chime and the calibration panel.
- [ ] Is the dialogue box readable when the scene is bright? If not, exposure needs a different approach.
- [ ] Hotkeys work with another app focused (⌥⌘R, ⌥⇧⌘R, ⌥⌘S, ⌥⌘P, ⌥⌘C, hold ⌥⌘E).
- Logs are in `~/Library/Application Support/Hablamon/logs/` if anything goes wrong.

## Leftovers

- The calibration panel doesn't let you pick a different camera; delete `calibration.json` to pin a new phone.
- `settings.json` gains no new fields here, but adding one later still needs a default or a migration (see the M4 record).
