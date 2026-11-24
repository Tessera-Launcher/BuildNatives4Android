#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/lib.sh"

check_ndk
require_tool git
require_tool cmake
mkdir -p "$WORK" "$NATIVE_DIR"

SRC="$WORK/openal"
BUILD_DIR="$WORK/openal-build"
OBOE_SRC="$WORK/oboe"
clone_if_missing https://github.com/kcat/openal-soft.git "openal-soft-$OPENAL_VERSION" "$SRC"
clone_if_missing https://github.com/google/oboe.git "$OBOE_VERSION" "$OBOE_SRC"

# OpenAL sets CMAKE_CXX_VISIBILITY_PRESET=hidden globally. Oboe as a shared
# subproject then exports no symbols, so force Oboe to build as a static
# archive. OpenAL links it into libopenal.so; no extra liboboe.so is needed.
python3 - "$OBOE_SRC/CMakeLists.txt" <<'PY2'
import pathlib, sys
p = pathlib.Path(sys.argv[1])
s = p.read_text()
old = 'add_library(oboe ${oboe_sources})'
new = 'add_library(oboe STATIC ${oboe_sources})'
if old in s:
    p.write_text(s.replace(old, new, 1))
PY2

rm -rf "$BUILD_DIR"
cmake -S "$SRC" -B "$BUILD_DIR" -G "Unix Makefiles" \
    -DCMAKE_TOOLCHAIN_FILE="$NDK/build/cmake/android.toolchain.cmake" \
    -DANDROID_ABI="$ABI" -DANDROID_PLATFORM="android-$API" \
    -DCMAKE_BUILD_TYPE=Release \
    -DBUILD_SHARED_LIBS=ON \
    -DALSOFT_EXAMPLES=OFF -DALSOFT_UTILS=OFF \
    -DALSOFT_TESTS=OFF -DALSOFT_INSTALL=OFF \
    -DALSOFT_BACKEND_OBOE=ON \
    -DOBOE_SOURCE="$OBOE_SRC" -DALSOFT_REQUIRE_OBOE=ON \
    -DALSOFT_BACKEND_OPENSL=ON -DALSOFT_REQUIRE_OPENSL=ON \
    -DCMAKE_C_FLAGS="-fgnu89-inline" \
    -DCMAKE_SHARED_LINKER_FLAGS="-Wl,-z,max-page-size=16384 -Wl,-z,noexecstack"
cmake --build "$BUILD_DIR" -j"$JOBS"

OUT="$NATIVE_DIR/libopenal.so"
cp "$BUILD_DIR/libopenal.so" "$OUT"
strip_native "$OUT"
"$NM" -D "$OUT" | grep ' T alcOpenDevice' >/dev/null || { echo "OpenAL output invalid" >&2; exit 1; }
strings "$OUT" | grep -x oboe >/dev/null || { echo 'Oboe backend missing' >&2; exit 1; }
strings "$OUT" | grep -x opensl >/dev/null || { echo 'OpenSL backend missing' >&2; exit 1; }
echo "built $OUT (Oboe + OpenSL backends; Oboe statically linked)"
