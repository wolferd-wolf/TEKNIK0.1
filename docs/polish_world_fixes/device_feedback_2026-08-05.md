# Device feedback — 2026-08-05

Source: Akila's Android release-device screenshot and gameplay report.

## Confirmed defects

1. Right-side drag-look does not rotate the camera on the real Android build.
2. Tree leaf side and underside faces show a repeating triangular/checkered pattern.

## Initial root-cause review

### Camera

The direct `MobileCameraSensitivity` node disables the older frame-scaled action-look path by setting `action_look_speed` to zero. The older `TouchControls` node still captures the same right-side touch and marks it handled. Godot sends `_input` callbacks in reverse scene-tree order, and the older touch node is later in the scene than the direct adapter, so it can consume the event before the direct adapter receives it. The original gate called the adapter method directly and therefore did not exercise scene-level input propagation.

### Tree pattern

The visible pattern follows triangle boundaries on shadowed leaf faces rather than block-color boundaries. This is consistent with directional shadow self-shadowing/acne on voxel faces. It appeared only after the hard-edged directional shadow step and was not caught by the settings-only shadow gate.

No fix is marked complete until the camera integration gate and a visual shadow-artifact gate pass.