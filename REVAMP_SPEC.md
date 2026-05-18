# BooksApp v2 — Revamp Spec: Ephemeral Streaming Reader

**Status:** Ready for implementation
**Author:** Architecture review, May 2026
**Implementer:** Single agent / engineer, ~1–2 weeks

---

## 1. Overview

Pivot BooksApp v2 from a *generate-and-store* audiobook app to an *ephemeral live reader*. The user opens an EPUB, the app reads it aloud in real time using on-device TTS, and **no audio is ever written to disk**. Closing the app discards the audio; reopening the app re-synthesizes from the saved document.

### 1.1 Goals

- **Real-time TTS only.** First audio plays within ~500 ms of tapping a chapter.
- **Zero audio persistence.** No M4A, WAV, or PCM bytes touch the filesystem.
- **On-device synthesis.** No network calls, no cloud TTS, no per-minute cost.
- **Reuse the existing iOS app.** Refactor in place; do not rewrite.
- **Document survives across launches** (text + position only — see §4.3); audio does not.

### 1.2 Non-goals (v1)

- PDF support (deferred to v2).
- Pasted-text input (deferred to v2).
- Cloud / premium voice tier (future).
- Word-level scrubbing within a chapter (paragraph-level only — see §5.3).
- Background-tab continuous reading beyond standard `AVAudioSession` behavior.
- Migration of existing user libraries from the current build. **The new build wipes any existing on-disk library on first launch.** No migration path needed.

---

## 2. TTS Engine Decision: Supertonic 3 (on-device)

After comparing 2026 options, the recommendation is to **keep the existing Supertonic ONNX engine** and upgrade to **Supertonic 3** (released 2026-04-29).

### 2.1 Why on-device, not cloud

| Option                   | TTFA      | Quality              | Cost / hr listened | Network |
| ------------------------ | --------- | -------------------- | ------------------ | ------- |
| **Supertonic 3 (chosen)** | ~instant  | Close to ElevenLabs Prime (5-step) | $0                 | None    |
| Kokoro-82M (on-device alt)| ~instant  | > Google WaveNet     | $0                 | None    |
| Cartesia Sonic 3 (cloud) | ~90 ms    | Top tier             | ~$1.35             | Yes     |
| ElevenLabs Flash v2.5    | ~75 ms    | Very good            | $1–3               | Yes     |
| Inworld TTS              | <250 ms   | #1 Artificial Analysis | varies           | Yes     |

Audiobook listening is hours-long; cloud TTS pricing is prohibitive at scale ($1.50+/hr per active user). Supertonic 3 runs 3–5× realtime on 2023+ flagship iPhones and now reaches quality parity with cloud "prime" tiers.

### 2.2 Supertonic 3 specifics

- **Model size:** ~66M params
- **Languages:** 31
- **Inference modes:** 2-step (fastest, close to ElevenLabs Flash) → 5-step (highest quality, close to ElevenLabs Prime). **Default to 4-step** for the v1 reader (balanced).
- **Output:** 44.1 kHz mono PCM float32
- **Runtime:** ONNX Runtime ≥1.16.0 (already in project)
- **Voices:** Use Supertonic 3's built-in voice presets. Expose 4–6 voices in UI (see §6.2).

### 2.3 Future cloud tier (out of scope for v1)

Architect the `Synthesizer` protocol (§4.2) such that a `CartesiaSynthesizer` or `ElevenLabsSynthesizer` could be swapped in later without touching playback, parsing, or UI. **Do not implement either.** Just keep the seam.

---

## 3. Stack Decision: Refactor In Place

The current code is modular enough that a rewrite is unnecessary. Concretely:

- **Keep verbatim:** `EpubTextParser`, `SupertonicService` synth core, `AVAudioEngine` playback pipeline, most SwiftUI views.
- **Refactor:** `PlayerService` (file-backed → buffer-streaming), `TTSGenerationService` (becomes a streaming scheduler, not a file writer), `LibraryService` (becomes a thin "saved documents" index — text only, no audio).
- **Delete:** `M4AWriter`, manifest-writing code paths, `Documents/books/[slug]/*.m4a`, `Documents/tts-progress/`.

