# Polish and World Fixes — Water Fix Status

Status: gated complete on `session/polish-world-fixes`; not merged to `main`.

## Diagnosed cause

The Android/mobile playable-world runtime created one `PlaneMesh` sized 512×512 at `SEA_LEVEL + 0.54` and moved that plane with the player. Because this renderer did not consult terrain topology, it visually filled every low area and underground opening near sea level. The bug was therefore a global water sheet, not localized rivers or lakes.

## Fix

- Added `scripts/world/localized_water_bodies.gd` on the Android/mobile playable-world path.
- The legacy runtime plane is removed after the mobile runtime activates.
- Water is built per streamed chunk from the deterministic terrain height function.
- A column receives water only when its natural surface is below sea level and at least two cardinal neighbors are also below sea level.
- Underground air pockets and isolated low cells are not water candidates because the renderer uses the natural surface height, not arbitrary air cells.
- Water meshes have no collision and cast no shadows.
- Desktop-only world behavior is unchanged.

## Self-review

Compared against release-step completion commit `3d0e17352fd82335cf915fd6c96db653eddd293b`.

Touched only:
- `scenes/main.tscn`
- `scripts/world/localized_water_bodies.gd`
- `tests/polish_water_gate.gd`
- `.github/workflows/polish-water-gate.yml`

No export preset, input/sensitivity, shadow, tree, inventory, mining, or architecture files were changed. The initial test helper coroutine mistake was found during self-review and corrected before gating.

## Gate evidence

- Gated source commit: `fb9a82e7133b72bbb3ab69cdcfb4552541ca6432`
- Workflow: `TEKNIK Polish Water Gate`
- Actions run: `30948566610`
- Result: success
- Artifact ID: `8908127654`
- Artifact digest: `sha256:f7a82511ef250d58ebffac6718171a2775c2fb4a8e3bd7f0ad9ace977de6c249`

The gate verified:
1. Connected terrain below sea level creates water.
2. An isolated low terrain cell does not create a global sheet.
3. Terrain at or above sea level stays dry.
4. The generated water mesh covers only qualifying cells, not the full chunk.
5. The actual main scene launches with the forced Android/mobile playable-world path.
6. The legacy `Water` plane is absent after activation.
7. The localized water renderer is active and evaluates streamed chunks.

Real-device visual confirmation remains for Akila; CI verified the runtime path and topology logic headlessly.
