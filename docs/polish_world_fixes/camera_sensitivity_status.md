# Polish and World Fixes — Camera Sensitivity Status

Status: gated complete on the session branch; not merged to `main`.

## Original implementation evidence

- Original gated source: `8be5ba1219ee783c5cfeaf0961f0dd78c7076e6e`
- Original passing run: `30956691684`
- Original artifact: `8911306633`

## Implemented behavior

- Right-side mobile drag uses direct screen-drag pixel deltas.
- Camera rotation is independent of frame time.
- Existing touch InputMap states remain available for inherited controls.
- The lower-right action-button area remains reserved and does not claim camera look.
- Unclaimed touch indices do not rotate the camera.
- Releasing the active look touch clears camera capture.

## Real-device correction

Akila's release-device test showed that right-side drag did not rotate the camera. The original gate called `MobileCameraSensitivity._input()` directly and therefore missed the real scene-level conflict:

- `MobileCameraSensitivity` disabled the old frame-scaled action-look path by setting `action_look_speed` to zero.
- The older `TouchControls` node still captured the same right-side drag and marked it handled.
- The direct adapter was earlier than that overlay in reverse scene-tree input order, so it never received the Android event.

The correction:

- places `MobileCameraSensitivity` after `TouchControls` in `scenes/main.tscn`, so it receives `_input` first;
- retains a deferred ordering fallback for dynamically assembled hosts;
- checks precedence against the actual blocking touch overlay rather than unrelated later UI children;
- injects `InputEventScreenTouch` and `InputEventScreenDrag` through `Input.parse_input_event` in the full main scene under Xvfb;
- proves both the direct adapter and legacy overlay receive the same touch while the direct adapter rotates yaw and pitch before the overlay handles propagation.

## Corrective gate evidence

- Rejected run `30989257204`: runtime `move_child()` during `_ready()` was rejected because the parent was still setting up children.
- Rejected run `30989512709`: the test used headless Godot, which did not dispatch parsed screen events to either live touch listener, and its “must be last child” assertion incorrectly counted dynamically added hotbar UI.
- Passing run: `30989700918`.
- Result: success.
- The passing gate parsed the project, ran graphical real-scene touch propagation, verified yaw and pitch deltas, verified release semantics, and passed corrective scope isolation.

## Runtime verification boundary

The corrected CI gate now covers the exact scene-level input conflict reported on-device. A new Android APK must still be installed by Akila to confirm the correction on the physical touchscreen before merge.