See §7 and §8 for the full file-by-file action list.

---

## 4. Architecture

### 4.1 Component diagram

```
                ┌──────────────────────┐
   EPUB file ──▶│  EpubTextParser      │── chapters: [Chapter{paragraphs}]
                └──────────┬───────────┘
                           │
                           ▼
                ┌──────────────────────┐       ┌──────────────────────┐
                │  DocumentStore       │◀─────▶│  Disk: text JSON +   │
                │  (text + position)   │       │  position only       │
                └──────────┬───────────┘       └──────────────────────┘
                           │
                           ▼
                ┌──────────────────────┐
                │  ReaderSession       │  one active at a time
                │  (current chapter,   │
                │   paragraph cursor)  │
                └──────────┬───────────┘
                           │
            tap play       ▼
                ┌──────────────────────┐       ┌──────────────────────┐
                │  SynthScheduler      │──────▶│  Synthesizer         │
                │  (look-ahead buffer  │       │  (Supertonic 3)      │
                │  of N paragraphs)    │◀──────│  PCM float32 chunks  │
                └──────────┬───────────┘       └──────────────────────┘
                           │
                           ▼
                ┌──────────────────────┐
                │  PlayerService       │
                │  AVAudioEngine +     │
                │  AVAudioPlayerNode   │
                └──────────┬───────────┘
                           │
                           ▼
                       speaker
                           │
            highlight ◀────┘ (paragraph index events)
            current paragraph in UI
```

### 4.2 Core types (in-memory; no persistence except where noted)

```swift
// Persisted (text + cursor only — no audio)
struct SavedDocument: Codable, Identifiable {
    let id: UUID                  // stable ID, used as filename
    let title: String
    let author: String?
    let coverImageData: Data?     // small JPEG, ≤200 KB, optional
    let importedAt: Date
    var lastOpenedAt: Date
    var chapters: [ChapterText]   // text only
    var cursor: PlaybackCursor
}

struct ChapterText: Codable {
    let index: Int
    let title: String
    let paragraphs: [String]      // plain text, pre-split
}

struct PlaybackCursor: Codable {
    var chapterIndex: Int
    var paragraphIndex: Int       // paragraph user last reached
}

// Runtime only — never persisted
final class ReaderSession: ObservableObject {
    @Published var document: SavedDocument
    @Published var state: PlayerState  // .idle | .synthesizing | .playing | .paused
    @Published var currentChapter: Int
    @Published var currentParagraph: Int   // drives the highlight
    let player: PlayerService
    let scheduler: SynthScheduler
}

// Synthesis seam (allows future cloud tier)
protocol Synthesizer {
    /// Synthesize one paragraph. Returns PCM float32 @ 44.1 kHz mono.
    /// May yield multiple chunks; caller concatenates or schedules each.
    func synthesize(_ text: String, voice: VoiceID, options: SynthOptions) -> AsyncThrowingStream<PCMChunk, Error>
    func cancelAll()
}

struct PCMChunk {
    let samples: UnsafeBufferPointer<Float>
    let sampleRate: Double      // 44_100
    let isFinal: Bool           // last chunk for this paragraph
}

struct SynthOptions {
    var steps: Int = 4          // Supertonic inference steps (2…5)
    var speed: Double = 1.0     // text-level; player-level scaling also possible
}
```

### 4.3 Persistence rules

**Persisted to `Documents/library/[uuid].json`:**

- Document text (chapters + paragraphs as plain strings)
- Title, author, cover thumbnail (≤200 KB JPEG, optional)
- `PlaybackCursor` (current chapter + paragraph)
- Timestamps

**Never persisted:**

- Audio bytes (PCM, WAV, M4A, AAC, anything)
- Synthesis caches
- ONNX intermediate state (beyond the model file itself, which is cached in `Documents/Models/supertonic/` as already implemented)

**On launch:** Library lists saved documents by `lastOpenedAt` desc. Tapping a document → `ReaderSession` opens with `cursor` restored. Tapping play → live synthesis from `cursor`.

**On document delete:** Remove the JSON; no audio cleanup needed (none exists).

