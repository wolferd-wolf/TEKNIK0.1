# Polish and World Fixes — Camera Sensitivity Status

Status: gated complete on the session branch; not merged to `main`.

## Gated source and evidence

- Session branch: `session/polish-world-fixes`
- Gated source commit: `8be5ba1219ee783c5cfeaf0961f0dd78c7076e6e`
- Dedicated workflow: `TEKNIK Polish Camera Sensitivity Gate`
- Passing run: `30956691684`
- Result: success
- Artifact ID: `8911306633`
- Artifact digest: `sha256:846e7a72d3ea4c17345dc3b3b6ba4c8d8b7508e665298ab8894646eaa7edc32f`

## Implemented behavior

- Right-side mobile drag uses direct screen-drag pixel deltas.
- Camera rotation is independent of frame time.
- Existing touch InputMap states remain available for inherited controls.
- The lower-right action-button area remains reserved and does not claim camera look.
- Unclaimed touch indices do not rotate the camera.
- Releasing the active look touch clears camera capture.

## Gate coverage

The dedicated gate:

- parsed the full Godot project with Godot 4.3;
- created the sensitivity adapter in a deterministic test viewport;
- verified the adapter disables the legacy frame-scaled action-look path;
- verified left-side and bottom action-area touches are rejected;
- verified a right-side drag maps directly through the configured radians-per-pixel sensitivity;
- verified unrelated touch indices do not rotate the camera;
- verified touch release clears capture;
- verified `scenes/main.tscn` contains the adapter;
- verified the step changed only the approved scene, adapter, test, and gate workflow files;
- verified `export_presets.cfg` was not touched.

## Failed gate and correction

- Rejected run: `30956628209`.
- Failure: Godot could not infer the test adapter variable type at `tests/polish_camera_sensitivity_gate.gd:25`.
- Correction: explicitly typed the loaded script and adapter node, and used typed-safe `set`/`call` access in the dynamic test harness.
- The corrected gate passed in run `30956691684`.

## Inherited regression evidence

For the preceding camera checkpoint `9bda98dad47a1314ad1bb348e5590935e2633698`:

- Acceptance Gate `30952946092`: success.
- Step 3 Touch Gate `30952946476`: success.
- Polish Water Gate `30952946099`: success.
- Release Export `30952946087`: success.
- Android Export Setup `30952946148`: success.
- Export Configuration Diagnostic `30952946119`: success.

Two unrelated legacy workflows failed at that checkpoint (`Playable World Mining Port` and `Threaded Remesh Step 5 Playthrough`); the camera-specific, acceptance, touch, water, and export gates passed.

## Runtime verification boundary

CI validated deterministic drag behavior and scene integration. A physical Android device was not connected, so final subjective feel and device-specific touch behavior still require Akila's on-device confirmation.
