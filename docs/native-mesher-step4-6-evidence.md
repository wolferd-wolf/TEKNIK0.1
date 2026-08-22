# Native Mesher Steps 4–6 Evidence

## Discovery
The native mesher integration already existed end-to-end but was dead code in practice:
`playable_world_stage12_mesher.gd::_build_base_mesh()` calls `TeknikVoxelMesher.build(...)`
when registered, and the C++ registration (`register_teknik_voxel_mesher()`, commit b807c8c)
was present. Nothing ever loaded because `assets/shadcn_dark_theme.tres` failed to parse,
aborting `project.godot` load (error 43) before any GDExtension initialization.

## Unblock
Theme repair + standard `gui/theme/custom` setting (commit 8214787) restored full project
parse; extension then loaded and both classes registered.

## Step 4 — Parity gate (native vs GDScript oracle, 18 chunks incl. boundary cases)
- `NATIVE_VOXEL_MESHER_EQUIVALENCE_PASS`
- exact_geometry_cases: 18/18, color_samples: 23388, max_color_error: 0 (byte-exact)

## Step 5 — Shipping-path gates
- `NATIVE_THREADED_CHUNK_BUILD_PASS`: 17 tasks through WorkerThreadPool, wall 91.13 ms
- `CHUNK_APPLY_HITCH_GATE_PASS`: split-frame peak p95 0.308 ms vs legacy 0.83 ms
  (peak reduction 62.9%), samples 48
- `NATIVE_LOADER_GATE_PASS` with lib present (expect=1) and absent (expect=0)

## Step 6 — Performance baseline (recorded from equivalence artifact)
| Metric | GDScript | Native | Speedup |
|---|---|---|---|
| mean ms/chunk | 56.18 | 0.194 | ~290x |
| p95 ms/chunk | 61.89 | 0.237 | 261x |

Baseline threshold policy: any future native mesher regression beyond 10x of these
native numbers fails review; GDScript fallback keeps the old absolute budget.
