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

# Prefer the stable self-signed identity (from setup-signing.sh) so granted
# permissions — especially Accessibility for auto-paste — survive rebuilds.
# Fall back to ad-hoc if it hasn't been set up yet.
IDENTITY="NotchVoice Self-Signed"
if security find-identity -v -p codesigning | grep -q "$IDENTITY"; then
    echo "==> Code signing with stable identity '$IDENTITY'…"
    codesign --force --deep --sign "$IDENTITY" "$APP"
else
    echo "==> Ad-hoc code signing…"
    echo "    (!) Run 'bash setup-signing.sh' once so Accessibility permission"
    echo "        stops resetting on every rebuild."
    codesign --force --deep --sign - "$APP"
fi

echo ""
echo "Done ->  $APP"
echo "Launch with:  open \"$APP\""