---

## 5. User flow

### 5.1 First-run / empty library

1. Empty state: "Open an EPUB to start reading aloud."
2. Tap "Open EPUB" → iOS document picker (UTType.epub).
3. App parses EPUB on a background queue (existing `EpubTextParser` — reuse verbatim).
4. Document saved to library (text only) → navigates to the reader view for that document.
5. Cursor defaults to chapter 0, paragraph 0.

### 5.2 Reader view

- Top: cover thumbnail, title, author.
- Middle: scrolling text of the **current chapter**. Current paragraph is highlighted (background tint + auto-scroll-to-center).
- Bottom: transport controls — chapter title, prev/next chapter, prev/next paragraph, play/pause, speed selector (0.8 / 1.0 / 1.25 / 1.5 / 1.75 / 2.0×), voice selector (sheet).
- No scrubber. Paragraph-level navigation only.

### 5.3 Play / synthesis behavior

- Tap play → `SynthScheduler` immediately starts synthesizing the **current paragraph + next 2 paragraphs** (look-ahead = 3).
- First PCM chunk schedules onto `AVAudioPlayerNode` as soon as it arrives. Target time-to-first-audio: **<500 ms** on iPhone 13 Pro or newer (achievable: Supertonic 2-step model produces first chunk in ~150 ms on flagship).
- As each paragraph finishes playing, the scheduler advances and synthesizes the next look-ahead paragraph.
- Crossing a chapter boundary: continue seamlessly; chapter view auto-changes; highlight follows.
- Pause: stop the player node, **cancel any in-flight synthesis past the current paragraph** (don't waste cycles). Buffered audio for the current paragraph is discarded.
- Resume: re-synthesize from `cursor`.
- Skip paragraph (forward/back): cancel current synthesis, advance/rewind `cursor`, restart from new position.
- Skip chapter: same as above, jump cursor to start of target chapter.

### 5.4 Backgrounding and interruptions

- `AVAudioSession` category `.playback`, mode `.spokenAudio`, options `.allowAirPlay`, `.allowBluetooth`.
- Background audio capability enabled in entitlements (already enabled — verify).
- Now Playing info: title, chapter, cover.
- Remote control events: play/pause/next/previous track → maps to chapter prev/next.
- Audio interruption (call, Siri): pause, persist cursor, resume on `.interruptionEnded` with `.shouldResume`.
- App goes to background: continue playing.
- App is force-quit or killed: cursor is already persisted (saved on every paragraph advance, debounced 1 s).

### 5.5 Session end

- User taps "Done" / back: cursor persisted, session torn down, all in-flight synthesis cancelled, `AVAudioEngine` stopped.
- Reopening the document: cursor restored, fresh synthesis starts on play.

---

## 6. UI changes

### 6.1 Screens to keep, modify, or remove

| Screen / View                 | Action       | Notes                                                                                                                              |
| ----------------------------- | ------------ | ---------------------------------------------------------------------------------------------------------------------------------- |
| `LibraryView`                 | **Modify**   | Drop generation-progress banner, "Importing…" cells, M4A duration display. Show: cover, title, author, "Last read N min ago". |
| `PlayerView`                  | **Replace**  | Becomes the *ReaderView* described in §5.2. File-based playback gone; replaced with live synth + paragraph highlighting.        |
| `TTSImportView` / generation banner | **Delete** | No more import-with-generation. EPUB import is instant (text-only).                                                            |
| Chapter picker                | **Modify**   | Show all chapters as unlocked from import (since no pre-generation). Tap → set cursor → play.                                  |
| Voice / speed settings sheet  | **New**      | See §6.2.                                                                                                                          |
| Onboarding                    | **Modify**   | Remove any "first book is generating" language.                                                                                  |

### 6.2 Settings sheet (new)

Reachable from a gear icon in the reader. Per-document settings (not global — store on `SavedDocument`, default from a user-prefs singleton):

- **Voice:** 4–6 Supertonic 3 voices, each with a name and a "Play sample" button (synthesizes one short sentence).
- **Speed:** segmented control: 0.8 / 1.0 / 1.25 / 1.5 / 1.75 / 2.0×.
  - Speed is applied at the `AVAudioPlayerNode`/`AVAudioUnitTimePitch` layer (rate change without pitch shift), not in synthesis. Don't re-synthesize on speed change.
- **Quality:** "Fast / Balanced / High" → maps to Supertonic steps 2 / 4 / 5. Default Balanced.

---

## 7. Files to **delete**

```
Sources/.../M4AWriter.swift                  # WAV→M4A encoder. Audio no longer persisted.
Sources/.../tts-progress/*.swift             # Progress cache; not needed without pre-gen.
Documents/books/                             # Runtime: wipe on first launch of new build.
Documents/tts-progress/                      # Runtime: wipe on first launch.
```

Add a one-shot migration on app startup (v2 first launch): if `Documents/books/` exists, delete it. Log the cleanup.

---

## 8. Files to **refactor**

### 8.1 `TTSGenerationService.swift` → rename to `SynthScheduler.swift`

**Current responsibility:** Iterate paragraphs, call Supertonic, write WAV, encode M4A, update manifest.

**New responsibility:** Maintain a look-ahead buffer (size 3) of synthesized paragraphs. Coordinate with `PlayerService` to schedule PCM onto the player node. Cancel cleanly on pause/skip.

**Key methods:**

```swift
final class SynthScheduler {
    init(synthesizer: Synthesizer, player: PlayerService, lookAhead: Int = 3)
    func start(from cursor: PlaybackCursor, in document: SavedDocument)
    func advanceTo(cursor: PlaybackCursor)   // skip
    func pause()
    func resume()
    var onParagraphStartedPlaying: ((PlaybackCursor) -> Void)?  // drives UI highlight
}
```

Internally uses `AsyncThrowingStream` from the `Synthesizer` protocol. Each paragraph's PCM is scheduled onto `AVAudioPlayerNode` via `scheduleBuffer(_:at:options:completionHandler:)` with a completion that advances the cursor and fires `onParagraphStartedPlaying` for the *next* paragraph.

**Crucially:** never call `M4AWriter`. Never touch the filesystem.

### 8.2 `SupertonicService.swift` → `SupertonicSynthesizer.swift`

Adopt the `Synthesizer` protocol (§4.2). Keep the ONNX model loading and `synthesize()` core. Remove any code that writes WAVs or returns file URLs. Output `AsyncThrowingStream<PCMChunk, Error>`.

Upgrade the bundled model to **Supertonic 3** (download URL from supertone-inc/supertonic releases). Keep the existing on-first-launch model download flow.

### 8.3 `PlayerService.swift`

**Current:** Reads M4A files from `Documents/books/[slug]/`, loads into `AVPlayer`/`AVAudioFile`, plays.

**New:** Owns `AVAudioEngine` + `AVAudioPlayerNode` + optional `AVAudioUnitTimePitch` for speed control. Exposes:

```swift
final class PlayerService {
    func schedule(_ buffer: AVAudioPCMBuffer, completion: @escaping () -> Void)
    func play()
    func pause()
    func stop()                // clears scheduled buffers
    func setRate(_ rate: Float) // 0.8…2.0
    var isPlaying: Bool { get }
}
```

The `AVAudioFormat` is fixed: 44.1 kHz, mono, float32, non-interleaved. `SynthScheduler` converts `PCMChunk` → `AVAudioPCMBuffer` and hands it to `schedule(_:completion:)`.

### 8.4 `LibraryService.swift`

**Current:** Scans `Documents/books/` for `manifest.json` files.

**New:** Scans `Documents/library/` for `[uuid].json` containing `SavedDocument`. Sort by `lastOpenedAt`. CRUD operations: `import(epubURL:)`, `delete(id:)`, `loadAll()`, `update(_ document:)`.

### 8.5 `Models.swift`, `BookPaths.swift`

Drop `BookManifest`, `Chapter.audio`, `Chapter.duration`. Replace with `SavedDocument`, `ChapterText` (§4.2). `BookPaths` becomes `LibraryPaths`: only the `library/` directory.

---

## 9. Files to **keep verbatim** (or near-verbatim)

- `EpubTextParser.swift` — EPUB → text extraction. Already correct.
- `ZipExtractor.swift` — Reused by parser.
- `XMLIndexer` and supporting parsing utilities.
- Most SwiftUI components for library cells, navigation, error views.
- `AppState` singleton structure (just changes what it holds).

---

## 10. Visual text follow-along (highlight current paragraph)

Implementation:

1. The chapter text is rendered as a `ScrollViewReader` containing a `LazyVStack` of `Text(paragraph)` views, each with `.id(paragraphIndex)`.
2. The current paragraph view applies a background tint (`Color.accentColor.opacity(0.15)`) and a slightly heavier font weight.
3. When `ReaderSession.currentParagraph` changes, call `scrollProxy.scrollTo(idx, anchor: .center)` with `.easeInOut(duration: 0.25)`.
4. The trigger for `currentParagraph` change is the `onParagraphStartedPlaying` callback on `SynthScheduler` — fires at the moment a paragraph's audio actually begins playing on the audio node, **not** when synthesis starts. This keeps the highlight in sync with the ear.
5. Tapping a paragraph in the text → set cursor to that paragraph, restart synthesis.

No word-level highlighting in v1.

---

## 11. Edge cases

| Scenario                                       | Behavior                                                                                                                                              |
| ---------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------- |
| Empty paragraph (whitespace-only)              | `EpubTextParser` should skip these at parse time. Defensive check in scheduler: skip and advance cursor.                                                |
| Paragraph >2000 chars (long passage)           | Split at sentence boundaries before synthesis (heuristic: `.!?` followed by space + capital). Treat each piece as a sub-paragraph internally.            |
| EPUB with no `<p>` tags / one giant blob       | Parser fallback: split by `\n\n` or `.` heuristic into ~200-word chunks.                                                                                |
| ONNX model not yet downloaded on first play    | Show a determinate progress sheet; block playback until ready. (Same as today.)                                                                       |
| Low Power Mode                                 | Lower default synthesis steps to 2 (Fast). Restore on exit from low power mode.                                                                       |
| Cursor points past end of chapter              | Clamp to last paragraph; if at end of last chapter, stop with "End of book" state.                                                                    |
| Audio session interruption mid-paragraph       | Pause player, keep cursor at the paragraph that was *playing* (not buffered-ahead). On resume, re-synthesize from that paragraph.                       |
| User imports the same EPUB twice               | Detect by SHA256 of EPUB bytes. If match → open existing `SavedDocument`, don't re-import. Update `lastOpenedAt`.                                       |
| Corrupted / malformed EPUB                     | Show parse error, don't add to library.                                                                                                               |
| Device runs out of RAM during synthesis        | `SynthScheduler` caps look-ahead PCM in memory at ~30 seconds. If exceeded, pauses synthesis until player drains.                                       |
| User scrubs to a paragraph 100+ ahead instantly | Cancel all in-flight, set cursor, restart synthesis from new cursor. First audio in <500 ms.                                                          |
| Voice change mid-playback                      | Pause, cancel synth, change voice, resume — re-synthesize current paragraph with new voice.                                                            |
| Speed change mid-playback                      | Apply at `AVAudioUnitTimePitch` immediately. **Do not re-synthesize.**                                                                                   |

---

## 12. Acceptance criteria (test checklist)

### Functional

- [ ] Import an EPUB → appears in library within 2 s (text-only parse).
- [ ] Tap chapter → first audio plays within 500 ms on iPhone 13 Pro or newer (Balanced quality).
- [ ] Current paragraph is highlighted and auto-scrolls into view as it begins playing.
- [ ] Prev/next paragraph button works within 200 ms of tap (synthesis restart latency).
- [ ] Prev/next chapter button jumps cursor and synthesizes from chapter start.
- [ ] Pause + resume preserves cursor exactly (resumes at the paragraph that was playing).
- [ ] Force-quit + relaunch → document still in library, cursor restored, tap play → resumes at correct paragraph.
- [ ] Backgrounding → audio continues playing.
- [ ] Lock screen Now Playing controls show title + cover and play/pause works.
- [ ] Phone call interrupts → audio pauses → call ends → audio resumes.
- [ ] Speed change applies in <500 ms without re-synthesizing.
- [ ] Voice change applies cleanly (brief pause acceptable while re-synthesizing current paragraph).
- [ ] Reaching end of last chapter → state goes to `.ended`, transport shows "Restart" affordance.

### Non-functional / contract

- [ ] **`find Documents -name "*.m4a" -o -name "*.wav" -o -name "*.aac"` returns nothing** after a 30-min reading session.
- [ ] `Documents/library/` contains only `[uuid].json` files and (optionally) tiny cover JPEGs.
- [ ] App makes **zero outbound network requests** during a reading session (verify with Charles / Proxyman).
  - Exception: the one-time Supertonic 3 model download on first launch.
- [ ] Memory usage stable below 250 MB during continuous playback (look-ahead cap working).
- [ ] CPU usage <30% sustained on iPhone 13 Pro during Balanced-quality playback.
- [ ] No `M4AWriter`, `manifest.json`, or `tts-progress` symbols remain in the codebase (grep clean).

### Migration

- [ ] On first launch of new build: any pre-existing `Documents/books/` is removed without prompting; user library starts empty.

---

## 13. Open / out-of-scope items (future)

- **PDF support (v2):** PDFKit-based text extraction; chapter splitting heuristic via font-size deltas or outline (`PDFDocument.outlineRoot`).
- **Pasted-text input (v2):** Accept raw text → treat as single-chapter `SavedDocument`.
- **Cloud premium voice tier:** Implement `CartesiaSynthesizer: Synthesizer`. Gated behind subscription. The `Synthesizer` protocol already accommodates this.
- **Word-level karaoke highlighting:** Requires per-token timing from the TTS engine. Supertonic 3 does not expose this in v1 of the integration; revisit if/when added.
- **Position sync across devices:** Out of scope. App is local-only.
- **Export to audio file:** Explicitly *not* a feature. The whole point is ephemerality.

---

## 14. Implementation order (suggested)

1. **Branch + cleanup.** Delete `M4AWriter`, persistence code paths, `Documents/books/` migration shim. Project should still compile (stub out call sites).
2. **Types refresh.** Introduce `SavedDocument`, `ChapterText`, `PlaybackCursor`. Update `LibraryService` to read/write the new format.
3. **`Synthesizer` protocol + `SupertonicSynthesizer`.** Refactor `SupertonicService` to the streaming protocol. Upgrade to Supertonic 3 model.
4. **`PlayerService` rebuild.** New buffer-streaming version with `AVAudioEngine` + `AVAudioPlayerNode` + `AVAudioUnitTimePitch`.
5. **`SynthScheduler`.** Look-ahead scheduling, cancellation, cursor advancement.
6. **`ReaderView` UI.** Replace the old `PlayerView`. Paragraph list + highlight + transport.
7. **`LibraryView` cleanup.** Remove generation banner / progress UI.
8. **Settings sheet** (voice, speed, quality).
9. **Edge cases pass** (interruptions, backgrounding, low power, end-of-book).
10. **Acceptance checklist + manual QA on a real device.**

Each step should leave the app in a buildable, runnable state.

---

## References

- Repo survey (architecture, current files): conducted in-session, May 2026.
- [Supertonic 3 (supertone-inc/supertonic GitHub)](https://github.com/supertone-inc/supertonic/) — release 2026-04-29, 31 languages, ONNX assets.
- [Kokoro-82M for iOS](https://github.com/mlalma/kokoro-ios) — considered as on-device alternative.
- [Cartesia Sonic 3](https://cartesia.ai/sonic) — considered as future cloud tier.
- [ElevenLabs Flash v2.5 / v3](https://elevenlabs.io/docs/overview/models) — considered as future cloud tier.
- [Gladia 2026 TTS API comparison](https://www.gladia.io/blog/best-tts-apis-for-developers-in-2026-top-7-text-to-speech-services)
- [Inworld 2026 TTS benchmarks](https://inworld.ai/resources/best-voice-ai-tts-apis-for-real-time-voice-agents-2026-benchmarks)
