#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/lib.sh"

RUNTIME_DATE="${RUNTIME_DATE:-$(date -u +%Y%m%d)}"

export RUNTIME_DATE

require_tool python3
require_tool zip
mkdir -p "$DIST"

STAGE="$DIST/tessera-runtime-${LWJGL_VERSION}-${ABI}"
LWJGL_ROOT="$STAGE/lwjgl/$LWJGL_VERSION"
LWJGL_OUT="$LWJGL_ROOT/natives/$ABI"
JAVA_OUT="$BUILD/java/lwjgl/$LWJGL_VERSION"
JNA_OUT="$STAGE/jna/$JNA_VERSION"
NATIVE_OUT="$STAGE/native/$ABI"
LICENSE_OUT="$STAGE/licenses"
rm -rf "$STAGE"
mkdir -p "$LWJGL_OUT" "$NATIVE_OUT" "$LICENSE_OUT"

required=(
    "$JAVA_OUT/lwjgl.jar"
    "$JAVA_OUT/lwjgl-sdl.jar"
    "$JAVA_OUT/lwjgl-glfw.jar"
    "$NATIVE_DIR/liblwjgl.so"
    "$NATIVE_DIR/liblwjgl_stb.so"
    "$NATIVE_DIR/liblwjgl_opengl.so"
    "$NATIVE_DIR/liblwjgl_vma.so"
    "$NATIVE_DIR/libSDL3.so"
    "$NATIVE_DIR/libshaderc.so"
    "$NATIVE_DIR/libspirv-cross.so"
    "$NATIVE_DIR/libfreetype.so"
    "$NATIVE_DIR/libopenal.so"
    "$NATIVE_DIR/libjemalloc.so"
    "$NATIVE_DIR/libc++_shared.so"
    "$NATIVE_DIR/jna/$JNA_VERSION/libjnidispatch.so"
)
for f in "${required[@]}"; do
    [ -f "$f" ] || { echo "missing build output: $f" >&2; exit 1; }
done

