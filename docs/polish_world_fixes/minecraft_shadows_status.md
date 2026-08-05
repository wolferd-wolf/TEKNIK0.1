# Polish and World Fixes — Minecraft-Style Shadows

Status: corrective gate complete on `session/polish-world-fixes`; not merged to `main`.

## Original implementation

- The world sun uses four directional shadow cascades to preserve nearby block-edge resolution.
- Shadow blur is limited to `0.15` for hard-edged, Minecraft-style silhouettes.
- Split blending is disabled so cascades do not soften voxel edges.
- Shadow distance is bounded to `72.0` world units for stable mobile resolution and cost.
- Bias is `0.035` and normal bias is `0.75`.
- The existing sun direction, color, and energy remain unchanged.

Original acceptance evidence:

- Original gated source: `742e9f6e62be8e87a41e85258447f34fd16469e2`
- Acceptance run: `30960332842` — success
- Artifact: `8912729130`

## Android device feedback

Akila's release-device screenshot showed a dense repeating triangular/moiré pattern on leaf sides, leaf undersides, and some trunk faces. The pattern follows shadowed triangle boundaries rather than block colors or texture coordinates.

Self-review confirmed:

- the production mesher emits each exposed voxel face once;
- both triangles in every quad have consistent winding;
- all four vertices of a face share one flat normal and one color;
- no additional tree renderer or duplicate tree mesh was introduced;
- a controlled desktop render of the real meshed tree chunk is clean even with reverse shadow culling disabled.

This isolates the visible defect to the Android compatibility-renderer shadow path rather than tree texture data, UVs, face winding, or duplicated tree generation. Desktop llvmpipe does not reproduce the mobile precision artifact.

## Corrective implementation

The production `DirectionalLight3D` now enables:

```text
shadow_reverse_cull_face = true
```

This is the smallest targeted correction for closed voxel cubes. Existing tuned bias, normal bias, cascades, distance, blur, light direction, light color, and light energy remain unchanged.

No world-generation, meshing, mining, tree, water, export-preset, or architecture code was changed.

## Corrective gate and visual review

Rejected or insufficient evidence was retained honestly:

- Run `30990105979` passed configuration and produced an image, but the full-world capture was overexposed and did not frame a tree closely enough. It was not accepted as visual proof.
- Run `30990500055` passed an initial A/B script, but the camera was misframed and the second image was blank gray. It was not accepted.
- Run `30990706776` was rejected during parsing because the test used a nonexistent `Color.distance_to()` method.

Final controlled gate:

- Passing run: `30990826126`
- Result: success
- Artifact: `8924022978`
- Artifact digest: `sha256:c26df4a800eef9b4aff75b154ac7144df40cba03b9e8f848ba4769e7f4135389`
- Source: `8178ced908aaf602962e883b2997461eb67a8c9b`

The final gate:

- parsed the complete Godot 4.3 project;
- loaded the production sun settings from `scenes/main.tscn`;
- built an actual deterministic tree chunk through `playable_world_mesher.gd`;
- rendered two isolated, centered 1280×720 viewports using the production material and light settings;
- captured baseline and reverse-cull images;
- rejected black, blank, or poorly framed captures;
- verified the correction changed only `scenes/main.tscn`, the shadow test, and its workflow;
- confirmed no `export_presets.cfg` or world-script changes.

The two desktop captures are clean and pixel-identical. This does not reproduce the Android artifact, but it confirms the corrective setting causes no desktop visual regression while targeting the mobile shadow-map path.

## Verification boundary

A fresh Android release APK containing the camera-input and shadow corrections must still be installed on Akila's device. Only that physical-device test can confirm that the moiré pattern is gone on the actual mobile GPU. No merge or standing-default export decision should be made before that result.
