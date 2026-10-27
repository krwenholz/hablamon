# M2 Live Camera Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Run the companion window from the iPhone via Continuity Camera: pick and pin the camera, calibrate the TV corners, sample adaptively, and recover on its own when the phone is picked up or moved (M3 wiring).

**Architecture:** Decisions live in platform-neutral, tested Core types: `CameraChooser`, `QuadPicker`, `BezelMatcher`, `SampleScheduler`, `LiveController` (wraps `ConnectionMonitor`), `QualityGate`, and PGM read/write for the reference thumbnail. Apple-only adapters sit behind protocols: `LiveCamera` (AVCaptureSession, suspension and connection signals, exposure bias, zoom) and `RectangleFinder` (Vision). `AppModel` gains a live mode that feeds camera frames through the controller into the same `DialoguePipeline` and `CompanionState` as replay.

**Spec:** [init.md § M2 and M3](init.md#m2-live-continuity-camera), [status-states.png](mockups/status-states.png) for the recovery card content.

## Global Constraints

- Apple frameworks only; offline; Swift Testing; Linux builds pass (`#if canImport`).
- Never fall back to the built-in camera unless `settings.allowBuiltInCamera`; never auto-switch away from the pinned device.
- Idle sampling every `settings.idleSampleInterval` s (default 2); in dialogue `settings.dialogueSampleRate` per s (default 4); dialogue mode ends 3 s after the box disappears (`DialoguePresence`).
- Bezel check every 10 s while tracking.
- Text-height warning below 8 camera px.
- `calibration.json` and `reference.pgm` live in Application Support next to the other files.
- Kyle can't be asked mid-task: anything needing hardware gets a log line and goes in the hand-off.

## Review Focus

1. Phone picked up mid-line: speech stops, no half page is spoken on return, and a gap appears in the conversation. Test: `LiveControllerTests.suspendStopsAndLogsGap`.
2. Phone set back slightly moved: re-finding accepts a quad whose bezel matches and logs an automatic recalibration. Test: `LiveControllerTests.movedPhoneRefindsAutomatically`.
3. No match for 10 s: the recovery card appears with a chime, and confirming corners resumes. Test: `LiveControllerTests.refindTimeoutAsksForHelp`.
4. Only the Mac's built-in camera present: the app says it's waiting for the iPhone instead of using it. Test: `CameraChooserTests.neverPicksBuiltInByDefault`.
5. A frame with no rectangle, or several (picture frames, windows): the picker prefers the ~16:9 quad nearest the previous one. Test: `QuadPickerTests.prefersWidescreenNearPrevious`.

---

### Task 1: Camera choice

**Files:** Create `Sources/HablamonCore/Live/CameraChooser.swift`; test `Tests/HablamonCoreTests/CameraChooserTests.swift`.

**Produces:** `struct CameraInfo { id: String; name: String; kind: Kind }` with `enum Kind { continuity, builtIn, external }`; `enum CameraChooser { static func choose(from: [CameraInfo], pinned: String?, allowBuiltIn: Bool) -> CameraInfo? }`.

- [ ] Tests: `prefersPinnedDevice`, `firstContinuityWhenNothingPinned`, `neverPicksBuiltInByDefault` (only built-in → nil), `builtInWhenAllowed`, `pinnedMissingDoesNotSwitch` (pinned id absent but other continuity present → nil, the caller shows Lost).
- [ ] Implement, verify, commit "Choose and pin the camera".

### Task 2: Quad geometry and picking

**Files:** Create `Sources/HablamonCore/Live/QuadPicker.swift`; test `QuadPickerTests.swift`.

**Produces:** `extension Quad { var area: Double; var aspect: Double (mean top/bottom width ÷ mean left/right height); var center: Point; func distance(to: Quad) -> Double (mean corner distance) }`; `enum QuadPicker { static func pick(_ candidates: [Quad], near previous: Quad?, frameArea: Double) -> Quad? }` keeping quads with aspect 1.45…2.1 and area ≥ 5 % of the frame, preferring nearest to `previous`, else largest.

- [ ] Tests: `aspectOfWidescreenQuad` (16:9 rectangle → 1.78), `rejectsSquareAndTiny`, `prefersWidescreenNearPrevious` (two 16:9 candidates; the one near previous wins even if smaller), `largestWithoutPrevious`, `emptyGivesNil`.
- [ ] Implement, verify, commit "Pick the TV quad from rectangle candidates".

### Task 3: Bezel matching and the reference thumbnail

**Files:** Create `Sources/HablamonCore/Live/BezelMatcher.swift`, `Sources/HablamonCore/Detection/GrayImage+PGM.swift`; tests `BezelMatcherTests.swift`.

**Produces:** `GrayImage.pgm: Data`, `GrayImage(pgm: Data) throws`; `GrayImage.resized(width:height:) -> GrayImage` (box average); `struct BezelMatcher { static let size = (64, 36); var threshold = 0.12; func matches(_ reference: GrayImage, _ current: GrayImage) -> Bool }` comparing mean absolute difference after normalizing each image's mean brightness (exposure drift shouldn't count as a move).

