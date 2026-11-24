#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/lib.sh"

require_tool curl
require_tool unzip
JNA_VERSION="${JNA_VERSION:-5.17.0}"
OUT="$NATIVE_DIR/jna/$JNA_VERSION"
mkdir -p "$OUT"
AAR="$WORK/jna-$JNA_VERSION.aar"
if [ ! -f "$AAR" ]; then
    curl -fsSL --retry 3 -o "$AAR" \
        "https://repo1.maven.org/maven2/net/java/dev/jna/jna/$JNA_VERSION/jna-$JNA_VERSION.aar"
fi
unzip -p "$AAR" jni/arm64-v8a/libjnidispatch.so > "$OUT/libjnidispatch.so"
strip_native "$OUT/libjnidispatch.so"
echo "built $OUT/libjnidispatch.so"
