#!/usr/bin/env bash
#
# build.sh — headless, signing-free compile/link check of the app.
#
# Builds the BooksAppV2 scheme for the iOS Simulator with code signing disabled.
# Fast and secret-free — ideal for CI / agents to verify a change compiles.
#
# Note: entitlements that need a team-prefixed identity (App Groups, CarPlay)
# are NOT exercised in an unsigned build — that's expected. This verifies that
# the code compiles and links, not entitlement behavior.
set -euo pipefail
cd "$(dirname "$0")/.."

"$(dirname "$0")/generate.sh"

xcodebuild \
  -project BooksAppV2.xcodeproj \
  -scheme BooksAppV2 \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO \
  build
