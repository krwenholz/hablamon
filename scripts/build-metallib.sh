#!/usr/bin/env bash
# Builds MLX's Metal shader library (mlx.metallib) for the voices, next to the SwiftPM build output.
# SwiftPM doesn't compile Metal shaders itself; without this the Qwen3 voices fail to load.
# Usage: scripts/build-metallib.sh [debug|release]   (run after swift build)
set -euo pipefail

cd "$(dirname "$0")/.."
config="${1:-release}"
script=.build/checkouts/speech-swift/scripts/build_mlx_metallib.sh
if ! BUILD_DIR="$PWD/.build" "$script" "$config"; then
    echo "Downloading Xcode's Metal Toolchain (one time, ~700 MB)…"
    xcodebuild -downloadComponent MetalToolchain
    BUILD_DIR="$PWD/.build" "$script" "$config"
fi
