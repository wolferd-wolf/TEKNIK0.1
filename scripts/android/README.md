# Android setup contract — Godot 4.3

This directory contains setup helpers for the supervised Android debug-export workflow.

## Required toolchain

- Godot editor: `4.3.stable`
- Matching Godot export templates: `4.3.stable`
- OpenJDK: 17
- Android SDK Platform: 34
- Android SDK Build-Tools: 34.0.0
- CMake: 3.10.2.4988404
- Android NDK: r23c / 23.2.8568313
- Gradle: use the wrapper provided by Godot's `android_source.zip`; no system Gradle installation is required

## Debug signing

Run `setup_debug_keystore.sh`. It creates only the standard Android debug identity (`androiddebugkey`) for device testing. The keystore and credentials remain outside version control. No release keystore is configured.

## Export preset

- Preset: `Android Debug`
- Package: `com.wolferdwolf.teknik`
- ABI: `arm64-v8a` only
- Minimum SDK: API 24
- Target SDK: API 34
- Gradle build: enabled

## Step boundary

Step 4 performs toolchain, signing, preset, and Gradle configuration checks only. It must not call Godot `--export-debug`, Gradle `assemble`, or otherwise produce an APK. APK generation belongs exclusively to supervised Step 5.
