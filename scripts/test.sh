#!/usr/bin/env bash
#
# test.sh — run the test suite on a booted iOS Simulator, no Xcode GUI.
#
# Usage:
#   ./scripts/test.sh                 # run all tests (unit + UI)
#   ONLY_UNIT=1 ./scripts/test.sh     # fast path: unit tests only (skips UI tests)
#   SIMULATOR="iPhone 17 Pro" ./scripts/test.sh   # override the simulator
#
# The first run is slow (SPM resolution + onnxruntime). Results are written to
# build/TestResults.xcresult for inspection.
set -euo pipefail
cd "$(dirname "$0")/.."

"$(dirname "$0")/generate.sh"

SIMULATOR="${SIMULATOR:-iPhone 17}"

ONLY_TESTING=()
if [[ "${ONLY_UNIT:-0}" == "1" ]]; then
  ONLY_TESTING=(-only-testing:BooksAppV2Tests)
fi

# xcodebuild refuses to overwrite an existing result bundle.
rm -rf build/TestResults.xcresult

xcodebuild \
  -project BooksAppV2.xcodeproj \
  -scheme BooksAppV2 \
  -destination "platform=iOS Simulator,name=${SIMULATOR}" \
  -resultBundlePath build/TestResults.xcresult \
  "${ONLY_TESTING[@]}" \
  test
