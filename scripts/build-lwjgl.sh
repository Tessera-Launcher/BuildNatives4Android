#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/lib.sh"

check_ndk
require_tool git
require_tool curl
mkdir -p "$WORK" "$NATIVE_DIR"

LWJGL_DIR="$WORK/lwjgl3"
LIBFFI_SRC="$WORK/libffi"
LIBFFI_BUILD="$WORK/libffi-build"
LIBFFI_A="$LIBFFI_BUILD/.libs/libffi.a"

clone_if_missing https://github.com/LWJGL/lwjgl3.git "$LWJGL_VERSION" "$LWJGL_DIR"

if [ ! -f "$LIBFFI_SRC/configure" ]; then
    echo "fetch libffi 3.8.0"
    rm -rf "$LIBFFI_SRC" "$LIBFFI_BUILD"
    curl -fsSL --retry 3 -o "$WORK/libffi-3.8.0.tar.gz" \
        https://github.com/libffi/libffi/releases/download/v3.8.0/libffi-3.8.0.tar.gz
    tar -xzf "$WORK/libffi-3.8.0.tar.gz" -C "$WORK"
    mv "$WORK/libffi-3.8.0" "$LIBFFI_SRC"
fi

if [ ! -f "$LIBFFI_A" ]; then
    rm -rf "$LIBFFI_BUILD"
    mkdir -p "$LIBFFI_BUILD"
    (
        cd "$LIBFFI_BUILD"
        "$LIBFFI_SRC/configure" \
            --host=aarch64-linux-android \
            --disable-shared --enable-static --disable-docs \
            --disable-multi-os-directory \
            CC="$CC" CCAS="$CC" CFLAGS="-O2 -fPIC"
        make -j"$JOBS"
    )
fi

M="$LWJGL_DIR/modules/lwjgl"
OUT="$NATIVE_DIR"
mkdir -p "$OUT"

compile_c_lib() {
    local name="$1" out="$2" extra_incs="$3" extra_libs="$4"
    local obj="$WORK/obj/$name"
    shift 4
    local srcs=("$@")
    rm -rf "$obj"
    mkdir -p "$obj"
    (
        cd "$obj"
        "$CC" -c -std=gnu11 "${lwjgl_cflags[@]}" $extra_incs "${srcs[@]}"
        "$CC" "${lwjgl_ldflags[@]}" -o "$out" ./*.o $extra_libs
    )
    strip_native "$out"
    echo "built $out"
}

compile_cxx_lib() {
    local name="$1" out="$2" extra_incs="$3" extra_libs="$4"
    local obj="$WORK/obj/$name"
    shift 4
    local srcs=("$@")
    rm -rf "$obj"
    mkdir -p "$obj"
    (
        cd "$obj"
        "$CXX" -c -std=gnu++17 "${lwjgl_cflags[@]}" $extra_incs "${srcs[@]}"
        "$CXX" "${lwjgl_ldflags[@]}" -o "$out" ./*.o $extra_libs
    )
    strip_native "$out"
    echo "built $out"
}

mapfile -t CORE_SRCS < <(
    find "$M/core/src/main/c" -maxdepth 1 -name '*.c' | sort
    find "$M/core/src/generated/c" -maxdepth 1 -name '*.c' | sort
    find "$M/core/src/generated/c/linux" -maxdepth 1 -name '*.c' | grep -v liburing | sort
)
compile_c_lib core "$OUT/liblwjgl.so" \
    "-I$M/core/src/main/c -I$M/core/src/main/c/linux -I$M/core/src/main/c/libffi -I$M/core/src/main/c/libffi/aarch64" \
    "$LIBFFI_A -llog -ldl -lm" \
    "${CORE_SRCS[@]}"

mapfile -t STB_SRCS < <(find "$M/stb/src/generated/c" -maxdepth 1 -name '*.c' | sort)
compile_c_lib stb "$OUT/liblwjgl_stb.so" \
    "-I$M/core/src/main/c -I$M/core/src/main/c/linux -I$M/stb/src/main/c" \
    "-llog -ldl -lm" \
    "${STB_SRCS[@]}"

mapfile -t OPENGL_SRCS < <(
    find "$M/opengl/src/generated/c" -maxdepth 1 -name '*.c' \
        | grep -vE '_(WGL|GLX)[A-Za-z0-9_]*\.c$|_opengl_(WGL|GLX)\.c$' \
        | sort
)
compile_c_lib opengl "$OUT/liblwjgl_opengl.so" \
    "-I$M/core/src/main/c -I$M/core/src/main/c/linux -I$M/opengl/src/main/c" \
    "-llog -ldl -lm" \
    "${OPENGL_SRCS[@]}"

mapfile -t VMA_SRCS < <(find "$M/vma/src/generated/c" -maxdepth 1 -name '*.cpp' | sort)
compile_cxx_lib vma "$OUT/liblwjgl_vma.so" \
    "-I$M/core/src/main/c -I$M/core/src/main/c/linux -I$M/vma/src/main/c -I$M/vulkan/src/main/c" \
    "-llog -ldl -lm" \
    "${VMA_SRCS[@]}"

echo
echo "LWJGL $LWJGL_VERSION native output:"
ls -lh "$OUT"/liblwjgl*.so
