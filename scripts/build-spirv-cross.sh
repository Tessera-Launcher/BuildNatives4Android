#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/lib.sh"

check_ndk
require_tool git
require_tool cmake
mkdir -p "$WORK" "$NATIVE_DIR"

SRC="$WORK/SPIRV-Cross"
BUILD_DIR="$WORK/SPIRV-Cross-build"
clone_if_missing https://github.com/KhronosGroup/SPIRV-Cross.git "$SPIRV_CROSS_VERSION" "$SRC"

rm -rf "$BUILD_DIR"
cmake -S "$SRC" -B "$BUILD_DIR" -G "Unix Makefiles" \
    -DCMAKE_TOOLCHAIN_FILE="$NDK/build/cmake/android.toolchain.cmake" \
    -DANDROID_ABI="$ABI" -DANDROID_PLATFORM="android-$API" \
    -DCMAKE_BUILD_TYPE=Release \
    -DSPIRV_CROSS_SHARED=ON -DSPIRV_CROSS_STATIC=OFF \
    -DSPIRV_CROSS_CLI=OFF -DSPIRV_CROSS_ENABLE_TESTS=OFF \
    -DBUILD_SHARED_LIBS=OFF \
    -DCMAKE_SHARED_LINKER_FLAGS="-Wl,-z,max-page-size=16384 -Wl,-z,noexecstack"
cmake --build "$BUILD_DIR" --target spirv-cross-c-shared -j"$JOBS"

BUILT="$(find "$BUILD_DIR" -maxdepth 1 -name 'libspirv-cross-c-shared.so' -print -quit)"
[ -n "$BUILT" ] || { echo "SPIRV-Cross output not found" >&2; exit 1; }
OUT="$NATIVE_DIR/libspirv-cross.so"
cp "$BUILT" "$OUT"
strip_native "$OUT"
"$NM" -D "$OUT" | grep ' T spvc_context_create' >/dev/null || { echo "missing spvc C API" >&2; exit 1; }
echo "built $OUT"
