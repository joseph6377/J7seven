# BooksApp v2 — TTS Implementation Plan

## Goal
Allow the user to import a **text-only EPUB** into BooksApp v2, synthesise it to audio
on-device using **Supertone Supertonic** (ONNX, ~99M params), play back audio
**immediately** while synthesis continues in the background, and save the result as
standard per-chapter **M4A + manifest.json** (same format as BooksApp v1 — existing
PlayerService and LibraryService work unchanged).

---

## Key Decisions (already made)

| Decision | Choice |
|---|---|
| Where generation runs | **On-device iPhone** |
| Word highlighting | **Not needed** — paragraph timing only |
| EPUB import trigger | **iOS Document Picker** (tap + in Library) |
| Voice selection | **Picker in import flow** (baked into M4A) |
| Chunk size | **Paragraph** (~2–5 s latency, natural prosody) |
| Output format | **Per-chapter M4A + manifest.json** (v1 format) |
| Playback start | **After first paragraph** — stream as you go |
| Interrupted synthesis | **Save progress + resume** |
| Model download | **On first EPUB import** (one-time, ~200–400 MB) |

---

## What Does NOT Change (copied verbatim from v1)

- `PlayerService.swift` — unchanged
- `LibraryService.swift` — unchanged (scans for manifest.json as before)
- `PlayerView.swift` / `ReaderView.swift` — unchanged
- `BookPaths.swift` — unchanged
- `Models.swift` — unchanged (`wordEnds` stays empty `[]` for TTS books)
- `ZipExtractor.swift` — reused by EpubTextParser
- `MiniPlayerView.swift`, `CoverImageView.swift` — unchanged

---

## Output Format (matches v1 library)

```
Documents/books/[slug]/
  manifest.json          ← BookManifest (paragraph start/end, empty wordEnds)
  cover.jpg              ← extracted from EPUB if present
  ch-0.m4a               ← AAC audio for chapter 0
  ch-1.m4a               ← AAC audio for chapter 1
  ch-0.html              ← <p id="[slug]-ch0-p0">text</p> structure
  ch-1.html
```

`PlayerService` loads `ch-N.m4a` via `localURL(slug:filename:)` — zero changes needed.
`LibraryService.scanLocalLibrary()` picks up `manifest.json` automatically.

---

## Supertonic SDK Integration

### Step 1 — Clone the repo
```bash
git clone https://github.com/supertone-inc/supertonic
```

### Step 2 — Copy Swift helper sources
```
supertonic/swift/Sources/Helper.swift
  → Sources/Services/TTS/SupertonicHelper.swift

supertonic/ios/ExampleiOSApp/ExampleiOSApp/TTSService.swift
  → Sources/Services/TTS/SupertonicONNX.swift
```
**Audit these files first** — their real function signatures override anything assumed
in the skeleton code. Update `SupertonicService.synthesize()` to match the actual API.

### Step 3 — SPM dependency (already in project.yml)
```yaml
packages:
  onnxruntime:
    url: https://github.com/microsoft/onnxruntime-swift-package-manager
    from: 1.16.0
```

### Step 4 — Model download URL
Find the ONNX model download URL in the supertonic README or GitHub releases page.
Set it in `SupertonicService.modelDownloadURL`.
Model is stored at: `Documents/Models/supertonic/` (created on first download).

### Step 5 — Voice style JSONs
Copy `supertonic/assets/*.json` → `Resources/tts-voices/`.
Update `TTSVoice.loadAll()` with real voice IDs and names from those files.

---

## New Files Created (skeletons in repo)

### `Sources/Services/TTS/EpubTextParser.swift`
Parses a text-only EPUB (no media overlays required) into chapters of plain text.

```swift
enum EpubTextParser {
    struct ParsedBook {
        let title: String
        let author: String
        let slug: String
        let coverData: Data?
        let chapters: [EpubChapter]
    }
    static func parse(epubURL: URL) throws -> ParsedBook
}
struct EpubChapter {
    let title: String
    let paragraphs: [String]   // plain text, one per <p>
}
```

**Key difference from v1 EpubParser:** does NOT require SMIL/audio overlays.
Extracts `<p>` text from each XHTML spine item.
TOC titles from nav doc (EPUB 3) or NCX (EPUB 2 fallback).

---

### `Sources/Services/TTS/SupertonicService.swift`
`@Observable @MainActor` wrapper around Supertonic ONNX inference.

```swift
enum ModelState {
    case notDownloaded
    case downloading(progress: Double)
    case loading
    case ready
    case error(String)
}

final class SupertonicService {
    var modelState: ModelState
    var realtimeFactor: Double       // audioSeconds / wallClockSeconds

    func downloadModel() async throws
    func synthesize(text: String, voice: TTSVoice) async throws -> AVAudioPCMBuffer
}
```

**TODOs in skeleton:**
- Set `modelDownloadURL`
- Implement model download with URLSession progress reporting
- Implement `synthesize()` using the real Supertonic API from `SupertonicONNX.swift`

---

### `Sources/Services/TTS/TTSVoice.swift`
Voice model parsed from Supertonic voice style JSON files.

