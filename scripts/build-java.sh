#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/lib.sh"
export LC_ALL=C.UTF-8 LANG=C.UTF-8

require_tool curl
require_tool unzip
require_tool python3
[ -x "$JAVA_HOME/bin/javac" ] || { echo "javac not found under $JAVA_HOME" >&2; exit 1; }
JAVAC="$JAVA_HOME/bin/javac"
JAR="$JAVA_HOME/bin/jar"

JAVA_WORK="$WORK/java"
SRC_DIR="$JAVA_WORK/src"
CLASSES="$JAVA_WORK/classes"
JARS="$JAVA_WORK/jars"
OUT="$BUILD/java/lwjgl/$LWJGL_VERSION"
rm -rf "$JAVA_WORK" "$OUT"
mkdir -p "$SRC_DIR" "$CLASSES" "$JARS" "$OUT"

MODULES=(
    lwjgl
    lwjgl-freetype
    lwjgl-jemalloc
    lwjgl-openal
    lwjgl-opengl
    lwjgl-sdl
    lwjgl-shaderc
    lwjgl-spvc
    lwjgl-stb
    lwjgl-vma
    lwjgl-vulkan
    lwjgl-glfw
)

for module in "${MODULES[@]}"; do
    url="https://repo1.maven.org/maven2/org/lwjgl/$module/$LWJGL_VERSION/$module-$LWJGL_VERSION.jar"
    curl -fsSL --retry 3 -o "$JARS/$module.jar" "$url"
done

curl -fsSL --retry 3 -o "$JAVA_WORK/jspecify.jar" \
    "https://repo1.maven.org/maven2/org/jspecify/jspecify/1.0.0/jspecify-1.0.0.jar"
curl -fsSL --retry 3 -o "$JAVA_WORK/lwjgl-sdl-sources.jar" \
    "https://repo1.maven.org/maven2/org/lwjgl/lwjgl-sdl/$LWJGL_VERSION/lwjgl-sdl-$LWJGL_VERSION-sources.jar"
mkdir -p "$SRC_DIR/org/lwjgl/sdl" "$SRC_DIR/org/lwjgl/glfw"
unzip -p "$JAVA_WORK/lwjgl-sdl-sources.jar" org/lwjgl/sdl/SDLInit.java > "$SRC_DIR/org/lwjgl/sdl/SDLInit.java"
unzip -p "$JAVA_WORK/lwjgl-sdl-sources.jar" org/lwjgl/sdl/SDLMouse.java > "$SRC_DIR/org/lwjgl/sdl/SDLMouse.java"
cp "$ROOT/java/org/lwjgl/glfw/CallbackBridge.java" "$SRC_DIR/org/lwjgl/glfw/CallbackBridge.java"

python3 - "$SRC_DIR/org/lwjgl/sdl" <<'PY'
import pathlib, sys
root = pathlib.Path(sys.argv[1])

init = root / 'SDLInit.java'
s = init.read_text()
old = """    public static boolean SDL_Init(@NativeType("SDL_InitFlags") int flags) {
        long __functionAddress = Functions.Init;
        return invokeZ(flags, __functionAddress);
    }"""
new = """    public static boolean SDL_Init(@NativeType("SDL_InitFlags") int flags) {
        org.lwjgl.glfw.CallbackBridge.nativeNotifyLauncher(
                org.lwjgl.glfw.CallbackBridge.SDL,
                org.lwjgl.glfw.CallbackBridge.INIT);
        long __functionAddress = Functions.Init;
        return invokeZ(flags, __functionAddress);
    }"""
assert old in s, 'SDL_Init anchor not found'
init.write_text(s.replace(old, new, 1))

mouse = root / 'SDLMouse.java'
s = mouse.read_text()
old = """        if (CHECKS) {
            check(window);
        }
        return invokePZ(window, enabled, __functionAddress);
    }"""
new = """        if (CHECKS) {
            check(window);
        }
        boolean result = invokePZ(window, enabled, __functionAddress);
        org.lwjgl.glfw.CallbackBridge.nativeSetGrabbing(enabled);
        return result;
    }"""
assert old in s, 'SDL_SetWindowRelativeMouseMode anchor not found'
mouse.write_text(s.replace(old, new, 1))
PY

"$JAVAC" --release 8 -Xlint:-options \
    -cp "$JARS/lwjgl.jar:$JARS/lwjgl-sdl.jar:$JARS/lwjgl-glfw.jar:$JAVA_WORK/jspecify.jar" \
    -d "$CLASSES" \
    "$SRC_DIR/org/lwjgl/sdl/SDLInit.java" \
    "$SRC_DIR/org/lwjgl/sdl/SDLMouse.java" \
    "$SRC_DIR/org/lwjgl/glfw/CallbackBridge.java"

# Keep the upstream jars byte-identical except for the two patched SDL classes
# and the game-side CallbackBridge.
cp "$JARS"/*.jar "$OUT"/
"$JAR" uf "$OUT/lwjgl-sdl.jar" \
    -C "$CLASSES" org/lwjgl/sdl/SDLInit.class \
    -C "$CLASSES" org/lwjgl/sdl/SDLMouse.class
"$JAR" uf "$OUT/lwjgl-glfw.jar" \
    -C "$CLASSES" org/lwjgl/glfw/CallbackBridge.class
printf '%s' "$(date +%s)" > "$OUT/version"

# Verify the hooks really landed in the classes that the game JVM will load.
"$JAVA_HOME/bin/javap" -p -c -classpath "$OUT/lwjgl-sdl.jar:$OUT/lwjgl-glfw.jar" \
    org.lwjgl.sdl.SDLInit org.lwjgl.sdl.SDLMouse > "$JAVA_WORK/javap.txt"
grep -q 'CallbackBridge.nativeNotifyLauncher' "$JAVA_WORK/javap.txt" \
    || { echo 'SDL_Init hook missing' >&2; exit 1; }
grep -q 'CallbackBridge.nativeSetGrabbing' "$JAVA_WORK/javap.txt" \
    || { echo 'SDLMouse hook missing' >&2; exit 1; }

echo "Java LWJGL $LWJGL_VERSION output:"
ls -lh "$OUT"/*.jar
