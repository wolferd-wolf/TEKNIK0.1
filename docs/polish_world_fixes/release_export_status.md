# Polish and World Fixes — Release Export Status

Status: gated complete on the session branch; not merged to `main`; release has not been made the standing default.

## Source and gate

- Session branch: `session/polish-world-fixes`
- Gated source commit: `cc0870fa1987c4b315d427a581b0aff84cee2e83`
- GitHub Actions run: `30943221576`
- Workflow: `TEKNIK Polish Release Export`
- Result: success
- Artifact ID: `8906066192`
- Artifact digest: `sha256:94cd4a4ddfbe530d096b4b2a6dfc9fac0a1d8c9f77eb70290d0a29c75e901594`

## Exact export command

```text
/tmp/godot/godot --headless --verbose --path /home/runner/work/TEKNIK0.1/TEKNIK0.1 --install-android-build-template --export-release Android\ Release /home/runner/work/TEKNIK0.1/TEKNIK0.1/artifacts/TEKNIK-0.1-release.apk
```

Preset: `Android Release`

## Signing and release checks

- Self-signed PKCS12 release keystore generated with alias `teknikrelease`.
- APK verified with Android APK Signature Scheme v2.
- Signer certificate: `CN=TEKNIK Test Release, O=TEKNIK, C=IN`.
- APK was not signed with the Android debug certificate.
- Exported manifest did not contain `android:debuggable="true"` or `android:debuggable="1"`.
- Only `arm64-v8a` was enabled in the release preset.

## Size comparison

- Existing debug build: `69,239,674` bytes (`69.239674 MB`, `66.032099 MiB`).
- Release APK: `63,236,557` bytes (`63.236557 MB`, `60.307080 MiB`).
- Reduction: `6,003,117` bytes (`6.003117 MB`, `5.725019 MiB`), or `8.670054%` smaller.

## Runtime verification boundary

CI verified successful release assembly, signing, manifest state, artifact integrity, and APK structure. No real Android device was connected to this run, so install and gameplay launch are not claimed. Akila must confirm installation and runtime behavior on the target device before deciding whether release becomes the standard export mode.
