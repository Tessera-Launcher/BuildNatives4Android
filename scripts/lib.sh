#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="$ROOT/work"
BUILD="$ROOT/build"
DIST="$ROOT/dist"
NDK="${ANDROID_NDK_HOME:-${ANDROID_NDK_ROOT:-$HOME/android-ndk-r30}}"
API="${ANDROID_API:-26}"
ABI=arm64-v8a
HOST_TAG=linux-x86_64
TOOLCHAIN="$NDK/toolchains/llvm/prebuilt/$HOST_TAG"
CC="$TOOLCHAIN/bin/aarch64-linux-android${API}-clang"
CXX="$TOOLCHAIN/bin/aarch64-linux-android${API}-clang++"
STRIP="$TOOLCHAIN/bin/llvm-strip"
NM="$TOOLCHAIN/bin/llvm-nm"
READELF="$TOOLCHAIN/bin/llvm-readelf"
JOBS="${JOBS:-$(nproc)}"
JAVA_HOME="${JAVA_HOME:-$HOME/.sdkman/candidates/java/current}"
JNI_INCLUDE="$JAVA_HOME/include"
JNI_PLATFORM_INCLUDE="$JAVA_HOME/include/linux"
NATIVE_DIR="$BUILD/natives"
LWJGL_VERSION=3.4.3
SDL_VERSION=release-3.4.16
SPIRV_CROSS_VERSION=vulkan-sdk-1.4.363.0
SHADERC_VERSION=v2026.4
FREETYPE_VERSION=VER-2-14-3
OPENAL_VERSION=1.25.2
OBOE_VERSION=1.11.2
JNA_VERSION=5.17.0
JEMALLOC_VERSION=5.4.0

export SDL_VERSION SHADERC_VERSION SPIRV_CROSS_VERSION FREETYPE_VERSION OPENAL_VERSION OBOE_VERSION JNA_VERSION JEMALLOC_VERSION
export LC_ALL=C

require_tool() {
    command -v "$1" >/dev/null || { echo "missing tool: $1" >&2; exit 1; }
}

check_ndk() {
    [ -x "$CC" ] || { echo "Android NDK clang not found: $CC" >&2; exit 1; }
    [ -f "$JNI_INCLUDE/jni.h" ] || { echo "JNI headers not found under $JAVA_HOME" >&2; exit 1; }
}

clone_if_missing() {
    local url="$1" ref="$2" dir="$3"
    if [ -d "$dir/.git" ]; then
        echo "source cached: $dir"
        return
    fi
    mkdir -p "$(dirname "$dir")"
    echo "clone $url @ $ref"
    git clone --depth 1 --branch "$ref" "$url" "$dir"
}

lwjgl_cflags=(
    -O2 -fPIC -DNDEBUG
    -DLWJGL_LINUX -DLWJGL_arm64
    -D_GNU_SOURCE -D_FILE_OFFSET_BITS=64
    -Wno-everything
    -I"$JNI_INCLUDE" -I"$JNI_PLATFORM_INCLUDE"
)

lwjgl_ldflags=(
    -shared
    -Wl,-z,max-page-size=16384
    -Wl,-z,noexecstack
    -Wl,-z,relro
    -Wl,-z,now
    -Wl,--no-undefined
)

strip_native() {
    "$STRIP" --strip-unneeded "$1"
    "$READELF" -lW "$1" | awk '$1=="LOAD"{print $NF}' | sort -u | grep -x 0x4000 >/dev/null \
        || { echo "16KB LOAD alignment check failed: $1" >&2; exit 1; }
}
