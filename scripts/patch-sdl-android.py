#!/usr/bin/env python3
"""Tessera's Android SDL3 adjustments.

The Android SDL backend supports one native window, while Minecraft 26.3 creates
a hidden tool window and then the real game window. The launcher also loads SDL
in its own ART VM before the embedded HotSpot game VM loads the same library.

These patches keep SDLActivity callbacks in the first VM and reuse the first
Android window, removing the need for FCL's dynamic SDL hook library.
"""
import pathlib
import sys

if len(sys.argv) != 2:
    raise SystemExit("usage: patch-sdl-android.py <SDL source dir>")

root = pathlib.Path(sys.argv[1])

# 1. Only the first Java VM owns SDLActivity.
path = root / "src/core/android/SDL_android.c"
text = path.read_text()
if "TESSERA_FIRST_JAVA_VM" not in text:
    old = "static JavaVM *mJavaVM = NULL;\n"
    new = (
        "static JavaVM *mJavaVM = NULL;\n"
        "/* TESSERA_FIRST_JAVA_VM: the launcher VM owns SDLActivity. */\n"
        "static JavaVM *mFirstJavaVM = NULL;\n"
    )
    assert old in text, "mJavaVM anchor not found"
    text = text.replace(old, new, 1)
    old = (
        "JNIEXPORT jint JNICALL JNI_OnLoad(JavaVM *vm, void *reserved)\n"
        "{\n"
        "    JNIEnv *env = NULL;\n"
        "\n"
        "    mJavaVM = vm;"
    )
    new = (
        "JNIEXPORT jint JNICALL JNI_OnLoad(JavaVM *vm, void *reserved)\n"
        "{\n"
        "    JNIEnv *env = NULL;\n"
        "\n"
        "    if (mFirstJavaVM == NULL) {\n"
        "        mFirstJavaVM = vm;\n"
        "    } else if (mFirstJavaVM != vm) {\n"
        "        __android_log_print(ANDROID_LOG_INFO, \"SDL\", \"Skipping JNI_OnLoad for secondary VM\");\n"
        "        return JNI_VERSION_1_4;\n"
        "    }\n"
        "\n"
        "    mJavaVM = vm;"
    )
    assert old in text, "JNI_OnLoad anchor not found"
    text = text.replace(old, new, 1)
    path.write_text(text)

# 2. Reuse the first Android window and ignore resizes.
path = root / "src/video/SDL_video.c"
text = path.read_text()
if "TESSERA_ANDROID_PRIMARY_WINDOW" not in text:
    marker = "SDL_Window *SDL_CreateWindowWithProperties(SDL_PropertiesID props)\n{"
    insert = (
        "#ifdef SDL_VIDEO_DRIVER_ANDROID\n"
        "/* TESSERA_ANDROID_PRIMARY_WINDOW: Minecraft needs two SDL windows, but\n"
        " * Android's video backend only supports one. Keep the first window. */\n"
        "static SDL_Window *s_tessera_primary_window = NULL;\n"
        "static int s_tessera_primary_window_refs = 0;\n"
        "#endif\n"
        "\n"
        "SDL_Window *SDL_CreateWindowWithProperties(SDL_PropertiesID props)\n"
        "{"
    )
    assert marker in text, "SDL_CreateWindowWithProperties anchor not found"
    text = text.replace(marker, insert, 1)

    anchor = (
        "    if (!_this) {\n"
        "        // Initialize the video system if needed\n"
        "        if (!SDL_Init(SDL_INIT_VIDEO)) {\n"
        "            return NULL;\n"
        "        }\n"
        "\n"
        "        // Make clang-tidy happy\n"
        "        if (!_this) {\n"
        "            return NULL;\n"
        "        }\n"
        "    }\n"
    )
    reuse = anchor + (
        "\n"
        "#ifdef SDL_VIDEO_DRIVER_ANDROID\n"
        "    if (s_tessera_primary_window) {\n"
        "        ++s_tessera_primary_window_refs;\n"
        "        return s_tessera_primary_window;\n"
        "    }\n"
        "#endif\n"
    )
    assert anchor in text, "video init anchor not found"
    text = text.replace(anchor, reuse, 1)

    anchor = (
        "    SDL_ClearError();\n"
        "\n"
        "    return window;\n"
        "}\n"
        "\n"
        "SDL_Window *SDL_CreateWindow(const char *title, int w, int h, SDL_WindowFlags flags)"
    )
    remember = (
        "    SDL_ClearError();\n"
        "\n"
        "#ifdef SDL_VIDEO_DRIVER_ANDROID\n"
        "    if (!s_tessera_primary_window) {\n"
        "        s_tessera_primary_window = window;\n"
        "    }\n"
        "#endif\n"
        "\n"
        "    return window;\n"
        "}\n"
        "\n"
        "SDL_Window *SDL_CreateWindow(const char *title, int w, int h, SDL_WindowFlags flags)"
    )
    assert anchor in text, "window return anchor not found"
    text = text.replace(anchor, remember, 1)

    anchor = (
        "void SDL_DestroyWindow(SDL_Window *window)\n"
        "{\n"
        "    CHECK_WINDOW_MAGIC(window,);\n"
    )
    destroy = (
        "void SDL_DestroyWindow(SDL_Window *window)\n"
        "{\n"
        "    CHECK_WINDOW_MAGIC(window,);\n"
        "\n"
        "#ifdef SDL_VIDEO_DRIVER_ANDROID\n"
        "    if (window == s_tessera_primary_window) {\n"
        "        if (s_tessera_primary_window_refs > 0) {\n"
        "            --s_tessera_primary_window_refs;\n"
        "            return;\n"
        "        }\n"
        "        s_tessera_primary_window = NULL;\n"
        "    }\n"
        "#endif\n"
    )
    assert anchor in text, "SDL_DestroyWindow anchor not found"
    text = text.replace(anchor, destroy, 1)

    anchor = (
        "bool SDL_SetWindowSize(SDL_Window *window, int w, int h)\n"
        "{\n"
        "    CHECK_WINDOW_MAGIC(window, false);\n"
    )
    resize = (
        "bool SDL_SetWindowSize(SDL_Window *window, int w, int h)\n"
        "{\n"
        "    CHECK_WINDOW_MAGIC(window, false);\n"
        "#ifdef SDL_VIDEO_DRIVER_ANDROID\n"
        "    (void)w;\n"
        "    (void)h;\n"
        "    return true;\n"
        "#endif\n"
    )
    assert anchor in text, "SDL_SetWindowSize anchor not found"
    text = text.replace(anchor, resize, 1)
    path.write_text(text)
