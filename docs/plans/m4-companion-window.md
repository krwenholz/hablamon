# M4 Companion Window Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A full-screen SwiftUI window that shows the line being spoken, the conversation, ranked vocabulary, and pipeline status, driven by replaying the fixture videos in real time.

**Architecture:** All logic lives in `HablamonCore` as plain, testable types: a `CompanionState` reducer, a `VocabRanker`, an `AppSupportStore`, and Spanish/English label tables. Apple-only adapters (NaturalLanguage tagging, Dictionary Services lookup, speech progress, Carbon hotkeys) sit behind small protocols and `#if canImport`. `HablamonApp` is thin: an `@Observable` model feeds replay events into the reducer and the narrator, and SwiftUI views render the state.

**Tech Stack:** Swift 6, SwiftPM, SwiftUI (macOS 14), AVFoundation, Vision, NaturalLanguage, CoreServices (Dictionary Services), Carbon (hotkeys), Swift Testing.

**Spec:** [init.md § M4](init.md#m4-characters-and-companion-ui), mockups [main-window.png](mockups/main-window.png) and [status-states.png](mockups/status-states.png).

## Global Constraints

- Apple frameworks only; no new packages.
- Fully offline: no network calls.
- Every new JSON file gets a `VersionedDocument` in `HablamonModels`; run `mise run schemas` after model changes.
- Swift Testing only. Hardware and OS services (speech, dictionary, tagger, hotkeys) go behind protocols with fakes in tests.
- Code that needs AppKit/SwiftUI/NaturalLanguage/CoreServices/Carbon is wrapped in `#if canImport(...)` so Linux builds still pass.
- Window target: 1470×956 points, full screen, no camera preview.
- Labels are Spanish; holding `opt+cmd+E` shows English while held.
- Unknown speakers are never prompted mid-game: neutral voice, a quiet count, and a sheet opened on demand.
- Each task ends with `mise run verify` passing and a commit (seven-rules message, `Co-Authored-By` trailer).

## Review Focus

1. A three-line, 150-character message must fit the top box without clipping at 1470×956: the text scales down (`minimumScaleFactor(0.6)`) instead of truncating. Test: Task 10 preview at that size with the longest `far.expected.json` line.
2. OCR variants of one name ("Mencia", "Mencía", "Mencía.") must collapse into one unknown speaker entry. Test: Task 5 `unknownSpeakersGroupByMatchKey`.
3. With no Spanish–English dictionary enabled, words still show (word, class, sentence) with an empty gloss, and a one-time hint says how to enable it. Test: Task 6 `missingGlossStillRanks`.
4. A hand-edited `characters.json` or `known-words.json` with a schema error must not crash: the app uses bundled defaults (or an empty known set) and shows the `DocumentError` text in diagnostics. Test: Task 4 `brokenFileFallsBackWithIssue`.
5. First launch with no sessions folder: frequency counts are all zero and nothing throws. Test: Task 4 `emptySessionsDirectoryHasNoLines`.

---

### Task 1: Calibrations and golden transcripts for the landscape videos

**Files:**
- Create: `Tests/Fixtures/videos/academy-lobby_far.calibration.json`, `Tests/Fixtures/videos/classroom_far.calibration.json`
- Create: `Tests/Fixtures/videos/academy-lobby_far.expected.json`, `Tests/Fixtures/videos/classroom_far.expected.json`
- Modify: `Tests/HablamonCoreTests/ReplayTests.swift`

**Interfaces:**
- Produces: `VideoFixtures.available(_ name: String) -> Bool`; a parameterized replay test over `["far", "academy-lobby_far", "classroom_far"]`.

- [ ] **Step 1:** Extract a frame with a dialogue box from each video (`ffmpeg -ss <t> -i … -frames:v 1`), place the four TV-screen corners by hand, and write the calibration files in the same shape as `far.calibration.json` (`deviceID: "fixture:<name>.mp4"`, `deviceName` saying which frame).
- [ ] **Step 2:** Draft each golden transcript by stepping through the video (`at`, `speaker`, `text`, all `certain: true`; drop any line that can't be read with confidence). Player choice bubbles are menus, not dialogue; leave them out.
- [ ] **Step 3:** Generalize `farVideoMatchesGoldenTranscript` into `@Test(arguments: ["far", "academy-lobby_far", "classroom_far"]) func videoMatchesGoldenTranscript(_ name: String)`, enabled per video by `VideoFixtures.available(name)`. Keep the 70 % found threshold and the "pages ≤ 2× lines" check; replace the all-Mencía check with "at least 70 % of found pages carry the golden speaker".
- [ ] **Step 4:** Run `swift test --disable-xctest --no-parallel --filter ReplayTests`. If a new video falls under 70 %, record the misses and causes in the commit body; don't tune detection in this task.
- [ ] **Step 5:** `mise run verify`, commit "Add calibrations and goldens for landscape videos".

### Task 2: Neutral voice for unknown speakers; live character updates

**Files:**
- Modify: `Sources/HablamonCore/Speech/VoiceSelector.swift`, `Sources/HablamonCore/Pipeline/DialoguePipeline.swift`
- Test: `Tests/HablamonCoreTests/VoiceSelectorTests.swift`, `Tests/HablamonCoreTests/DialoguePipelineTests.swift`

**Interfaces:**
- Produces: `VoiceSelector.neutralPitch = 0.92`; `DialoguePipeline.updateCharacters(_ table: CharacterTable)`.

- [ ] **Step 1: Failing tests.**
  - `unknownSpeakersShareNeutralRegister`: `.unknown("Recepcionista")` and `.unknown("Recluta")` both plan `.female` register, pitches within `neutralPitch ± spread * 1.5`, and differ from each other.
  - `neutralCharacterUsesNeutralPitch`: a known character with `gender: .neutral` and no age gets base pitch `0.92 ± spread`.
  - `updatedCharactersApplyToNextPage`: a pipeline built with an empty table resolves "Clavel" as `.unknown`; after `updateCharacters` with Clavel added, the next settled page resolves `.known`.
- [ ] **Step 2:** Run them; expect failures (unknowns currently alternate male/female).
- [ ] **Step 3:** Unknown and neutral both map to the female register at base `neutralPitch` (Apple's es-ES voices are male or female, so "neutral" is a lowered female voice). Remove the name-hash register alternation. `updateCharacters` replaces the resolver.
- [ ] **Step 4:** Tests pass; update the existing unknown-pitch test to the new base.
- [ ] **Step 5:** `mise run verify`, commit "Give unknown speakers one neutral voice".

### Task 3: Known-words document and the hold-for-English hotkey

**Files:**
- Create: `Sources/HablamonModels/KnownWords.swift`
- Modify: `Sources/HablamonModels/Settings.swift` (Hotkeys), `Sources/HablamonModels/SchemaCatalog.swift`, `schemas/` (regenerated)
- Test: `Tests/HablamonModelsTests/DocumentRoundTripTests.swift`

**Interfaces:**
- Produces:
  ```swift
  public struct KnownWords: VersionedDocument, Equatable {  // schemaName "known-words", version 1
      public var schemaURI: String?   // "$schema"
      public var schemaVersion: Int
      public var lemmas: [String]     // sorted, unique, lowercased
  }
  ```
  `Hotkeys.holdForEnglish: String`, default `"opt+cmd+E"`.

- [ ] **Step 1:** Failing round-trip tests: `knownWordsRoundTrips` (encode → `DocumentLoader.load` → equal) and `knownWordsRejectsUnknownKeys` (extra key gives a `DocumentError`); `settingsDefaultsIncludeHoldForEnglish` expects `"opt+cmd+E"`.
- [ ] **Step 2:** Run; expect compile failure.
- [ ] **Step 3:** Add the type (pattern of `VoiceManifest`, plus `$schema` like `Settings`), add the hotkey field and default, and register `KnownWords` in `SchemaCatalog.documents`. No settings files exist in the wild yet, so add the field without a migration.
- [ ] **Step 4:** `mise run schemas`; tests pass, including the stale-schema test.
- [ ] **Step 5:** `mise run verify`, commit "Add known-words document and English hotkey".

### Task 4: Application Support store

**Files:**
- Create: `Sources/HablamonCore/Storage/AppSupportStore.swift`
- Test: `Tests/HablamonCoreTests/AppSupportStoreTests.swift`

**Interfaces:**
- Consumes: `KnownWords`, `Settings.defaults`, `BundledData.defaultCharacters()`, `TranscriptWriter.entries(at:)`.
- Produces:
  ```swift
  public struct Loaded<T> { public var value: T; public var issue: String? }
  public struct AppSupportStore: Sendable {
      public init(root: URL)                       // default root: ~/Library/Application Support/Hablamon
      public static var defaultRoot: URL { get }
      public var sessionsDirectory: URL { get }    // root/sessions
      public func seedIfNeeded() throws            // writes characters.json and settings.json with "$schema" if absent
      public func characters() -> Loaded<CharacterTable>
      public func settings() -> Loaded<Settings>
      public func knownWords() -> Loaded<KnownWords>
      public func save(_ table: CharacterTable) throws
      public func save(_ words: KnownWords) throws
      public func pastLines() -> [TranscriptLine]  // every line entry in every sessions/*.jsonl
  }
  ```
  Seeded files get `"$schema": "hablamon:<schemaName>"`. A URL would invite editors to fetch it over the network; this only labels the file type.

- [ ] **Step 1: Failing tests** in a temp directory:
  - `seedWritesDefaultsOnce`: after `seedIfNeeded()`, both files load and equal the bundled table and `Settings.defaults`; editing a file and seeding again leaves it unchanged.
  - `brokenFileFallsBackWithIssue`: a `characters.json` with `"gender": "robot"` returns the bundled table and a non-nil `issue` containing `gender`.
  - `missingKnownWordsIsEmpty`: no file gives `lemmas == []`, `issue == nil`.
  - `emptySessionsDirectoryHasNoLines`: `pastLines()` is `[]` when `sessions/` doesn't exist.
  - `pastLinesReadsAllSessions`: two session files written with `TranscriptWriter` yield all their lines.
- [ ] **Step 2:** Run; expect compile failure.
- [ ] **Step 3:** Implement with `DocumentLoader`; writes are atomic.
- [ ] **Step 4:** Tests pass.
- [ ] **Step 5:** `mise run verify`, commit "Add Application Support store".

### Task 5: Companion state reducer

**Files:**
- Create: `Sources/HablamonCore/Companion/CompanionState.swift`
- Test: `Tests/HablamonCoreTests/CompanionStateTests.swift`

**Interfaces:**
- Consumes: `SpokenPage`, `PipelineEvent`, `ConnectionMonitor.State`, `TranscriptGap.Reason`, `DialogueText.matchKey`.
- Produces:
  ```swift
  public enum StatusPill: Equatable, Sendable { case idle, reading, speaking, phoneInUse, findingTV, lostCamera, needsYou }
  public enum Light: Equatable, Sendable { case off, ok, working, bad }
  public struct Lights: Equatable, Sendable { public var camera, tv, box, text, voice: Light }
  public enum ConversationItem: Equatable, Sendable, Identifiable {
      case line(id: Int, page: SpokenPage)
      case gap(id: Int, reason: TranscriptGap.Reason, seconds: Double)
  }
  public struct UnknownSpeaker: Equatable, Sendable { public var key: String; public var shownName: String; public var lines: [SpokenPage] }
  public enum CompanionEvent: Sendable {
      case pipeline(PipelineEvent)
      case frame(screenFound: Bool)          // from Task 8
      case speechStarted, speechProgress(utf16Offset: Int), speechFinished
      case connection(ConnectionMonitor.State)
      case gap(TranscriptGap.Reason, seconds: Double)
      case speakerTagged(key: String)         // removes it from unknowns
  }
  public struct CompanionState: Equatable, Sendable {
      public var current: SpokenPage?
      public var spokenUTF16: Int             // how much of current.text has been spoken
      public var conversation: [ConversationItem]   // newest last; current line is not duplicated here
      public var unknownSpeakers: [UnknownSpeaker]  // first-seen order
      public var pill: StatusPill
      public var lights: Lights
      public var lastConfidence: Double?
      public var lineCount: Int
      public mutating func apply(_ event: CompanionEvent)
  }
  ```

- [ ] **Step 1: Failing tests:**
  - `speakMovesPreviousLineIntoConversation`: two `.speak` pages → `current` is the second, `conversation` holds the first as `.line`.
  - `pillFollowsPipeline`: no box → `.idle`; `.dialogueStarted` → `.reading`; `.speechStarted` → `.speaking`; `.speechFinished` → `.reading`; `.dialogueEnded` → `.idle`.
  - `connectionStatesMapToPills`: `.paused` → `.phoneInUse`, `.refinding` → `.findingTV`, `.lost` → `.lostCamera`, `.recalibrating` → `.needsYou`; `.tracking` restores the pipeline-derived pill.
  - `lightsTrackStages`: `.frame(screenFound: true)` sets camera and tv `.ok`; `false` sets tv `.bad`; `.dialogueStarted` sets box `.ok`; `.speak` sets text `.ok`; `.speechStarted` sets voice `.working`.
  - `gapAppearsInConversation`: `.gap(.cameraPaused, seconds: 14)` appends a `.gap` item.
  - `unknownSpeakersGroupByMatchKey`: pages from `.unknown("Mencia")` and `.unknown("Mencía.")` produce one `UnknownSpeaker` with both lines; `.speakerTagged(key:)` removes it.
  - `progressClampsToText`: `speechProgress` past the end clamps to `current.text.utf16.count`; a new `.speak` resets it to 0.
- [ ] **Step 2:** Run; expect compile failure.
- [ ] **Step 3:** Implement as a pure value type; ids from a private counter.
- [ ] **Step 4:** Tests pass.
- [ ] **Step 5:** `mise run verify`, commit "Add companion state reducer".

### Task 6: Vocabulary ranking and glosses

**Files:**
- Create: `Sources/HablamonCore/Vocab/VocabRanker.swift`, `Sources/HablamonCore/Vocab/NLWordAnalyzer.swift`, `Sources/HablamonCore/Vocab/DictionaryGlossProvider.swift`
- Test: `Tests/HablamonCoreTests/VocabRankerTests.swift`, `Tests/HablamonCoreTests/NLWordAnalyzerTests.swift` (macOS-only, `#if canImport(NaturalLanguage)`)

**Interfaces:**
- Produces:
  ```swift
  public enum WordClass: String, Sendable { case noun, verb, adjective, adverb, other }
  public struct AnalyzedWord: Equatable, Sendable { public var surface: String; public var lemma: String; public var wordClass: WordClass }
  public protocol WordAnalyzer: Sendable { func analyze(_ text: String) -> [AnalyzedWord] }
  public protocol GlossProvider: Sendable { func gloss(for lemma: String) -> String? }
  public struct VocabEntry: Equatable, Sendable, Identifiable {
      public var id: String { lemma }
      public var lemma, surface: String; public var wordClass: WordClass
      public var gloss: String?; public var sentence: String; public var score: Double
  }
  public struct VocabRanker: Sendable {
      public init(analyzer: any WordAnalyzer, glosses: any GlossProvider, history: [String], known: Set<String>)
      public mutating func add(line: String)            // recent lines feed candidates; history feeds frequency
      public func top(_ count: Int = 5) -> [VocabEntry]
      public mutating func markKnown(_ lemma: String)
  }
  ```
  `NLWordAnalyzer` uses `NLTagger(tagSchemes: [.lemma, .lexicalClass])` with language `.spanish`. `DictionaryGlossProvider` calls `DCSCopyTextDefinition(nil, …)` and keeps the first sense: text up to the first `;` or line break after the headword, trimmed to 60 characters.

- [ ] **Step 1: Failing tests** (fake analyzer and gloss provider):
  - `functionWordsAndNamesNeverShow`: `other`-class words and capitalized words that aren't sentence-initial are excluded.
  - `knownWordsNeverShow`: a lemma in `known` or passed to `markKnown` disappears from `top`.
  - `frequentLemmaOutranksRareOne`: with equal recency, a lemma seen 5× in `history` beats one seen once.
  - `newLemmaOutranksSeenOne`: a lemma absent from `history` gets the newness boost over one present twice. Score: `score = 2.0 * (seenBefore ? 0 : 1) + log(1 + historyCount) + classWeight`, with class weights noun 1.0, verb 1.0, adjective 0.8, adverb 0.5.
  - `inflectionsCollapseByLemma`: "combatir" and "combatimos" (same lemma) yield one entry.
  - `missingGlossStillRanks`: a provider returning nil still yields entries with `gloss == nil`.
  - `sentenceIsMostRecentUse`: the entry's `sentence` is the latest line containing the word.
  - macOS only, `nlAnalyzerLemmatizesSpanish`: "Hemos combatido" yields lemma `combatir`, class `.verb`. Skip with a message if the Spanish model is unavailable.
- [ ] **Step 2:** Run; expect compile failure.
- [ ] **Step 3:** Implement. Candidates come only from the last 20 lines added; frequency from `history` lemmas (computed once at init by the analyzer).
- [ ] **Step 4:** Tests pass. On a Mac, run `DictionaryGlossProvider().gloss(for: "travesía")` once by hand and note the result in the commit body (verifies the unverified dictionary assumption).
- [ ] **Step 5:** `mise run verify`, commit "Rank vocabulary and look up glosses offline".

### Task 7: Speech progress

**Files:**
- Modify: `Sources/HablamonCore/Speech/SpeechEngine.swift`, `Sources/HablamonCore/Speech/AppleSpeechEngine.swift`
- Test: `Tests/HablamonCoreTests/NarratorTests.swift`

**Interfaces:**
- Produces: `SpeechEngine.speak(_ text: String, voice: VoicePlan, rate: Double, progress: @escaping @Sendable (Int) -> Void) async throws` (UTF-16 offset of the word starting now). A protocol extension keeps the old three-argument call. `Narrator.say(_:voice:progress:)` with `progress` defaulting to a no-op.

- [ ] **Step 1:** Failing test `narratorForwardsProgress`: a fake engine reporting offsets `[0, 3, 9]` delivers the same offsets to the closure passed to `say`.
- [ ] **Step 2:** Run; expect failure.
- [ ] **Step 3:** Apple engine reports `characterRange.location` from `speechSynthesizer(_:willSpeakRangeOfSpeechString:utterance:)` for the in-flight utterance only.
- [ ] **Step 4:** Tests pass.
- [ ] **Step 5:** `mise run verify`, commit "Report speech progress word by word".

### Task 8: Real-time replay with frame status

**Files:**
- Modify: `Sources/HablamonCore/Replay/Replay.swift`
- Test: `Tests/HablamonCoreTests/ReplayTests.swift`

**Interfaces:**
- Produces: two new `Replay.run` parameters: `realTime: Bool = false` (sleep so video time tracks wall-clock time) and `onFrame: ((_ screenFound: Bool, _ videoTime: Double) -> Void)? = nil` (called per sampled frame; `screenFound` is whether the corrector returned an image).

- [ ] **Step 1:** Failing test `realTimeReplayTakesVideoDuration` (macOS, enabled if `far` is available, time limit 4 minutes): replay the first 10 s by cancelling the task after the `onFrame` time passes 10, and expect wall time ≥ 9 s. Also `onFrameCalledPerSample`: count ≈ duration / interval (± 2).
- [ ] **Step 2:** Run; expect failure.
- [ ] **Step 3:** Pace with `Task.sleep` against a start `ContinuousClock.Instant`; honor cancellation.
- [ ] **Step 4:** Tests pass; existing replay tests still pass with defaults.
- [ ] **Step 5:** `mise run verify`, commit "Add real-time replay and per-frame status".

### Task 9: Spanish and English labels

**Files:**
- Create: `Sources/HablamonCore/Companion/Labels.swift`
- Test: `Tests/HablamonCoreTests/LabelsTests.swift`

**Interfaces:**
- Produces: `public enum Label: CaseIterable { … }` and `public func text(_ label: Label, english: Bool) -> String`, plus `public func text(_ pill: StatusPill, english: Bool) -> String`.

Exact copy (Spanish / English):

| Label | es | en |
| --- | --- | --- |
| idle / reading / speaking | En espera / Leyendo / Hablando | Idle / Reading / Speaking |
| phoneInUse / findingTV | Móvil en uso / Buscando la tele | Phone in use / Finding TV |
| lostCamera / needsYou | Cámara perdida / Te necesito | Lost camera / Needs you |
| conversation / words | Conversación / Palabras | Conversation / Words |
| knowIt | Ya la sé | I know it |
| camera / tv / box / text / voice | Cámara / Tele / Caja / Texto / Voz | Camera / TV / Box / Text / Voice |
| unassignedVoices | voces sin asignar | unassigned voices |
| narrator | Narrador | Narrator |
| male / female / neutral | Masculina / Femenina / Neutra | Male / Female / Neutral |
| repeat / slow / pause / recalibrate | Repetir / Lento / Pausa / Recalibrar | Repeat / Slow / Pause / Recalibrate |
| diagnostics | Diagnóstico | Diagnostics |
| gapPaused / gapLost / gapScreen | Móvil en uso / Cámara perdida / Tele perdida | Phone in use / Camera lost / TV lost |
| glossHint | Activa el diccionario español-inglés en Diccionario › Ajustes | Enable the Spanish–English dictionary in Dictionary › Settings |

- [ ] **Step 1:** Failing tests: `everyLabelHasBothLanguages` (non-empty, and es ≠ en except where identical by design: none), `pillsUseLabelTable`.
- [ ] **Step 2–4:** Implement as a `switch`; tests pass.
- [ ] **Step 5:** `mise run verify`, commit "Add Spanish and English labels".

### Task 10: App model and main window

**Files:**
- Create: `Sources/HablamonApp/AppModel.swift`, `Sources/HablamonApp/Theme.swift`, `Sources/HablamonApp/MainWindow.swift`, `Sources/HablamonApp/HeroBox.swift`, `Sources/HablamonApp/ConversationPanel.swift`, `Sources/HablamonApp/WordsPanel.swift`, `Sources/HablamonApp/StatusStrip.swift`
- Modify: `Sources/HablamonApp/HablamonApp.swift`

**Interfaces:**
- Consumes: Tasks 2–9.
- Produces: `@MainActor @Observable final class AppModel { var state: CompanionState; var words: [VocabEntry]; var english: Bool; var issues: [String]; func startReplay(video: URL, calibration: URL); func replay(_ item: ConversationItem); func markKnown(_ lemma: String); func tag(_ key: String, as gender: Gender) }`.

- [ ] **Step 1:** `AppModel` loads the store (seed, characters, settings, known words, past lines), builds `VocabRanker`, and on `startReplay` runs `Replay.run(realTime: true)` in a task: pipeline events → `state.apply`, `.speak` → `Narrator.say` (progress → `.speechProgress`) and `TranscriptWriter.appendLine` and `ranker.add(line:)`. `tag` writes `characters.json` via the store, calls `updateCharacters`, and applies `.speakerTagged`. Launch args `--replay <video> --calibration <file>` start a replay; otherwise File › Abrir grabación… opens a panel for the video and looks for `<name>.calibration.json` beside it.
- [ ] **Step 2:** Views per [main-window.png](mockups/main-window.png): orange striped background, heavy-ink cards, Gill Sans dialogue text, Avenir Next heavy italic headers. `HeroBox` dims text after `spokenUTF16` using `AttributedString`, `minimumScaleFactor(0.6)`, translation slot reserved but empty. `ConversationPanel` scrolls to newest; tap a line to replay. `WordsPanel` shows `top(5)` with "Ya la sé" per row, or the gloss hint once when glosses are nil. `StatusStrip` shows pill, lights, voice, line count, and the unassigned-voices count. The window opens full screen (`NSWindow.toggleFullScreen` on appear).
- [ ] **Step 3:** Add `#Preview` blocks at 1470×956 with a fixture `CompanionState` holding the longest `far.expected.json` line; confirm by eye that nothing clips (Review Focus 1).
- [ ] **Step 4:** `swift run HablamonApp --replay Tests/Fixtures/videos/classroom_far.mp4 --calibration Tests/Fixtures/videos/classroom_far.calibration.json` on the Mac: lines appear and are spoken, the conversation fills, words appear. Screenshot it into `docs/plans/mockups/built-main-window.png`.
- [ ] **Step 5:** `mise run verify`, commit "Build the companion window on replay".

### Task 11: Speakers sheet and diagnostics

**Files:**
- Create: `Sources/HablamonApp/SpeakersSheet.swift`, `Sources/HablamonApp/DiagnosticsPopover.swift`
- Modify: `Sources/HablamonApp/StatusStrip.swift`

- [ ] **Step 1:** Clicking the unassigned-voices count opens `SpeakersSheet`: one row per `UnknownSpeaker` with its lines (tap to replay) and Masculina / Femenina / Neutra buttons that call `AppModel.tag`. The sheet never opens by itself.
- [ ] **Step 2:** Clicking the strip's right side opens `DiagnosticsPopover`: last OCR confidence, line count, replay lag (video time vs wall time), and any `issues` from the store (Review Focus 4). Camera text height and clipping wait for M2.
- [ ] **Step 3:** On the Mac, replay `academy-lobby_far` with an empty `characters.json` (rename the real one first): unknowns appear in the sheet, tagging Clavel changes his voice on his next line, and `characters.json` gains the entry.
- [ ] **Step 4:** `mise run verify`, commit "Add speakers sheet and diagnostics".

### Task 12: Hotkeys and menu bar

**Files:**
- Create: `Sources/HablamonApp/Hotkeys.swift`, `Sources/HablamonCore/Companion/HotkeyParser.swift`
- Test: `Tests/HablamonCoreTests/HotkeyParserTests.swift`
- Modify: `Sources/HablamonApp/HablamonApp.swift`

**Interfaces:**
- Produces: `public struct ParsedHotkey: Equatable { public var key: Character; public var control, option, shift, command: Bool }`, `public static func parse(_ text: String) -> ParsedHotkey?` (Core, platform-neutral); `HotkeyCenter` (App) registering each `Settings.hotkeys` entry with Carbon `RegisterEventHotKey` and handling both `kEventHotKeyPressed` and `kEventHotKeyReleased`.

- [ ] **Step 1:** Failing parser tests: `"opt+shift+cmd+R"` parses all three modifiers and `R`; `"cmd+"` and `"hyper+R"` return nil.
- [ ] **Step 2–3:** Implement parser; tests pass.
- [ ] **Step 4:** Wire actions: repeat last, repeat slowly (speed × 0.7 for one line), toggle speed (0.85 ↔ 1.0), pause/resume narration, recalibrate (no-op with a log line until M2), and hold-for-English (`english = true` on press, `false` on release). Add a `MenuBarExtra` with the state dot, Pausa/Reanudar, Abrir ventana, Recalibrar, Salir, and a dot when unknown speakers are waiting.
- [ ] **Step 5:** On the Mac, check each hotkey with the window in the background and another app focused.
- [ ] **Step 6:** `mise run verify`, commit "Add global hotkeys and menu bar extra".

### Task 13: Close out

- [ ] **Step 1:** Update [init.md](init.md): M4 status to "Window built on replay; live camera in M2", and replace the built bullets with a pointer to a new `done/m4-companion-window.md` record (outcome, what was built, differences from the design, leftovers).
- [ ] **Step 2:** `mise run verify`; put the summary in the hand-off. Commit "Record the companion window milestone".

**Next plan (not this one):** M2 live camera and M3 recovery wiring, plus `scripts/install.sh`, so the window runs from the iPhone instead of a replay.
