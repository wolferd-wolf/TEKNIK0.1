# Building and Exporting

TEKNIK 0.1 is a Godot 4 project. Repository automation is pinned to **Godot 4.3 stable**.

## Desktop Development

### Requirements

- Godot 4.3 stable.
- A desktop environment capable of running Godot's Compatibility renderer.
- Git for cloning and branch work.

### Open and Run

1. Clone the repository.
2. Launch Godot 4.3.
3. Import `project.godot`.
4. Open the project.
5. Press `F5` to run the configured main scene.

Main project scene:

```text
res://scenes/main.tscn
```

### Command-Line Parse Check

With a `godot` executable on `PATH`:

```bash
godot --headless --path . --editor --quit
```

This validates project import and script parsing. It does not replace feature tests or device testing.

## Android Configuration

The repository contains two Android presets:

- `Android Debug`
- `Android Release`

Current shared preset configuration:

| Setting | Value |
|---|---|
| Build path | Gradle |
| Minimum Android SDK | 24 |
| Target Android SDK | 34 |
| CPU architecture | ARM64 (`arm64-v8a`) |
| Package ID | `com.wolferdwolf.teknik` |
| Package name | `TEKNIK 0.1` |
| Version name | `0.1.0` |
| Version code | `1` |

The release preset exists, but production release signing credentials are not committed to the repository.

## Recommended APK Build: GitHub Actions

The supported repeatable debug export path is the manual workflow:

```text
.github/workflows/android-export-step5.yml
```

Workflow display name:

```text
TEKNIK Step 5 Android APK Export
```

### Run the Workflow

1. Push the branch containing the exact code to test.
2. Open the repository on GitHub.
3. Select **Actions**.
4. Select **TEKNIK Step 5 Android APK Export**.
5. Choose **Run workflow**.
6. Select the correct branch.
7. Start the run.

The workflow is `workflow_dispatch` only. It does not export an APK automatically on every push.

### What the Workflow Installs

The workflow uses:

- Ubuntu 24.04.
- OpenJDK 17.
- Godot 4.3 stable.
- Matching Godot 4.3 export templates.
- Android platform tools.
- Android build tools 34.0.0.
- Android platform 34.
- CMake 3.10.2.4988404.
- Android NDK 23.2.8568313.

It generates a temporary standard Android debug keystore through:

```text
scripts/android/setup_debug_keystore.sh
```

### Export Command

The workflow runs the equivalent of:

```bash
godot \
  --headless \
  --verbose \
  --path "$REPOSITORY" \
  --install-android-build-template \
  --export-debug "Android Debug" \
  "$REPOSITORY/artifacts/TEKNIK-0.1-debug.apk"
```

### Download the APK

After a successful workflow run:

1. Open the run summary.
2. Find the **Artifacts** section.
3. Download:

```text
teknik-step5-first-apk-export
```

4. Extract the archive.
5. Install:

```text
TEKNIK-0.1-debug.apk
```

The artifact also contains export logs, tool versions, source revision, APK metadata, signature verification output, and the APK SHA-256 checksum.

## Local Android Export

A local Gradle export requires:

- Godot 4.3 with Android export templates.
- OpenJDK 17.
- Android SDK platform 34.
- Android build tools 34.0.0.
- Android NDK 23.2.8568313.
- CMake 3.10.2.4988404.
- A configured debug or release keystore.

The debug keystore helper can be run as:

```bash
bash scripts/android/setup_debug_keystore.sh /absolute/path/to/teknik-debug.keystore
```

Set the expected Godot keystore environment variables before exporting:

```bash
export GODOT_ANDROID_KEYSTORE_DEBUG_PATH=/absolute/path/to/teknik-debug.keystore
export GODOT_ANDROID_KEYSTORE_DEBUG_USER=androiddebugkey
export GODOT_ANDROID_KEYSTORE_DEBUG_PASSWORD=android
```

Then run:

```bash
mkdir -p artifacts

godot \
  --headless \
  --verbose \
  --path . \
  --install-android-build-template \
  --export-debug "Android Debug" \
  "$PWD/artifacts/TEKNIK-0.1-debug.apk"
```

Local Android SDK paths must also be configured in Godot or the environment.

## Installing a Debug APK

On an Android device:

1. Transfer the APK to the device.
2. Allow installation from the file manager or browser used to open it.
3. Install the APK.
4. Launch `TEKNIK 0.1`.

For development devices with Android Debug Bridge:

```bash
adb install -r artifacts/TEKNIK-0.1-debug.apk
```

## Device Validation

A successful export does not prove that gameplay works correctly.

After every gameplay-affecting Android build, verify at minimum:

- The game launches without crashing.
- The initial chunk and collision ring load.
- Movement, jump, and drag-to-look work.
- Mining and placement work.
- Hotbar selection works.
- Inventory opens, closes, and moves stacks correctly.
- No major frame-time regression appears while walking or editing blocks.
- Saved block edits reload after restarting the game.

## Release Builds

Do not publish the current debug APK as a production release.

Before public release, the project needs:

- A protected release keystore.
- Secure CI secrets.
- A final package/versioning policy.
- Release signing verification.
- Store-ready icons, screenshots, privacy information, and testing.
- A declared software license.
- A clean migration strategy for saved worlds between generator versions.