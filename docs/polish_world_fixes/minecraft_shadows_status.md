# Polish and World Fixes — Minecraft-Style Shadows

Status: gated complete on `session/polish-world-fixes`; not merged to `main`.

## Implementation

- The world sun uses four directional shadow cascades to preserve nearby block-edge resolution.
- Shadow blur is limited to `0.15` for hard-edged, Minecraft-style silhouettes.
- Split blending is disabled so cascades do not soften voxel edges.
- Shadow distance is bounded to `72.0` world units for stable mobile resolution and cost.
- Bias and normal bias are tuned to reduce acne without visibly detaching shadows from blocks.
- The existing sun direction, color, and energy remain unchanged.

## Self-review

The step diff was reviewed against camera completion commit `9607f0d93464f5f456ed677c70f6c8d6cde5cf25`.
Only these files belonged to the shadow step:

- `scenes/main.tscn`
- `tests/polish_minecraft_shadows_gate.gd`
- `.github/workflows/polish-minecraft-shadows-gate.yml`

No export, water, camera, tree, mining, inventory, or architecture code was changed.

## Gate evidence

- Gated source commit: `742e9f6e62be8e87a41e85258447f34fd16469e2`
- Acceptance workflow run: `30960332842`
- Result: success
- Acceptance artifact ID: `8912729130`
- Artifact digest: `sha256:8957f05ffadf96d302d1324c48531048304e01764e8f5163cb0a4a2c9bce8704`

The gate passed project parsing, actual-scene headless launch, graphical rendering and screenshot capture, voxel face diagnostics, mining and placement regressions, inventory regressions, and touch-input regressions. The acceptance screenshot was inspected directly and showed directional, hard-edged block shadows without the former oversized soft shadow presentation.

## Verification boundary

CI and screenshot inspection verify the desktop-rendered scene and configuration. Final visual quality and performance still require confirmation on Akila's Android device.
