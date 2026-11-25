#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
APP_OUT="/Applications/G3 Companion.app"
CONTENTS="$APP_OUT/Contents"
MACOS="$CONTENTS/MacOS"
RES="$CONTENTS/Resources"

rm -rf "$APP_OUT"
mkdir -p "$MACOS" "$RES"

swiftc -O -target x86_64-apple-macosx15.0 \
  "$ROOT/Sources/G3Protocol.swift" \
  "$ROOT/Sources/G3ViewModel.swift" \
  "$ROOT/Sources/WidgetView.swift" \
  "$ROOT/Sources/SettingsView.swift" \
  "$ROOT/Sources/AppMain.swift" \
  -o "$MACOS/G3Companion" \
  -framework Cocoa \
  -framework SwiftUI \
  -framework IOKit

cp "$ROOT/Info.plist" "$CONTENTS/Info.plist"
cp "$ROOT/AppIcon.icns" "$RES/AppIcon.icns"

codesign --force --deep --sign - "$APP_OUT"
touch "$APP_OUT"

echo "Built: $APP_OUT (clean standalone app with AppIcon)"