- [ ] Tests: `pgmRoundTrips`, `identicalImagesMatch`, `brightnessShiftStillMatches` (+40 levels everywhere), `shiftedContentDoesNotMatch` (content moved 10 px), `differentSizesAreResized`.
- [ ] Implement, verify, commit "Match the TV bezel against a reference".

### Task 4: Sample scheduling

**Files:** Create `Sources/HablamonCore/Live/SampleScheduler.swift`; test `SampleSchedulerTests.swift`.

**Produces:** `struct SampleScheduler { init(idleInterval: Double, dialogueRate: Double, bezelInterval: Double = 10); mutating func decide(at time: Double, inDialogue: Bool) -> (sample: Bool, checkBezel: Bool) }`.

- [ ] Tests: `idleSamplesEveryInterval` (30 fps of calls over 10 s idle → 5 samples), `dialogueSamplesAtRate` (→ 4/s), `switchesImmediatelyIntoDialogue`, `bezelEveryTenSeconds`.
- [ ] Implement, verify, commit "Schedule samples adaptively".

### Task 5: Live controller

**Files:** Create `Sources/HablamonCore/Live/LiveController.swift`; test `LiveControllerTests.swift`.

**Consumes:** `ConnectionMonitor`, `SampleScheduler`, `QuadPicker`, `BezelMatcher`.

**Produces:**
```swift
public enum LiveInput { case frame(time: Double, date: Date), camera(ConnectionMonitor.Signal, date: Date),
    rectangles([Quad], frameArea: Double, bezel: GrayImage?, date: Date), bezel(GrayImage, date: Date),
    boxSeen(Bool), calibrationConfirmed(Quad, date: Date), tick(Date) }
public enum LiveOutput: Equatable { case process(time: Double), findRectangles, checkBezel,
    useQuad(Quad), monitor(ConnectionMonitor.Effect), state(ConnectionMonitor.State) }
public struct LiveController { init(calibration quad: Quad?, reference: GrayImage?, scheduler: SampleScheduler, startingAt: Date);
    var quad: Quad?; mutating func handle(_ input: LiveInput) -> [LiveOutput] }
```
While tracking, frames go to `process` per the scheduler, and every bezel check compares against the reference (mismatch → monitor `.screenMismatch`). Twenty consecutive samples without a box while the bezel matches is not a mismatch (the game simply has no dialogue). While re-finding, each frame asks for rectangles; a picked quad whose corrected bezel matches the reference → `.screenFound(quadChanged:)` and `useQuad`. With no calibration at all, the state is `recalibrating` from the start.

