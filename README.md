# LysnBox — EPUB Audiobook Reader

An iOS app that reads EPUB books aloud using fully on-device AI text-to-speech. No cloud calls, no per-minute cost, no audio stored to disk. Import an EPUB, tap play, and the app synthesizes speech in real time as you listen.

---

## Features

- **Ephemeral Streaming TTS** — Audio is generated and played live; nothing is ever written to disk. Closing the app discards all in-flight buffers, keeping your local storage completely footprint-free.
- **On-Device Synthesis** — Powered by [Supertonic 3](https://github.com/supertone-inc/supertonic) (ONNX Runtime, ~400 MB one-time cache download).
- **80 Curated Voices** — 10 gender-balanced style profiles localized across 8 supported languages using popular, culturally-appropriate names.
- **8 Languages** — Native, fully-localized support for English, Spanish, French, German, Italian, Portuguese, Japanese, and Korean.
- **App Store & iCloud Compliant** — Voice models reside in the standard `Library/Caches/` sandbox directory rather than `Documents/` to satisfy Apple's App Store Review guidelines regarding backup sizes. Includes an automatic, self-healing model migration and automatic cleanup of legacy directories.
- **Privacy Manifest Compliant** — Ships with an official `PrivacyInfo.xcprivacy` manifest defining required usage declarations for system APIs (`UserDefaults`, `FileTimestamp`, and `DiskSpace`).
- **Cooperative Thread Safe** — CPU-intensive ONNX model loading and synchronous synthesis (`tts.call`) are systematically offloaded to user-initiated Grand Central Dispatch (GCD) background queues rather than the cooperative Swift Concurrency thread pool, resolving `unsafeForcedSync` runtime warnings and avoiding thread starvation.
- **Universal EPUB Handler ("Open In" Support)** — Registered system-wide as an EPUB document viewer. Tap or share an `.epub` file from external applications (Files, Safari, Mail, Slack) to instantly launch LysnBox and import the book.
- **Strategy A Pre-bundled Asset Support** — Detects and registers pre-packaged voice models within the App Bundle to bypass downloading and enable instant offline play out of the box.
- **Editorial UI/UX Player Overhaul** — Features an immersive serif reading canvas with automatic control auto-hiding, glowing paragraph active-sentence highlights, precise word-level highlight focus boxes, segments for speed/inference quality, and a collapsible/expandable transport card.
- **Paragraph-Level Cursor Tracking** — Current chapter and paragraph focus are persisted locally in real time so you can resume exactly where you left off.
- **Playback Speed Control** — Utilizes `AVAudioUnitTimePitch` for pitch-preserving speed modification (0.8× to 2.0×) in the playback engine, requiring no expensive voice re-synthesis.
- **Background Audio & Remote Controls** — Continues rendering and playing with the screen off; fully integrated with System Lock Screen controls and Now Playing info.
- **Bluetooth Optimization** — Configures `AVAudioSession` with `.spokenAudio` mode and `.longFormAudio` policy to leverage high-quality AAC compression over wireless AirPods and Bluetooth accessories.

---

## Requirements

- **iOS 17.0+**
- **Xcode 16+**
- **[XcodeGen](https://github.com/yonaskolb/XcodeGen)** (to generate and synchronize the `.xcodeproj` configuration from `project.yml`)

---

## Getting Started

```bash
# 1. Clone the repository
git clone <repo-url>
cd "BooksApp v2"

# 2. Generate the Xcode project and test target
xcodegen generate

# 3. Open and build in Xcode
open BooksAppV2.xcodeproj
```

*On first launch, if voice assets are not pre-bundled in the application, you will be prompted to download the Supertonic 3 model (~400 MB). This download is securely stored inside the sandbox `Library/Caches/supertonic/` folder, ensuring compliance.*

---

## Architecture

```
         EPUB / Open-In
               │
               ▼
     [ EpubTextParser ]        ──▶ chapters: [ChapterText { paragraphs: [String] }]
               │
               ▼
     [ LibraryService ]        ──▶ SavedDocument persisted to Documents/library/[uuid].json
               │
               ▼
     [ ReaderSession ]         ──▶ active playback state (cursor, rate, voice, play/pause)
               │
               ▼
     [ SynthScheduler ]        ──▶ look-ahead buffer of 3 paragraphs (Swift Concurrency)
         │          ▲
         ▼          │ PCMChunk (float32 @ 44.1 kHz)
[ SupertonicSynthesizer ]     ──▶ ONNX Runtime inference (GCD Thread offloading)
         │
         ▼
     [ PlayerService ]         ──▶ AVAudioEngine + AVAudioPlayerNode + AVAudioUnitTimePitch
         │
         ▼
 speaker + Lock Screen Now Playing
```

### Key Components

| Component | Target File | Role |
|---|---|---|
| `SavedDocument` | `Models.swift` | Persisted document container containing text, chapter layouts, and current cursor position. |
| `PlaybackCursor` | `Models.swift` | Tracks precise `chapterIndex` and `paragraphIndex` pointer positions. |
| `ReaderSession` | `ReaderSession.swift` | Orchestrator object binding the UI layers with the underlying synthesizers and players. |
| `SupertonicSynthesizer` | `TTS/SupertonicSynthesizer.swift` | Implements `Synthesizer`; executes ONNX Runtime inference offloaded to background threads. |
| `SynthScheduler` | `TTS/SynthScheduler.swift` | Consumes paragraph streams, manages buffering, and feeds buffers to the playback engine. |
| `PlayerService` | `PlayerService.swift` | Owns `AVAudioEngine`, configures lock screen metadata, and plays audio chunks. |
| `ZipExtractor` | `ZipExtractor.swift` | Extracts EPUB packages without memory leaks using central directory stream processing. |

### Sandbox & Caching Layout

- `Documents/library/[uuid].json` — Persists `SavedDocument` objects (titles, authors, custom cover data, and texts). Absolutely no audio PCM files are ever written to disk.
- `Library/Caches/supertonic/` — Houses downloaded ONNX models and style style sheets. Automatically excluded from iCloud backups, adhering to App Store size constraints.

---

## Audio Pipeline Details

| Stage | Detail |
|---|---|
| **Synthesis** | Supertonic 3, configurable inference steps (Fast: 2, Balanced: 4, High: 5), 44.1 kHz mono float32 PCM. |
| **GCD Offloading** | Core synthesis and setup routines are isolated onto custom concurrent `DispatchQueue` pools to prevent blocking Swift's cooperative threads. |
| **Silence Insertion** | 50 ms between internal sentence sub-chunks; 75 ms cushion appended at the end of each paragraph buffer. |
| **Normalization** | Per-buffer peak volume normalization calibrated to −1.4 dBFS using Apple's Accelerate framework (`vDSP_maxmgv` / `vDSP_vsmul`). |
| **Speed Control** | Pitch-preserving speed modification handled inside the `AVAudioUnitTimePitch` layer (no speech re-synthesis). |
| **Interruptions** | Immediate pause on telephone or system interrupts, with intelligent `.shouldResume` auto-restart logic. |

---

## Source Layout

```
Sources/
  App/
    AppState.swift              Root observable class; coordinates sub-services.
    BooksAppV2.swift            SwiftUI main app entry point.
    Font+Theme.swift            Unified typography scale & branding font styles.
    ReaderSession.swift         Main playback session orchestrator.
  Models/
    Models.swift                Structures representing book schemas, chapters, and cursors.
  Services/
    LibraryPaths.swift          Sandbox paths and directory configuration helpers.
    LibraryService.swift        Secure JSON reading and writing for imported books.
    PlayerService.swift         Low-level audio pipeline, remote controls, and background audio.
    ZipExtractor.swift          Robust ZIP processing for EPUB containers.
    TTS/
      AppleVoiceScheduler.swift Legacy/fallback scheduling for Apple AVSpeechSynthesizer.
      EpubTextParser.swift      Translates XML/XHTML spin contents into normalized string chunks.
      SupertonicHelper.swift    Low-level Swift bindings wrapping ONNX Runtime environments.
      SupertonicSynthesizer.swift High-performance ONNX synthesizer with GCD thread isolation.
      SynthScheduler.swift      Manages ahead-of-time synthesis blocks.
      TTSEngine.swift           Selected speech synthesizer selector (Supertonic 3 vs. Apple Voice).
      TTSVoice.swift            Language mappings and voice style definitions.
      XMLIndexer.swift          XML traversal helper for container metadata files.
  Views/
    ContentView.swift           Frosted bottom-navigation tab container.
    Library/
      AboutView.swift           Compact 'About LysnBox' branding sheet containing website links.
      ImportView.swift          UI picker options for import parameters and downloading weights.
      LibraryView.swift         Beautiful Grid shelf displaying book covers, reading times, and search.
      VoicesView.swift          Interactive custom voice tester with text pre-generation.
    Player/
      AudioPlayerView.swift     Full-screen serif reader canvas, glowing active lines, and collapsed sliders.
      MiniPlayerView.swift      Collapsible synchronized bottom mini controller.
    Components/
      CoverImageView.swift      Asynchronous image loading, caching, and cover art styling.
    TTS/
      ModelDownloadView.swift   Interactive download progress overlay for voice engine models.
      WelcomeModelDownloadView.swift Onboarding screen to configure Supertonic vs. Apple native voice engine.
  PrivacyInfo.xcprivacy         App Store mandatory privacy manifest recording system API footprint.

Tests/                          Automated unit-testing suite.
  EpubTextParserTests.swift     Validates XHTML structure scrubbing and paragraph parsing.
  LibraryServiceTests.swift     Validates document storage cycles, progress tracking, and WPM timing.
  XMLIndexerTests.swift         Validates OPF/NCX index reading.
  ZipExtractorTests.swift       Validates local folder inflation and directory streaming.
```

---

## Voices & Languages

### Localized Style Profiles

The application includes 10 core style profiles (5 male, 5 female), which are fully localized and mapped to culturally-appropriate names across all 8 supported languages:

| ID | Base Name | Gender | Localized Profiles (Examples) |
|---|---|---|---|
| **M1** | Marcus | Male | Mateo (ES), Gabriel (FR), Maximilian (DE), Leonardo (IT), Miguel (PT), Hiroto (JA), Minjun (KO) |
| **M2** | Nathan | Male | Santiago (ES), Lucas (FR), Lukas (DE), Francesco (IT), Arthur (PT), Ren (JA), Seojun (KO) |
| **M3** | Oliver | Male | Alejandro (ES), Arthur (FR), Jonas (DE), Alessandro (IT), Heitor (PT), Yuto (JA), Doyun (KO) |
| **M4** | Paul | Male | Sebastián (ES), Louis (FR), Finn (DE), Lorenzo (IT), Bernardo (PT), Minato (JA), Yujun (KO) |
| **M5** | Ryan | Male | Javier (ES), Hugo (FR), Elias (DE), Mattia (IT), Davi (PT), Haruto (JA), Eunwoo (KO) |
| **F1** | Alice | Female | Valentina (ES), Emma (FR), Marie (DE), Sofia (IT), Helena (PT), Himari (JA), Seo-a (KO) |
| **F2** | Beth | Female | Sofía (ES), Chloé (FR), Sophie (DE), Aurora (IT), Alice (PT), Tsumugi (JA), Ji-an (KO) |
| **F3** | Claire | Female | Camila (ES), Manon (FR), Charlotte (DE), Giulia (IT), Laura (PT), Aoi (JA), Hayoon (KO) |
| **F4** | Diana | Female | Isabella (ES), Léa (FR), Emilia (DE), Ginevra (IT), Manuela (PT), Ichika (JA), Seoyoon (KO) |
| **F5** | Eve | Female | Valeria (ES), Inès (FR), Mia (DE), Beatrice (IT), Isabella (PT), Mei (JA), Jiwoo (KO) |

Voice assets are dynamically resolved at runtime with safety fallbacks: if a requested localized voice style file is absent, the system gracefully resolves to `M1-en` (Marcus) to ensure uninterrupted reading.

### Supported Languages
English, Spanish, French, German, Italian, Portuguese, Japanese, and Korean.

---

## Unit Testing

LysnBox is backed by an automated testing suite to verify structural pipelines.

### Running Tests from terminal:
```bash
xcodebuild test -project BooksAppV2.xcodeproj -scheme BooksAppV2 -destination "platform=iOS Simulator,name=iPhone 17"
```

The tests cover:
- **ZIP Extraction**: Validates signature reading and resilient file extraction without memory leak.
- **XML Index Parsing**: Ensures metadata fields from OPF spine schemas translate safely.
- **EPUB Paragraphing**: Checks text sanitization to remove embedded script elements or styling tags from paragraphs.
- **Document Progress Operations**: Confirms progress estimation math (e.g. 60% completion) and reading duration estimates based on Average Words Per Minute (WPM).

---

## Credits & Acknowledgements

This application is built on top of the incredible open-source work by **Supertone, Inc.** 
Special thanks to their engineering team for developing and open-sourcing [Supertonic 3](https://github.com/supertone-inc/supertonic) and publishing the model style assets on [Hugging Face](https://huggingface.co/Supertone/supertonic-3), enabling premium, fully offline, and high-performance text-to-speech synthesis directly on-device.
