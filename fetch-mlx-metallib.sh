#!/bin/bash
# EXPERIMENT (qwen3-asr-experiment branch): fetch mlx.metallib without Xcode.
#
# MLX ships its GPU kernels as ~33 .metal source files that must be compiled
# into mlx.metallib before anything can run on the GPU. That compile needs
# Apple's `metal` compiler, which produces AIR (an undocumented intermediate
# format only Apple's GPU drivers accept) and ships ONLY with full Xcode —
# Command Line Tools do not include it. SwiftPM has no rule for Metal either,
# so `swift build` never produces it.
#
# Apple's MLX team already runs that compiler on these exact sources and
# publishes the finished binary inside the `mlx-metal` wheel on PyPI (Python
# users can't be asked to install Xcode either). So instead of installing the
# compiler, we download its output.
#
# No Python runs at runtime — pip is only a download mechanism, and the app
# stays a pure Swift binary.
#
# The version is pinned to the MLX core bundled in the mlx-swift checkout
# (see .build/checkouts/mlx-swift/Source/Cmlx/mlx/mlx/version.h). A mismatch
# means the metallib was built from different shader sources than the C++
# expects, which surfaces as another abort or as garbage output.
set -euo pipefail

MLX_VERSION="0.31.1"
ROOT="$(cd "$(dirname "$0")" && pwd)"
DEST="$ROOT/Vendor/mlx.metallib"

if [[ -f "$DEST" ]]; then
    echo "==> Already present: $DEST"
    echo "    Delete it to re-fetch."
    exit 0
fi

# Cross-check the pin against the checked-out MLX core, if it's been fetched.
VERSION_H="$ROOT/.build/checkouts/mlx-swift/Source/Cmlx/mlx/mlx/version.h"
if [[ -f "$VERSION_H" ]]; then
    CORE="$(awk '/MLX_VERSION_MAJOR/{a=$3} /MLX_VERSION_MINOR/{b=$3} /MLX_VERSION_PATCH/{c=$3} END{print a"."b"."c}' "$VERSION_H")"
    if [[ "$CORE" != "$MLX_VERSION" ]]; then
        echo "(!) mlx-swift bundles MLX core $CORE but this script pins $MLX_VERSION." >&2
        echo "    Update MLX_VERSION to $CORE — a mismatched metallib aborts or" >&2
        echo "    produces garbage." >&2
        exit 1
    fi
fi

command -v pip3 >/dev/null || { echo "pip3 not found." >&2; exit 1; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "==> Downloading mlx-metal==$MLX_VERSION from PyPI (~50 MB)…"
# --no-deps: we want one file, not an install. Nothing is installed anywhere.
pip3 download --no-deps --only-binary=:all: "mlx-metal==$MLX_VERSION" -d "$TMP"

WHEEL="$(find "$TMP" -name 'mlx_metal-*.whl' -maxdepth 1 | head -1)"
[[ -n "$WHEEL" ]] || { echo "No wheel downloaded." >&2; exit 1; }

echo "==> Extracting mlx.metallib…"
mkdir -p "$ROOT/Vendor"
unzip -o -j "$WHEEL" "mlx/lib/mlx.metallib" -d "$ROOT/Vendor"

file "$DEST" | grep -q "MetalLib" || { echo "Extracted file is not a metallib." >&2; exit 1; }

echo ""
echo "Done ->  $DEST"
echo "Now run:  bash build.sh    (it bundles this into the .app)"
