#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
./scripts/build-lwjgl.sh
./scripts/build-java.sh
./scripts/build-sdl3.sh
./scripts/build-shaderc.sh
./scripts/build-spirv-cross.sh
./scripts/build-freetype.sh
./scripts/build-jemalloc.sh
./scripts/build-openal.sh
./scripts/fetch-jna.sh
./scripts/package.sh
