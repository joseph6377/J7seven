# BooksApp v2 — TTS Implementation Plan

## Goal
Import a **text-only EPUB**, synthesise it to audio on-device using **Supertone
Supertonic** (ONNX, ~99M params), play audio **immediately** while synthesis continues
in the background, and save the result as per-chapter **M4A + manifest.json**.

**Pure audio output — no text display, no reader, no highlighting of any kind.**

---

## Key Decisions

| Decision | Choice |
|---|---|
| Where generation runs | On-device iPhone |
| Text display / highlighting | **None — pure audio only** |
| EPUB import | iOS Document Picker (tap + in Library) |
| Voice selection | Picker in import flow (baked into M4A) |
| Chunk size | Paragraph (~2–5 s latency, natural prosody) |
| Output format | Per-chapter M4A + manifest.json |
| Paragraphs in manifest | **Empty `[]`** — no timing needed |
| HTML chapter files | **Not generated** |
| Playback start | After first paragraph — stream as you go |
| Interrupted synthesis | Save progress + resume |
| Model download | On first EPUB import (one-time, ~200–400 MB) |

---

## Output Format

```
Documents/books/[slug]/
  manifest.json    ← chapters with audio paths + durations; paragraphs: []
  cover.jpg        ← extracted from EPUB if present
  ch-0.m4a
  ch-1.m4a
  ...
```

`LibraryService.scanLocalLibrary()` picks up `manifest.json` automatically.
`PlayerService` loads `ch-N.m4a` — no changes needed.

---

## What Does NOT Change (copied verbatim from v1)

- `PlayerService.swift`
- `LibraryService.swift`
- `BookPaths.swift`
- `Models.swift` (`paragraphs: []` and `html: ""` are valid)
- `ZipExtractor.swift` (reused by EpubTextParser)
- `MiniPlayerView.swift`, `CoverImageView.swift`

**Removed vs v1:** `ReaderView.swift` — not needed.

---

## Supertonic SDK Integration

### Step 1 — Clone the repo
```bash
git clone https://github.com/supertone-inc/supertonic
```

### Step 2 — Copy Swift helper sources into this project
```
supertonic/swift/Sources/Helper.swift
  → Sources/Services/TTS/SupertonicHelper.swift

supertonic/ios/ExampleiOSApp/ExampleiOSApp/TTSService.swift
  → Sources/Services/TTS/SupertonicONNX.swift
```
**Audit these files first.** Their real function signatures override everything
assumed in the `SupertonicService` skeleton. Update `synthesize()` to match.

### Step 3 — SPM dependency (already in project.yml)
```yaml
packages:
  onnxruntime:
    url: https://github.com/microsoft/onnxruntime-swift-package-manager
    from: 1.16.0
```

### Step 4 — Model download URL
Find the ONNX model download URL in the supertonic README / GitHub releases.
Set it in `SupertonicService.modelDownloadURL`.
Stored at: `Documents/Models/supertonic/`

### Step 5 — Voice style JSONs
Copy `supertonic/assets/*.json` → `Resources/tts-voices/`.
Update `TTSVoice.loadAll()` with real IDs from those files.

---

## File List

```
Sources/
  App/
    BooksAppV2.swift
    AppState.swift
  Models/
    Models.swift                  ← unchanged from v1
  Services/
    BookPaths.swift               ← unchanged from v1
    LibraryService.swift          ← unchanged from v1
    PlayerService.swift           ← unchanged from v1
    ZipExtractor.swift            ← unchanged from v1
    Keychain.swift                ← unchanged from v1
    ServerConfig.swift            ← unchanged from v1
    TTS/
      EpubTextParser.swift        ← parse text-only EPUB → chapters of plain text
      SupertonicService.swift     ← ONNX model download + synthesis
      SupertonicHelper.swift      ← COPY from supertonic/swift/Sources/
      SupertonicONNX.swift        ← COPY from supertonic/ios/ExampleiOSApp/
      TTSVoice.swift              ← voice model (update with real IDs)
      TTSProgress.swift           ← resume state (chapter/para index + WAV path)
      TTSGenerationService.swift  ← synthesis loop + AVAudioEngine playback
      M4AWriter.swift             ← WAV files → M4A + manifest.json
  Views/
    ContentView.swift
    Library/
      LibraryView.swift
    Player/
      PlayerView.swift            ← audio controls + cover art (no reader)
    Components/
      MiniPlayerView.swift
      CoverImageView.swift
    TTS/
      TTSImportView.swift         ← document picker + voice picker
      ModelDownloadView.swift     ← one-time model download progress
      TTSProgressBanner.swift     ← generation status banner
Resources/
  tts-voices/                     ← voice style JSONs from supertonic/assets/
project.yml
```