cp "$JAVA_OUT"/*.jar "$LWJGL_ROOT"/
cp "$JAVA_OUT/version" "$LWJGL_ROOT/version"
cp "$NATIVE_DIR"/liblwjgl*.so "$LWJGL_OUT"/
cp "$NATIVE_DIR/libfreetype.so" "$LWJGL_OUT"/
cp "$NATIVE_DIR/libSDL3.so" "$NATIVE_OUT"/
cp "$NATIVE_DIR/libshaderc.so" "$NATIVE_OUT"/
cp "$NATIVE_DIR/libspirv-cross.so" "$NATIVE_OUT"/
cp "$NATIVE_DIR/libopenal.so" "$NATIVE_OUT"/
cp "$NATIVE_DIR/libjemalloc.so" "$NATIVE_OUT"/
cp "$NATIVE_DIR/libc++_shared.so" "$NATIVE_OUT"/
mkdir -p "$JNA_OUT"
cp "$NATIVE_DIR/jna/$JNA_VERSION/libjnidispatch.so" "$JNA_OUT"/

copy_license() {
    local src="$1" dst="$2"
    [ -f "$src" ] && cp "$src" "$LICENSE_OUT/$dst"
}
copy_license "$WORK/lwjgl3/LICENSE.md" "LWJGL-BSD-3-Clause.txt"
copy_license "$WORK/libffi/LICENSE" "libffi-MIT.txt"
copy_license "$WORK/SDL/LICENSE.txt" "SDL3-Zlib.txt"
copy_license "$WORK/shaderc/LICENSE" "shaderc-Apache-2.0.txt"
copy_license "$WORK/SPIRV-Cross/LICENSE" "SPIRV-Cross-Apache-2.0.txt"
copy_license "$WORK/freetype/docs/FTL.TXT" "FreeType-FTL.txt"
copy_license "$WORK/freetype/docs/GPLv2.TXT" "FreeType-GPLv2.txt"
copy_license "$WORK/openal/COPYING" "OpenAL-Soft-LGPL-2.1.txt"
copy_license "$WORK/jemalloc/COPYING" "jemalloc-2-Clause-BSD.txt"
copy_license "$NDK/NOTICE" "libc++-NDK-NOTICE.txt"

(
    cd "$STAGE"
    find . -type f ! -name SHA256SUMS ! -name manifest.json -print0 \
        | sort -z | xargs -0 sha256sum > SHA256SUMS
)

python3 - "$STAGE" "$LWJGL_VERSION" "$ABI" "$API" "$NDK" <<'PY'
import hashlib, json, os, sys
from pathlib import Path

stage, lwjgl, abi, api, ndk = sys.argv[1:]
root = Path(stage)
files = []
for p in sorted(root.rglob('*')):
    if not p.is_file() or p.name in {'SHA256SUMS', 'manifest.json'}:
        continue
    rel = p.relative_to(root).as_posix()
    files.append({
        'path': rel,
        'size': p.stat().st_size,
        'sha256': hashlib.sha256(p.read_bytes()).hexdigest(),
    })
manifest = {
    'schema': 1,
    'name': 'tessera-natives',
    'lwjgl': lwjgl,
    'abi': abi,
    'android_api': int(api),
    'ndk': os.path.basename(ndk),
    'versions': {
        'lwjgl': lwjgl,
        'libffi': '3.8.0',
        'sdl3': os.environ.get('SDL_VERSION', 'release-3.4.16'),
        'shaderc': os.environ.get('SHADERC_VERSION', 'v2026.4'),
        'spirv_cross': os.environ.get('SPIRV_CROSS_VERSION', 'vulkan-sdk-1.4.363.0'),
        'freetype': os.environ.get('FREETYPE_VERSION', 'VER-2-14-3'),
        'openal_soft': os.environ.get('OPENAL_VERSION', '1.25.2'),
        'oboe': os.environ.get('OBOE_VERSION', '1.11.2'),
        'jemalloc': os.environ.get('JEMALLOC_VERSION', '5.4.0'),
        'jna': os.environ.get('JNA_VERSION', '5.17.0'),
    },
    'files': files,
}
(root / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
print(f"manifest: {len(files)} files")
PY

ZIP="$DIST/tessera-runtime-${LWJGL_VERSION}-${ABI}.zip"
rm -f "$ZIP"
(cd "$STAGE" && zip -qr "$ZIP" .)
sha256sum "$ZIP" > "$ZIP.sha256"

MANIFEST="$DIST/tessera-runtime-manifest.json"
python3 - "$ZIP" "$MANIFEST" "$LWJGL_VERSION" "$ABI" "$API" <<'PY2'
import hashlib, json, os, sys
from pathlib import Path

zip_path, manifest_path, lwjgl, abi, api = sys.argv[1:]
zip_path = Path(zip_path)
manifest = {
    'id': f'tessera-runtime-{lwjgl}-{abi}-{os.environ["RUNTIME_DATE"]}',
    'vendor': 'Tessera',
    'lwjgl': lwjgl,
    'abi': abi,
    'os': 'android',
    'libc': 'bionic',
    'min_sdk': int(api),
    'ndk': 'r30',
    'layout': 'lwjgl/<version>/*.jar, lwjgl/<version>/natives/<abi>/*.so, native/<abi>/*.so, jna/<version>/libjnidispatch.so',
    'files': {
        'zip': {
            'name': zip_path.name,
            'sha256': hashlib.sha256(zip_path.read_bytes()).hexdigest(),
            'size': zip_path.stat().st_size,
        },
    },
    'components': {
        'lwjgl': lwjgl,
        'libffi': '3.8.0',
        'sdl3': os.environ.get('SDL_VERSION', 'release-3.4.16'),
        'shaderc': os.environ.get('SHADERC_VERSION', 'v2026.4'),
        'spirv_cross': os.environ.get('SPIRV_CROSS_VERSION', 'vulkan-sdk-1.4.363.0'),
        'freetype': os.environ.get('FREETYPE_VERSION', 'VER-2-14-3'),
        'openal_soft': os.environ.get('OPENAL_VERSION', '1.25.2'),
        'oboe': os.environ.get('OBOE_VERSION', '1.11.2'),
        'jemalloc': os.environ.get('JEMALLOC_VERSION', '5.4.0'),
        'jna': os.environ.get('JNA_VERSION', '5.17.0'),
    },
    'install': {
        'extract': 'unzip; no top-level directory inside the zip',
        'classpath': 'all lwjgl/<version>/*.jar',
        'natives': 'lwjgl/<version>/natives/<abi> and native/<abi>',
        'openal_driver': 'ALSOFT_DRIVERS=opensl is the recommended default; use oboe only after route-change testing',
    },
    'source': 'https://github.com/Tessera-Launcher/BuildNatives4Android',
    'license': 'GPL-3.0-or-later; bundled components keep their own licenses (see licenses/)',
}
Path(manifest_path).write_text(json.dumps(manifest, indent=2) + '\n')
PY2

(
    cd "$DIST"
    sha256sum "$(basename "$ZIP")" tessera-runtime-manifest.json > SHA256SUMS
)

echo
echo "package: $ZIP"
echo "manifest: $MANIFEST"
du -h "$ZIP"
cat "$ZIP.sha256"
