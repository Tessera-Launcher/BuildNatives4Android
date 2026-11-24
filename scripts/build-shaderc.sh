#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/lib.sh"

check_ndk
require_tool git
require_tool cmake
require_tool python3
mkdir -p "$WORK" "$NATIVE_DIR"

SRC="$WORK/shaderc"
BUILD_DIR="$WORK/shaderc-build"
clone_if_missing https://github.com/google/shaderc.git "$SHADERC_VERSION" "$SRC"

if [ ! -d "$SRC/third_party/spirv-tools/.git" ]; then
    (cd "$SRC" && python3 utils/git-sync-deps)
fi

rm -rf "$BUILD_DIR"
cmake -S "$SRC" -B "$BUILD_DIR" -G "Unix Makefiles" \
    -DCMAKE_TOOLCHAIN_FILE="$NDK/build/cmake/android.toolchain.cmake" \
    -DANDROID_ABI="$ABI" -DANDROID_PLATFORM="android-$API" \
    -DCMAKE_BUILD_TYPE=Release \
    -DSHADERC_SKIP_TESTS=ON -DSHADERC_SKIP_EXAMPLES=ON \
    -DSHADERC_SKIP_COPYRIGHT_CHECK=ON -DSHADERC_ENABLE_WERROR_COMPILE=OFF \
    -DBUILD_SHARED_LIBS=OFF \
    -DSPIRV_SKIP_EXECUTABLES=ON -DSPIRV_SKIP_TESTS=ON \
    -DENABLE_GLSLANG_BINARIES=OFF \
    -DCMAKE_SHARED_LINKER_FLAGS="-Wl,-z,max-page-size=16384 -Wl,-z,noexecstack"
cmake --build "$BUILD_DIR" --target shaderc_shared -j"$JOBS"

OUT="$NATIVE_DIR/libshaderc.so"
cp "$BUILD_DIR/libshaderc/libshaderc_shared.so" "$OUT"
strip_native "$OUT"

for sym in \
    shaderc_compile_options_initialize \
    shaderc_compile_options_set_max_id_bound \
    shaderc_compile_into_spv \
    shaderc_compiler_initialize \
    shaderc_result_get_bytes; do
    "$NM" -D "$OUT" | grep " T $sym" >/dev/null || { echo "missing symbol: $sym" >&2; exit 1; }
done
echo "built $OUT"
