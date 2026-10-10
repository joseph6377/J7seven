# CLAUDE.md — LysnBox (BooksAppV2)

Guidance for agents and CI working in this repo. LysnBox is an **iOS-only** (iOS 17+)
EPUB audiobook reader. The Xcode project is generated from `project.yml` via **XcodeGen**.

## Golden rule: never hand-edit the Xcode project

`BooksAppV2.xcodeproj` is a generated artifact. To change targets, build settings,
Info.plist keys, entitlements, dependencies, or schemes, edit **`project.yml`** and
regenerate. Do not edit `project.pbxproj` directly.

## Headless build & test (no Xcode GUI)

```bash
./scripts/generate.sh   # regenerate .xcodeproj after any project.yml change
./scripts/build.sh      # unsigned Simulator build — fast compile/link check
./scripts/test.sh       # run unit + UI tests on the iOS Simulator
```

- **`build.sh`** builds the `BooksAppV2` scheme for `generic/platform=iOS Simulator`
  with `CODE_SIGNING_ALLOWED=NO`. Secret-free and the quickest way to confirm a change
  compiles. Entitlement-gated features (App Groups, CarPlay) are not exercised in an
  unsigned build — that's expected.
- **`test.sh`** runs on a named simulator (default `iPhone 17`; override with
  `SIMULATOR="iPhone 17 Pro"`). Use `ONLY_UNIT=1 ./scripts/test.sh` to skip the slower
  UI tests. Results land in `build/TestResults.xcresult`.
- The **first** build/test run is slow: SwiftPM resolves dependencies and the local
  `onnxruntime` package (~400 MB) builds.

## Out of scope (not set up here)

Code signing, archiving, and uploading to TestFlight / App Store are intentionally not
scripted yet. When added, follow the App-Store-Connect-API-key path (a `.p8` key kept
outside the repo), not app-specific passwords. Notarization / `stapler` / `spctl` are
macOS-app concepts and never apply to this iOS app.

## Project facts

- Scheme: `BooksAppV2` (app + `J7ShareExtension`; tests `BooksAppV2Tests`, `BooksAppV2UITests`).
- Bundle id: `in.josepht.booksappv2`. App Group: `group.in.josepht.booksappv2`.
- Dependencies (resolved at generate time): local `onnxruntime` package (`Packages/`),
  SwiftSoup, SwiftReadability.