- [ ] Tests: `tracksAndProcessesOnSchedule`, `suspendStopsAndLogsGap`, `movedPhoneRefindsAutomatically`, `refindTimeoutAsksForHelp`, `confirmingCornersResumes`, `noCalibrationStartsRecalibrating`, `bezelMismatchStartsRefinding`.
- [ ] Implement, verify, commit "Coordinate live sampling and recovery".

### Task 6: Quality gate

**Files:** Create `Sources/HablamonCore/Live/QualityGate.swift`; test `QualityGateTests.swift`.

**Produces:** `struct QualityReport: Equatable { textHeight: Double; clipped: Double; warnings: [String] }`; `enum QualityGate { static func report(quad: Quad, profile: GameProfile, bodyCrop: RGBAImage?) -> QualityReport }`. Text height = body cap height (profile frame ≈ 22 px of 720) × the quad's mean height ÷ 720. Clipped = fraction of body pixels with luminance ≥ 0.98. Warnings below 8 px and above 5 % clipped.

- [ ] Tests: `farQuadTextHeight` (far.mp4 calibration → between 8 and 14), `smallQuadWarns`, `clippedHighlightsWarn`.
- [ ] Implement, verify, commit "Report text height and clipping".

### Task 7: Rectangle finder (Vision) and live camera (AVFoundation)

**Files:** Create `Sources/HablamonCore/Live/RectangleFinder.swift`, `Sources/HablamonCore/Live/LiveCamera.swift`; test `RectangleFinderTests.swift` (macOS).

**Produces:** `struct RectangleFinder { func candidates(in: CIImage) throws -> [Quad] }` (pixel coordinates, origin top-left); `final class LiveCamera` with `static func available() -> [CameraInfo]`, `start(deviceID:zoom:) throws`, `stop()`, `onFrame: (CIImage, Date) -> Void`, `onSignal: (ConnectionMonitor.Signal, Date) -> Void`, `setZoom(_:)`; 1080p30, frames dropped while busy, `isSuspended` KVO, connect/disconnect notifications for the pinned id, `exposureTargetBias` lowered to −1 EV when supported.

- [ ] Test `findsTheTVInFixtureFrames`: on frames from `classroom_far.mp4` and `academy-lobby_far.mp4`, `QuadPicker.pick(finder.candidates…)` lands within 25 px (mean corner) of each fixture's calibration. Skips without the videos.
- [ ] `LiveCamera` can't be tested here (no camera on the dev Mac); it compiles and is exercised in Kyle's play test.
- [ ] Verify, commit "Find the TV with Vision and capture from the iPhone".

### Task 8: Live mode in the app

**Files:** Modify `AppModel.swift`, `HablamonApp.swift`, `MainWindow.swift`, `StatusStrip.swift`; create `CalibrationPanel.swift`, `Cues.swift`; modify `AppSupportStore.swift` (+ tests) for `calibration()`, `save(_ calibration:)`, `reference()`, `save(reference:)`.

- [ ] Store tests: `calibrationRoundTrips`, `referenceRoundTrips`, `missingCalibrationIsNil`.
- [ ] Launching without `--replay` starts live mode: choose the camera (waiting state with a message if none), start capture, feed frames through `LiveController`, run `DialoguePipeline` on `process` outputs with `ScreenCorrector(quad)`, apply connection states and gaps to `CompanionState`, play cues (`NSSound` "Tink" stopped, "Pop" resumed, "Glass" needs attention, volume 0.3).
- [ ] `CalibrationPanel` takes over the words slot when recalibrating: latest frame with the proposed quad, four draggable corners, quality report, zoom slider, "Usar estas esquinas" (⏎). Confirming saves `calibration.json` and `reference.pgm`. The recalibrate hotkey and menu item open it.
- [ ] Verify (build, tests); snapshot the calibration panel from a replayed frame via `--panel calibration --replay`; commit "Run the window from the live camera".

### Task 9: Close out

- [ ] Update init.md (M2/M3 status, what Kyle should check), write `done/m2-live-camera.md`, verify, commit.
