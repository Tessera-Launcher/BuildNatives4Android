#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/lib.sh"

check_ndk
require_tool git
require_tool cmake
mkdir -p "$WORK" "$NATIVE_DIR"

SRC="$WORK/SDL"
BUILD_DIR="$WORK/SDL-build"
clone_if_missing https://github.com/libsdl-org/SDL.git "$SDL_VERSION" "$SRC"
python3 "$ROOT/scripts/patch-sdl-android.py" "$SRC"

rm -rf "$BUILD_DIR"
cmake -S "$SRC" -B "$BUILD_DIR" -G "Unix Makefiles" \
    -DCMAKE_TOOLCHAIN_FILE="$NDK/build/cmake/android.toolchain.cmake" \
    -DANDROID_ABI="$ABI" -DANDROID_PLATFORM="android-$API" \
    -DCMAKE_BUILD_TYPE=Release \
    -DSDL_TESTS=OFF -DSDL_EXAMPLES=OFF \
    -DSDL_SHARED=ON -DSDL_STATIC=OFF \
    -DCMAKE_SHARED_LINKER_FLAGS="-Wl,-z,max-page-size=16384 -Wl,-z,noexecstack"
cmake --build "$BUILD_DIR" --target SDL3-shared -j"$JOBS"

OUT="$NATIVE_DIR/libSDL3.so"
cp "$BUILD_DIR/libSDL3.so" "$OUT"
strip_native "$OUT"
echo "built $OUT"