```swift
struct TTSVoice: Identifiable, Hashable, Codable {
    let id: String        // e.g. "en-male-1"
    let name: String      // e.g. "Alex"
    let language: String  // e.g. "en"
    let gender: Gender    // .male / .female

    static func loadAll() -> [TTSVoice]
    static let default: TTSVoice
}
```

**TODO:** Replace placeholder voices with real IDs after inspecting `supertonic/assets/*.json`.

---

### `Sources/Services/TTS/TTSProgress.swift`
Codable progress state saved after each paragraph. Enables resume on interruption.

```swift
struct TTSProgress: Codable {
    let slug: String
    let voiceId: String
    var completedParagraphs: [CompletedParagraph]

    struct CompletedParagraph: Codable {
        let chapterIdx: Int
        let paragraphIdx: Int
        let paragraphId: String   // matches <p id=""> in HTML + Paragraph.id in manifest
        let startTime: Double     // cumulative seconds within chapter
        let endTime: Double
        let tempWavPath: String   // path to cached WAV file
    }

    func save() throws
    static func load(slug: String) -> TTSProgress?
    static func delete(slug: String)
    func isCompleted(chapterIdx: Int, paragraphIdx: Int) -> Bool
}
```

Saved to: `Documents/tts-progress/[slug].json`

---

### `Sources/Services/TTS/TTSGenerationService.swift`
`@Observable @MainActor` — orchestrates the full pipeline.

```swift
enum GenerationState {
    case idle
    case preparingModel
    case generating(chapter: Int, paragraph: Int, totalParagraphs: Int)
    case paused
    case finalizingAudio
    case done(slug: String)
    case failed(String)
}

final class TTSGenerationService {
    var state: GenerationState
    var canPlayNow: Bool            // true after first paragraph synthesised
    var isActive: Bool              // true while generating or paused
    var currentlyPlayingParagraphId: String?

    func generate(epubURL: URL, voice: TTSVoice)
    func pause()
    func resume()
    func cancel()
}
```

**Internal pipeline:**
```
EpubTextParser.parse(epubURL)
  → TTSProgress.load(slug) — resume from saved state if available
  → for each chapter → for each paragraph:
      SupertonicService.synthesize(text, voice) → AVAudioPCMBuffer
      playerNode.scheduleBuffer(buffer)          → immediate gapless playback
      canPlayNow = true                          → "Listen Now" button activates
      saveTempWAV(buffer)                        → cache for M4A encoding
      TTSProgress.save()                         → persist after each paragraph
  → M4AWriter.finalizeChapter(idx, paragraphs)  → write ch-N.m4a + ch-N.html
  → M4AWriter.finalizeBook()                    → write manifest.json + cover
  → TTSProgress.delete(slug)
  → state = .done(slug)                         → LibraryView refreshes
```

**Gapless playback with AVAudioEngine:**
```swift
let engine     = AVAudioEngine()
let playerNode = AVAudioPlayerNode()
engine.attach(playerNode)
engine.connect(playerNode, to: engine.mainMixerNode, format: outputFormat)
try engine.start()

// After each synthesis:
playerNode.scheduleBuffer(buffer) {
    // completion → update currentlyPlayingParagraphId
}
if !playerNode.isPlaying { playerNode.play() }
```

**Background execution:** Wrap generation loop in `UIApplication.beginBackgroundTask`.

**TODO in skeleton:** Complete `saveTempWAV` using `AVAudioFile`.

---

### `Sources/Services/TTS/M4AWriter.swift`
Converts synthesis output to BooksApp library format.

```swift
final class M4AWriter {
    init(slug: String, title: String, author: String,
         coverData: Data?, chapters: [EpubChapter])

    func finalizeChapter(_ idx: Int,
                         paragraphs: [TTSProgress.CompletedParagraph]) throws
    func finalizeBook() throws
}
```

**TODO in skeleton — `encodeToM4A`:**

Option A (simpler — try this first):
```swift
let aacSettings: [String: Any] = [
    AVFormatIDKey:         kAudioFormatMPEG4AAC,
    AVSampleRateKey:       44100,
    AVNumberOfChannelsKey: 1,
    AVEncoderBitRateKey:   64_000
]
let outFile = try AVAudioFile(forWriting: outputURL, settings: aacSettings)
for p in paragraphs {
    let wavFile = try AVAudioFile(forReading: URL(fileURLWithPath: p.tempWavPath))
    let buf = AVAudioPCMBuffer(pcmFormat: wavFile.processingFormat,
                               frameCapacity: AVAudioFrameCount(wavFile.length))!
    try wavFile.read(into: buf)
    // AVAudioConverter pcm → aac, then write to outFile
}
```

Option B (more control): `AVAssetWriter` with `CMSampleBuffer` conversion.

---

## New UI Files

### `Sources/Views/TTS/TTSImportView.swift`
Sheet shown after user picks an EPUB. Shows metadata preview + voice picker.

