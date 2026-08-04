# Step 4 Acceptance Report — Android Debug Export Setup

Status: **Functionally complete and gated. APK generation remains exclusively Step 5 and was not attempted.**

## Accepted implementation

- Godot editor and Android export templates are pinned to `4.3.stable`, matching the existing CI environment.
- Android toolchain is pinned to OpenJDK 17, Android SDK Platform 34, Build-Tools 34.0.0, CMake 3.10.2.4988404, and Android NDK r23c (`23.2.8568313`).
- Godot's `android_source.zip` supplies the project-local Gradle wrapper; no system Gradle installation is required. The accepted wrapper resolves Gradle 8.2.
- Debug signing uses an ephemeral standard Android debug keystore with alias `androiddebugkey` and certificate identity `CN=Android Debug, O=Android, C=US`.
- Keystore files and project-local Android build output are excluded from version control. No release keystore, release alias, release password, or production signing configuration exists.

## Export preset

- Preset name: `Android Debug`
- Package/application ID: `com.wolferdwolf.teknik`
- Display name: `TEKNIK 0.1`
- Version code: `1`
- Version name: `0.1.0`
- Architecture: `arm64-v8a` enabled; ARMv7, x86, and x86_64 disabled
- Minimum SDK: API 24
- Target SDK: API 34
- Gradle build: enabled
- Committed export output path: empty
- Debug signing: enabled through environment-supplied local credentials
- Release signing: unset

API 24 is the chosen compatibility floor for the original mid-range Android-phone target. It keeps Android 7.0 and later devices in scope while avoiding additional legacy-device validation below that baseline.

## Accepted gate evidence

Accepted implementation head: `788672dc48f4f773edb28808b706692143c50fca`.

- Step 4 Android setup gate: Actions run `30874045063` — success.
- Step 4 job: `91881748523` — success.
- Step 4 evidence artifact: `8878902614`, `teknik-step4-android-setup`.
- Artifact digest: `sha256:729ef9ccf05c01bc6c1ccd8f40a73d7b110544100f38ed9d3781d9bf63c3eedf`.
- Inherited acceptance gate: Actions run `30874045031` — success.
- Step 3 touch regression gate: Actions run `30874045198` — success.

## Exact validation performed

- Verified Godot `4.3.stable.official.77dcf97d8` and matching Android debug, release, and Gradle-source templates.
- Verified Temurin OpenJDK `17.0.19`.
- Verified Android SDK Platform 34, Build-Tools 34.0.0, CMake 3.10.2.4988404, NDK 23.2.8568313, platform-tools, and command-line tools.
- Generated the debug keystore and read back its alias and certificate identity using `keytool`.
- Installed the project-local Godot Android Gradle template and verified its wrapper, settings file, root build file, and wrapper properties.
- Loaded the project in Godot 4.3 headless editor mode.
- Loaded `export_presets.cfg` through Godot and asserted the exact package, architecture, API, Gradle, signing, credential, and output-path contract.
- Ran the Gradle wrapper's configuration-only `help` task; Gradle reported `BUILD SUCCESSFUL`.
- Asserted that no `.apk` existed before or after validation. The accepted log marker is `ANDROID_EXPORT_SETUP_STEP4_NO_APK_PASS`.

## Validation friction and corrections

- The first standalone workflow trigger was not observable through the available Actions connector. The Step 4 gate was made reusable and attached to the established pull-request validation path.
- The first reusable invocation failed before any job ran because `runner.temp` was referenced at job-environment evaluation time. Keystore-path initialization was moved into the runtime shell step.
- The first Gradle-template attempt assumed `android_source.zip` contained an `android/build` parent directory. Godot 4.3's archive places the Gradle project at the archive root. The installer now locates and validates the wrapper root before copying it into the project-local `android/build` directory.
- No rejected run was accepted as Step 4 evidence.

## Step boundary

No Godot `--export-debug` command, Gradle assemble task, APK packaging, APK signing output, installation, or device launch was performed. Step 5 remains untouched and requires separate supervised approval.
