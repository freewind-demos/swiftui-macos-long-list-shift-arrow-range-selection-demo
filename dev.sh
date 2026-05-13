#!/usr/bin/env bash
set -euo pipefail

export DEVELOPER_DIR=/System/Volumes/Data/Applications/Xcode.app/Contents/Developer

PROJECT="SwiftUILongListShiftArrowRangeSelectionDemo.xcodeproj"
SCHEME="SwiftUILongListShiftArrowRangeSelectionDemo"
DERIVED_DATA_PATH=".build"
APP_PATH="$PWD/$DERIVED_DATA_PATH/Build/Products/Debug/$SCHEME.app"

xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration Debug \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  build

pkill -x "$SCHEME" >/dev/null 2>&1 || true

open "$APP_PATH"
