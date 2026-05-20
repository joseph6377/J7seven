# J7seven — EPUB Audiobook Reader

An iOS app that reads EPUB books aloud using fully on-device AI text-to-speech. No cloud calls, no per-minute cost, no audio stored to disk. Import an EPUB, tap play, and the app synthesizes speech in real time as you listen.

## Features

- **Ephemeral streaming TTS** — audio is generated and played live; nothing is ever written to disk
- **On-device synthesis** — powered by [Supertonic 3](https://github.com/supertone-inc/supertonic) (ONNX, ~400 MB one-time download)
- **10 voices** — 5 male (Marcus, Nathan, Oliver, Paul, Ryan) and 5 female (Alice, Beth, Claire, Diana, Eve)
- **31 languages** — English, Korean, Japanese, Arabic, French, German, Spanish, and more
- **Paragraph-level cursor** — position is persisted across launches; resume exactly where you left off
- **Playback speed control** — via `AVAudioUnitTimePitch` (pitch-preserving, no re-synthesis needed)
- **Background audio** — continues playing with the screen off; Lock Screen controls and Now Playing info
- **Bluetooth quality** — `AVAudioSession` configured with `.spokenAudio` mode and `.longFormAudio` policy for AAC codec on wireless headphones

## Requirements

- iOS 17.0+
- Xcode 16+
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (to regenerate the `.xcodeproj` from `project.yml`)

## Getting Started

```bash
# 1. Clone
git clone <repo-url>
cd "BooksApp v2"

# 2. Generate the Xcode project
xcodegen generate

# 3. Open and build
open BooksAppV2.xcodeproj
```

On first launch the app will prompt to download the Supertonic 3 model (~400 MB). This is a one-time download stored at `Documents/Models/supertonic/`.

## Architecture

```
EPUB file
    │
    ▼
EpubTextParser          → chapters: [ChapterText { paragraphs: [String] }]
    │
    ▼
LibraryService          → SavedDocument persisted to Documents/library/[uuid].json
    │
    ▼
ReaderSession           → active playback state (cursor, rate, voice, play/pause)
    │
    ▼
SynthScheduler          → look-ahead buffer of 3 paragraphs
    │           ▲
    ▼           │ PCMChunk (float32 @ 44.1 kHz)
SupertonicSynthesizer   → ONNX Runtime inference (Supertonic 3, 4 steps default)
    │
    ▼
PlayerService           → AVAudioEngine + AVAudioPlayerNode + AVAudioUnitTimePitch
    │
    ▼
  speaker + Lock Screen Now Playing
```

### Key types

| Type | File | Role |
|---|---|---|
| `SavedDocument` | `Models.swift` | Persisted document: text + cursor, no audio |
| `PlaybackCursor` | `Models.swift` | Chapter + paragraph index |
| `ReaderSession` | `ReaderSession.swift` | ObservableObject wiring UI to scheduler |
| `SupertonicSynthesizer` | `TTS/SupertonicSynthesizer.swift` | `Synthesizer` protocol impl; yields `PCMChunk` via `AsyncThrowingStream` |
| `SynthScheduler` | `TTS/SynthScheduler.swift` | Consumes the stream; schedules `AVAudioPCMBuffer` onto the player node |
| `PlayerService` | `PlayerService.swift` | Owns `AVAudioEngine`; exposes `schedule/play/pause/stop/setRate` |

### Persistence

Only text is persisted — never audio:

- `Documents/library/[uuid].json` — `SavedDocument` (title, author, cover thumbnail, chapters as plain strings, cursor)
- `Documents/Models/supertonic/` — ONNX model files (downloaded once)

Audio bytes (PCM, WAV, M4A) are never written to disk. Closing the app discards all in-flight audio; reopening re-synthesizes from the saved cursor.

## Audio pipeline details

| Stage | Detail |
|---|---|
| Synthesis | Supertonic 3, 4 inference steps (balanced), 44.1 kHz mono float32 |
| Silence | 50 ms between sentence sub-chunks; 75 ms appended after each paragraph buffer |
| Normalization | Per-buffer peak normalize to −1.4 dBFS via `vDSP_maxmgv` / `vDSP_vsmul` |
| Speed control | `AVAudioUnitTimePitch` (pitch-preserving); applied at playback layer — no re-synthesis |
| Audio session | `.playback` category, `.spokenAudio` mode, `.longFormAudio` routing policy |
| Interruptions | Pause on interruption begin; resume on `.shouldResume` |

## Source layout

```
Sources/
  App/
    AppState.swift              Root observable, composes all services
    BooksAppV2.swift            SwiftUI App entry point
    ReaderSession.swift         Playback coordinator (ObservableObject)
  Models/
    Models.swift                SavedDocument, ChapterText, PlaybackCursor, LibraryEntry
  Services/
    LibraryPaths.swift          Documents/library/ path helpers
    LibraryService.swift        CRUD for SavedDocument JSON files
    PlayerService.swift         AVAudioEngine pipeline + NowPlaying + remote commands
    ZipExtractor.swift          Central Directory ZIP extractor (robust support for streaming & data descriptors)
    Keychain.swift / ServerConfig.swift
    TTS/
      AppleVoiceScheduler.swift Speech synthesis scheduler for Apple's built-in AVSpeechSynthesizer
      EpubTextParser.swift      EPUB → [ChapterText] (XHTML spine → plain text)
      SupertonicHelper.swift    ONNX Runtime wrappers (TextToSpeech, UnicodeProcessor, etc.)
      SupertonicSynthesizer.swift  Synthesizer protocol; model download + ONNX inference
      SynthScheduler.swift      Look-ahead buffer scheduling, cursor advancement
      TTSEngine.swift           Enum representing the selected speech engine
      TTSVoice.swift            10 voice definitions (M1–M5, F1–F5)
      XMLIndexer.swift          Lightweight XML parser for EPUB metadata
  Views/
    ContentView.swift           Root container view with bottom tab bar navigation and import alerts
    Library/
      ImportView.swift          UI for choosing synthesis quality settings & initiating EPUB imports
      LibraryView.swift         The shelf grid/list view with stats and appearance/engine pickers
      VoicesView.swift          Voice tester and selection settings panel
    Player/AudioPlayerView.swift
    Player/MiniPlayerView.swift
    Components/CoverImageView.swift
    Components/MiniPlayerView.swift
    TTS/ModelDownloadView.swift
```

## Voices

| ID | Name | Gender |
|---|---|---|
| M1 | Marcus | Male |
| M2 | Nathan | Male |
| M3 | Oliver | Male |
| M4 | Paul | Male |
| M5 | Ryan | Male |
| F1 | Alice | Female |
| F2 | Beth | Female |
| F3 | Claire | Female |
| F4 | Diana | Female |
| F5 | Eve | Female |

Voice style files are downloaded from [Supertone/supertonic-3 on HuggingFace](https://huggingface.co/Supertone/supertonic-3) as part of the one-time model download.

## Supported languages

English, Korean, Japanese, Arabic, Bulgarian, Czech, Danish, German, Greek, Spanish, Estonian, Finnish, French, Hindi, Croatian, Hungarian, Indonesian, Italian, Lithuanian, Latvian, Dutch, Polish, Portuguese, Romanian, Russian, Slovak, Slovenian, Swedish, Turkish, Ukrainian, Vietnamese.

## Dependencies

| Package | Version | Purpose |
|---|---|---|
| [onnxruntime-swift-package-manager](https://github.com/microsoft/onnxruntime-swift-package-manager) | ≥ 1.16.0 | On-device ONNX inference for Supertonic 3 |

## Future / out of scope

- Word-level karaoke highlighting (requires per-token timing from TTS engine)
- PDF support
- Cloud TTS tier (the `Synthesizer` protocol is designed to accommodate a `CartesiaSynthesizer` or similar swap-in)
- Position sync across devices
- Export to audio file (intentionally not a feature — the app is ephemeral by design)