```
┌─────────────────────────────────┐
│  📖 The Martian                 │
│  Andy Weir · 31 chapters        │
│                                 │
│  Voice                          │
│  ┌──────────┐  ┌──────────┐    │
│  │ ● Alex   │  │   Sarah  │    │
│  │  Male    │  │  Female  │    │
│  └──────────┘  └──────────┘    │
│                                 │
│  [Generate & Play]              │
└─────────────────────────────────┘
```

Flow:
1. `EpubTextParser.parse(epubURL)` on appear
2. User picks voice
3. Tap "Generate & Play":
   - If model not downloaded → show `ModelDownloadView` first
   - Otherwise → `TTSGenerationService.generate(epubURL, voice)` → dismiss

---

### `Sources/Views/TTS/ModelDownloadView.swift`
Shown on first import. One-time model download with progress bar.

```
┌─────────────────────────────────┐
│  📥 One-Time Setup              │
│  Downloading voice model        │
│  ████████░░░░ 68%               │
│  This only happens once.        │
│  [Cancel]                       │
└─────────────────────────────────┘
```

Calls `SupertonicService.downloadModel()` on appear.
Dismisses and triggers generation when `modelState == .ready`.

---

### `Sources/Views/TTS/TTSProgressBanner.swift`
Persistent banner in Library while generation is active (similar to MiniPlayerView).

```
┌──────────────────────────────────────────┐
│  🎙 Generating audiobook…               │
│  Chapter 3 · Paragraph 12 of 47         │
│                      [▶ Listen]  [⏸]   │
└──────────────────────────────────────────┘
```

- "Listen" → opens PlayerView for the in-progress book
- Pause/Resume → `TTSGenerationService.pause()` / `.resume()`
- Shown via `safeAreaInset(edge: .bottom)` in `ContentView`

---

## Changes to Existing-Style Files in v2

### `Sources/App/AppState.swift`
```swift
let supertonicService    = SupertonicService()
let ttsGenerationService = TTSGenerationService(supertonicService: supertonicService)
```

### `Sources/Views/ContentView.swift`
- `fileImporter` with `.epub` content type → presents `TTSImportView`
- `safeAreaInset(edge: .bottom)` → `TTSProgressBanner` when `isActive`

### `Sources/Views/Library/LibraryView.swift`
- Book list + swipe-to-delete
- `.onChange(of: ttsGenerationService.state)` → `appState.refresh()` when `.done`

---

## Implementation Order

### Phase 1 — Supertonic integration (no UI)
1. Clone supertonic repo, copy `Helper.swift` + `TTSService.swift`
2. Audit real Swift API signatures
3. Update `SupertonicService.synthesize()` with real call
4. Set `modelDownloadURL`, implement download with URLSession
5. Smoke test: synthesise one sentence, log duration + RTF

### Phase 2 — Parsing + output
6. Complete `EpubTextParser.extractParagraphs` (XHTML `<p>` → plain text)
7. Complete `M4AWriter.encodeToM4A` (WAV → AAC → M4A)
8. Complete `saveTempWAV` in `TTSGenerationService` using `AVAudioFile`
9. Update `TTSVoice.loadAll()` with real voice IDs from supertonic assets

### Phase 3 — Full pipeline test
10. Generate a short book end-to-end (EPUB → M4A → manifest → library)
11. Verify `LibraryService` picks it up and `PlayerService` plays it

### Phase 4 — UI polish
12. Wire `ContentView` file importer
13. Add cover image display to `TTSImportView`
14. Test pause/resume, background execution, interrupted synthesis + resume
15. Add `.epub` UTType to Info.plist if needed

---

## Critical Technical Notes

### Supertonic output format
44100 Hz mono 16-bit PCM WAV.
Convert to `AVAudioPCMBuffer` with `pcmFormatInt16` or `pcmFormatFloat32`
(convert int16 → float32 if AVAudioEngine requires float).

### Paragraph IDs (must be consistent)
Generated as: `"\(slug)-ch\(chapterIdx)-p\(paragraphIdx)"`
- Must match `<p id="...">` in generated HTML
- Must match `Paragraph.id` in `manifest.json`
- `PlayerService.currentParagraphId` matches these → paragraph highlighting works automatically

### AVAudioConverter: int16 PCM → float32
```swift
let inFormat  = AVAudioFormat(commonFormat: .pcmFormatInt16,
                               sampleRate: 44100, channels: 1, interleaved: true)!
let outFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                               sampleRate: 44100, channels: 1, interleaved: false)!
let converter = AVAudioConverter(from: inFormat, to: outFormat)!
let outBuf    = AVAudioPCMBuffer(pcmFormat: outFormat,
                                  frameCapacity: inBuf.frameLength)!
try converter.convert(to: outBuf, from: inBuf)
```

### iOS background + audio session
Register `UIBackgroundTaskIdentifier` for CPU work.
Set audio session to `.playback` so the process stays alive while audio plays:
```swift
try AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
try AVAudioSession.sharedInstance().setActive(true)
```

### No force-unwraps in new code
Use `guard let` / `try?` with graceful fallbacks. Skip bad paragraphs rather than
aborting the whole book.