---

## Service APIs

### `EpubTextParser`
```swift
struct EpubChapter { let title: String; let paragraphs: [String] }

enum EpubTextParser {
    struct ParsedBook {
        let title: String; let author: String; let slug: String
        let coverData: Data?; let chapters: [EpubChapter]
    }
    static func parse(epubURL: URL) throws -> ParsedBook
}
```
Extracts `<p>` text from each XHTML spine item. No media overlays required.

---

### `SupertonicService`
```swift
enum ModelState { case notDownloaded, downloading(Double), loading, ready, error(String) }

@Observable @MainActor final class SupertonicService {
    var modelState: ModelState
    var realtimeFactor: Double          // audioSeconds / wallClockSeconds

    func downloadModel() async throws
    func synthesize(text: String, voice: TTSVoice) async throws -> AVAudioPCMBuffer
    // Returns 44100 Hz mono PCM buffer
}
```

**TODOs:**
- Set `modelDownloadURL`
- Implement download with URLSession progress reporting
- Implement `synthesize()` using real API from `SupertonicONNX.swift`

---

### `TTSProgress`
```swift
struct TTSProgress: Codable {
    let slug: String; let voiceId: String
    var completedParagraphs: [CompletedParagraph]

    struct CompletedParagraph: Codable {
        let chapterIdx: Int; let paragraphIdx: Int
        let tempWavPath: String    // cached WAV for M4A encoding
    }

    func save() throws
    static func load(slug: String) -> TTSProgress?
    static func delete(slug: String)
    func isCompleted(chapterIdx: Int, paragraphIdx: Int) -> Bool
    func wavPaths(forChapter idx: Int) -> [String]  // sorted by paragraphIdx
}
```
Saved to: `Documents/tts-progress/[slug].json`

---

### `TTSGenerationService`
```swift
enum GenerationState {
    case idle, preparingModel
    case generating(chapter: Int, paragraph: Int, totalParagraphs: Int)
    case paused, finalizingAudio, done(slug: String), failed(String)
}

@Observable @MainActor final class TTSGenerationService {
    var state: GenerationState
    var canPlayNow: Bool       // true after first buffer — enables "Listen Now"
    var isActive: Bool         // true while generating or paused

    func generate(epubURL: URL, voice: TTSVoice)
    func pause(); func resume(); func cancel()
}
```

**Pipeline:**
```
EpubTextParser.parse(epubURL)
  → TTSProgress.load(slug)   — skip already-done paragraphs
  → for each chapter → for each paragraph:
      SupertonicService.synthesize(text, voice) → AVAudioPCMBuffer
      playerNode.scheduleBuffer(buffer)          → gapless playback immediately
      canPlayNow = true
      saveTempWAV(buffer)                        → cache for M4A encoding
      TTSProgress.save()                         → persist progress
  → M4AWriter.finalizeChapter(idx, wavPaths)    → ch-N.m4a
  → M4AWriter.finalizeBook()                    → manifest.json + cover
  → TTSProgress.delete(slug)
  → cleanupTempWAVs()
  → state = .done(slug)                         → LibraryView refreshes
```

**TODOs in skeleton:**
- Complete `saveTempWAV` using `AVAudioFile`

---

### `M4AWriter`
```swift
final class M4AWriter {
    init(slug: String, title: String, author: String,
         coverData: Data?, chapterTitles: [String])

    func finalizeChapter(_ idx: Int, wavPaths: [String]) throws  // → ch-N.m4a
    func finalizeBook() throws                                    // → manifest.json
}
```

`manifest.json` chapters have `html: ""` and `paragraphs: []`.
No HTML files written.

