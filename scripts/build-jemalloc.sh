#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/lib.sh"

require_tool curl
require_tool make
mkdir -p "$WORK" "$NATIVE_DIR"

SRC="$WORK/jemalloc"
BUILD="$WORK/jemalloc-build"
TARBALL="$WORK/jemalloc-${JEMALLOC_VERSION}.tar.bz2"

if [ ! -f "$SRC/VERSION" ]; then
    rm -rf "$SRC"
    echo "download jemalloc $JEMALLOC_VERSION"
    curl -fsSL --retry 3 \
        "https://github.com/jemalloc/jemalloc/releases/download/${JEMALLOC_VERSION}/jemalloc-${JEMALLOC_VERSION}.tar.bz2" \
        -o "$TARBALL"
    tar -xjf "$TARBALL" -C "$WORK"
    mv "$WORK/jemalloc-${JEMALLOC_VERSION}" "$SRC"
fi

# 5.3.0 does not export je_free_sized, which LWJGL's jemalloc binding needs.
# 5.4.0 has it; keep the prefix so liblwjgl can bind to je_* symbols.
rm -rf "$BUILD"
mkdir -p "$BUILD"
cd "$BUILD"
"$SRC/configure" \
    --host=aarch64-linux-android \
    --prefix="$BUILD/out" \
    --with-jemalloc-prefix=je_ \
    --enable-shared \
    --disable-static \
    CC="$CC" \
    CXX="$CXX" \
    CFLAGS="-O2 -fPIC" \
    CXXFLAGS="-O2 -fPIC"
make -j"$JOBS"
make install

cp "$BUILD/out/lib/libjemalloc.so" "$NATIVE_DIR/libjemalloc.so"
strip_native "$NATIVE_DIR/libjemalloc.so"

"$NM" -D --defined-only "$NATIVE_DIR/libjemalloc.so" \
    | grep -q ' T je_free_sized$' \
    || { echo "libjemalloc.so is missing je_free_sized" >&2; exit 1; }
"$NM" -D --defined-only "$NATIVE_DIR/libjemalloc.so" \
    | grep -q ' T je_malloc$' \
    || { echo "libjemalloc.so is missing je_malloc" >&2; exit 1; }

echo "jemalloc $JEMALLOC_VERSION: $NATIVE_DIR/libjemalloc.so"
