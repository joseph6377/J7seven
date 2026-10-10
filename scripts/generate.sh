#!/usr/bin/env bash
#
# generate.sh — regenerate BooksAppV2.xcodeproj from project.yml via XcodeGen.
#
# The .xcodeproj is a generated artifact. Never edit it by hand; edit project.yml
# and run this script (build.sh / test.sh call it automatically).
#
# Requires: xcodegen (brew install xcodegen)
set -euo pipefail
cd "$(dirname "$0")/.."

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "error: xcodegen not found. Install it with: brew install xcodegen" >&2
  exit 1
fi

xcodegen generate
