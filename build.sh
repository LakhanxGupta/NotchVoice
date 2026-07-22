#!/bin/bash
# Builds NotchVoice and assembles a signed .app bundle at build/NotchVoice.app
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
APP="$ROOT/build/NotchVoice.app"
NAME="NotchVoice"

echo "==> Compiling (release)…"
swift build -c release

BIN="$(swift build -c release --show-bin-path)/$NAME"
if [[ ! -f "$BIN" ]]; then
    echo "Build failed: binary not found at $BIN" >&2
    exit 1
fi

echo "==> Assembling app bundle…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
mkdir -p "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/$NAME"
cp "$ROOT/Info.plist" "$APP/Contents/Info.plist"

echo "==> Ad-hoc code signing (so macOS remembers granted permissions)…"
codesign --force --deep --sign - "$APP"

echo ""
echo "Done ->  $APP"
echo "Launch with:  open \"$APP\""
