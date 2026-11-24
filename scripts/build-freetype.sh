#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/lib.sh"

check_ndk
require_tool git
require_tool cmake
mkdir -p "$WORK" "$NATIVE_DIR"

SRC="$WORK/freetype"
BUILD_DIR="$WORK/freetype-build"
clone_if_missing https://github.com/freetype/freetype.git "$FREETYPE_VERSION" "$SRC"

rm -rf "$BUILD_DIR"
cmake -S "$SRC" -B "$BUILD_DIR" -G "Unix Makefiles" \
    -DCMAKE_TOOLCHAIN_FILE="$NDK/build/cmake/android.toolchain.cmake" \
    -DANDROID_ABI="$ABI" -DANDROID_PLATFORM="android-$API" \
    -DCMAKE_BUILD_TYPE=Release \
    -DBUILD_SHARED_LIBS=ON \
    -DFT_DISABLE_ZLIB=TRUE -DFT_DISABLE_BZIP2=TRUE \
    -DFT_DISABLE_PNG=TRUE -DFT_DISABLE_HARFBUZZ=TRUE \
    -DFT_DISABLE_BROTLI=TRUE \
    -DCMAKE_SHARED_LINKER_FLAGS="-Wl,-z,max-page-size=16384 -Wl,-z,noexecstack"
cmake --build "$BUILD_DIR" -j"$JOBS"

OUT="$NATIVE_DIR/libfreetype.so"
cp "$BUILD_DIR/libfreetype.so" "$OUT"
strip_native "$OUT"
"$NM" -D "$OUT" | grep ' T FT_Init_FreeType' >/dev/null || { echo "FreeType output invalid" >&2; exit 1; }
echo "built $OUT"