**TODO — `encodeToM4A`:**
```swift
let aacSettings: [String: Any] = [
    AVFormatIDKey: kAudioFormatMPEG4AAC,
    AVSampleRateKey: 44100,
    AVNumberOfChannelsKey: 1,
    AVEncoderBitRateKey: 64_000
]
let outFile = try AVAudioFile(forWriting: outputURL, settings: aacSettings)
for path in wavPaths {
    let inFile = try AVAudioFile(forReading: URL(fileURLWithPath: path))
    let buf = AVAudioPCMBuffer(pcmFormat: inFile.processingFormat,
                               frameCapacity: AVAudioFrameCount(inFile.length))!
    try inFile.read(into: buf)
    try outFile.write(from: buf)   // AVAudioFile handles PCM→AAC on iOS
}
```

---

## UI

### `TTSImportView` — sheet after EPUB is picked
```
┌─────────────────────────────────┐
│  📖 The Martian                 │
│  Andy Weir · 31 chapters        │
│                                 │
│  Voice                          │
│  [ Alex ♂ ]  [ Sarah ♀ ]       │
│                                 │
│  [ Generate & Play ]            │
└─────────────────────────────────┘
```

### `ModelDownloadView` — one-time model download
```
┌─────────────────────────────────┐
│  📥 One-Time Setup              │
│  ████████░░░ 68%  ~350 MB       │
│  [ Cancel ]                     │
└─────────────────────────────────┘
```

### `TTSProgressBanner` — persistent banner while generating
```
┌──────────────────────────────────────┐
│  🎙 Generating audiobook…           │
│  Chapter 3 · Paragraph 12 of 47     │
│                  [ ▶ Listen ]  [⏸] │
└──────────────────────────────────────┘
```
Shown via `safeAreaInset(edge: .bottom)` in `ContentView`.

---

## Implementation Order

### Phase 1 — Supertonic integration
1. Clone supertonic, copy `Helper.swift` + `TTSService.swift`
2. Audit real Swift API signatures
3. Update `SupertonicService.synthesize()` with real call
4. Set `modelDownloadURL`, implement download
5. Smoke test: synthesise one sentence, verify `AVAudioPCMBuffer` output

### Phase 2 — Parsing + output
6. Complete `EpubTextParser.extractParagraphs` (XHTML → plain text strings)
7. Complete `saveTempWAV` in `TTSGenerationService` using `AVAudioFile`
8. Complete `M4AWriter.encodeToM4A` (WAV files → single M4A per chapter)
9. Update `TTSVoice.loadAll()` with real voice IDs from supertonic assets

### Phase 3 — Full pipeline test
10. Import a short EPUB end-to-end: EPUB → M4A → manifest → library → playback
11. Verify `PlayerService` plays the generated M4A correctly

### Phase 4 — UI + polish
12. Wire `ContentView` file importer
13. Test pause/resume, interrupted synthesis + resume
14. Background audio session setup (`AVAudioSession.setCategory(.playback)`)
15. Test on real device

---

## Technical Notes

### Supertonic output format
44100 Hz mono 16-bit PCM.
May need conversion to float32 for `AVAudioEngine`:
```swift
let inFmt  = AVAudioFormat(commonFormat: .pcmFormatInt16,
                            sampleRate: 44100, channels: 1, interleaved: true)!
let outFmt = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                            sampleRate: 44100, channels: 1, interleaved: false)!
let converter = AVAudioConverter(from: inFmt, to: outFmt)!
```

### Audio session (set once at startup)
```swift
try AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
try AVAudioSession.sharedInstance().setActive(true)
```
Required for background audio while synthesis + playback is running.

### Background execution
```swift
var bgTask = UIBackgroundTaskIdentifier.invalid
bgTask = UIApplication.shared.beginBackgroundTask {
    UIApplication.shared.endBackgroundTask(bgTask)
}
defer { UIApplication.shared.endBackgroundTask(bgTask) }
```
iOS gives ~30 s of background CPU. While the user is listening (active audio session),
the process stays alive. Encourage the user to keep the app open or screen on.

### Gapless playback
`AVAudioPlayerNode.scheduleBuffer(_:)` chains buffers seamlessly — no gaps between
paragraphs as long as each buffer is scheduled before the previous one finishes.
Schedule one buffer ahead (lookahead) for safety.
