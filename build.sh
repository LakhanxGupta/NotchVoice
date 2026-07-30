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

# EXPERIMENT (qwen3-asr-experiment branch): MLX loads its shader library from
# beside the executable, and SwiftPM does not build it — see
# .build/checkouts/speech-swift/scripts/build_mlx_metallib.sh. Without it, MLX
# calls abort() the moment a Qwen engine is selected, killing the whole app.
# Bundle it when present; the Qwen menu items hide themselves when it isn't.
METALLIB="$(swift build -c release --show-bin-path)/mlx.metallib"
if [[ -f "$METALLIB" ]]; then
    echo "==> Bundling mlx.metallib (Qwen3-ASR engines enabled)…"
    cp "$METALLIB" "$APP/Contents/MacOS/mlx.metallib"
else
    echo "==> No mlx.metallib — Qwen3-ASR engines will be hidden."
    echo "    To enable (needs full Xcode, not just Command Line Tools):"
    echo "      sudo xcode-select -s /Applications/Xcode.app/Contents/Developer"
    echo "      xcodebuild -downloadComponent MetalToolchain"
    echo "      BUILD_DIR=\"$ROOT/.build\" bash .build/checkouts/speech-swift/scripts/build_mlx_metallib.sh release"
fi

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
