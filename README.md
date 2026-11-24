# BuildNatives4Android

Android arm64-v8a runtime artifacts for Tessera Mobile's Vulkan-only
Minecraft 26.3 stack: LWJGL 3.4.3 Java jars, the Android input/SDL overlay,
and every native library needed by the launcher.

These are the pieces that used to come from Fold Craft Launcher's checked-in
AARs and snapshot jars.

## Versions

| Component | Version |
|---|---|
| LWJGL | 3.4.3 |
| libffi (static, linked into `liblwjgl.so`) | 3.8.0 |
| SDL3 | release-3.4.16 |
| shaderc | v2026.4 |
| SPIRV-Cross | vulkan-sdk-1.4.363.0 |
| FreeType | VER-2-14-3 |
| OpenAL Soft | 1.25.2 (Oboe + OpenSL backends) |
| Oboe | 1.11.2 (static, linked into `libopenal.so`) |
| jemalloc | 5.4.0 |
| JNA native | 5.17.0 |
| NDK | r30 |
| Android API | 26 |
| ABI | arm64-v8a |

## Build

Requirements: Linux, `git`, `curl`, `cmake`, `make`, Python 3, and Android
NDK r30. `JAVA_HOME` must point to a JDK with `javac`, `jar`, and JNI headers
(JDK 21 is recommended; the native build does not use the APK's D8 toolchain).

```sh
export ANDROID_NDK_HOME=$HOME/android-ndk-r30
export JAVA_HOME=$HOME/.sdkman/candidates/java/21.0.12+1.1-tem
./scripts/build-all.sh
```

Individual steps:

```sh
./scripts/build-lwjgl.sh
./scripts/build-java.sh
./scripts/build-sdl3.sh
./scripts/build-shaderc.sh
./scripts/build-spirv-cross.sh
./scripts/build-freetype.sh
./scripts/build-jemalloc.sh
./scripts/build-openal.sh
./scripts/fetch-jna.sh
./scripts/package.sh
```

Source trees and intermediate objects are cached under `work/`; Java output
lands in `build/java/` and native output in `build/natives/`.

## Output

```text
dist/tessera-runtime-3.4.3-arm64-v8a/
├── lwjgl/3.4.3/
│   ├── lwjgl.jar
│   ├── lwjgl-freetype.jar
│   ├── lwjgl-glfw.jar
│   ├── lwjgl-jemalloc.jar
│   ├── lwjgl-openal.jar
│   ├── lwjgl-opengl.jar
│   ├── lwjgl-sdl.jar
│   ├── lwjgl-shaderc.jar
│   ├── lwjgl-spvc.jar
│   ├── lwjgl-stb.jar
│   ├── lwjgl-vma.jar
│   ├── lwjgl-vulkan.jar
│   ├── version
│   └── natives/arm64-v8a/
│       ├── liblwjgl.so
│       ├── liblwjgl_opengl.so
│       ├── liblwjgl_stb.so
│       ├── liblwjgl_vma.so
│       └── libfreetype.so
├── native/arm64-v8a/
│   ├── libSDL3.so
│   ├── libshaderc.so
│   ├── libspirv-cross.so
│   ├── libopenal.so
│   ├── libjemalloc.so
│   └── libc++_shared.so
├── jna/5.17.0/
│   └── libjnidispatch.so
├── licenses/
├── manifest.json
└── SHA256SUMS

dist/tessera-runtime-3.4.3-arm64-v8a.zip
dist/tessera-runtime-3.4.3-arm64-v8a.zip.sha256
```

All native `LOAD` segments are linked with 16 KB page alignment
(`-Wl,-z,max-page-size=16384`).

## Java overlay

`scripts/build-java.sh` starts from the official Maven 3.4.3 jars and applies
only the Android-specific hooks:

- `org.lwjgl.glfw.CallbackBridge` is added to `lwjgl-glfw.jar` for the game
  VM's `libpojavexec` input bridge.
- `SDLInit.SDL_Init` notifies `CallbackBridge.nativeNotifyLauncher` before
  SDL starts.
- `SDL_SetWindowRelativeMouseMode` forwards the grab state through
  `CallbackBridge.nativeSetGrabbing`.
- `SDLVideo.SDL_GetDisplayName` returns a stable Android label instead of
  passing a possibly-tagged native pointer into LWJGL's UTF-8 reader.

The official `lwjgl-sdl` source is fetched from Maven, patched, and compiled
against the 3.4.3 jars. No third-party launcher's source tree is required.

## Release manifest

The launcher should fetch the manifest first:

```text
https://github.com/Tessera-Launcher/BuildNatives4Android/releases/latest/download/tessera-runtime-manifest.json
```

Read `files.zip.name`, `files.zip.sha256`, and `files.zip.size`, then download the
asset from the same release and verify the SHA-256 before extracting.

The release also carries `SHA256SUMS` covering the zip and manifest.

## Notes

- `liblwjgl.so` is built from LWJGL 3.4.3 sources and statically links libffi
  3.8.0, matching the headers bundled with 3.4.3.
- OpenAL Soft contains both Oboe/AAudio and OpenSL backends. Oboe 1.11.2 is
  statically linked; no separate `liboboe.so` is needed.
- FCL and PojavLauncher default to `ALSOFT_DRIVERS=opensl` on Android. Our
  package keeps OpenSL as the recommended default; Oboe can be selected with
  `ALSOFT_DRIVERS=oboe` for testing. AAudio has known route-change issues when
  plugging/unplugging headphones.
- `libjemalloc.so` is jemalloc 5.4.0. 5.3.x is not sufficient: it lacks
  `je_free_sized`, which the LWJGL 3.4.3 jemalloc binding requires.
- GrapheneOS/Android 17 may enable MTE, which tags native pointers in the top
  byte. LWJGL 3.4.3 on Java 28 reads strings through FFM and rejects those
  tagged pointers. The launcher must either run with MTE disabled for the app
  (`android:memtagMode="off"`) or use a runtime with an untagging memory
  backend. This runtime includes the SDL display-name fallback, but the
  launcher-side MTE setting is still required for Vulkan extension strings.
- This repository builds the runtime only. `libfcl.so` / `libpojavexec.so` are
  still FCL-side JNI host libraries and are not rebuilt here.
- Versions are pinned in `scripts/lib.sh`.
