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


## W1 Caves — Steps 9–13 Evidence

### Step 9 — Carve integration
- Single predicate `cave_carves_cell()` shared by gameplay truth (`get_block`) and mesh carve maps.
- Carve map injected under player overrides (edits win); surface-carved columns suppress tree origins.
- Field hash fixed: any trailing `h ^= h >> k` clears the sign bit; final op is now a multiply → uniform [0,1).
- Calibrated density: tunnels 3.77%, cheese 0.63% of deep cells (~5% combined).

### Step 10 — Boundary seams
- Bidirectional seam check across chunk pairs: 91 shared carved cells, zero mismatches (pure world-coordinate field).

### Step 11 — Sky light / AO
- Mesher equivalence re-run WITH cave overrides in the path: 18/18 byte-exact, max color error 0.
- Native evaluator (TeknikRustFieldEvaluator) selected automatically when registered.

### Step 12 — Performance decision
- Threaded shipping path with caves: 17 chunks wall 150.6 ms (was 91.1 ms pre-caves).
- Delta is dict/string override plumbing, not field math (Rust evaluator active).
- Decision: keep Rust field evaluation; no further flip needed.

### Step 13 — Hitch + screenshots (both paths)
- CHUNK_APPLY_HITCH_GATE_PASS: split-frame peak p95 0.552 ms vs legacy 1.319 ms.
- artifacts/cave-interior.png (native, pocket at -34,5,-48): mean luma 0.174, 65.5% dark pixels.
- artifacts/cave-interior-fallback.png (GDScript-only ships legacy world by charter): mean luma 0.430.
- Cave interior is structurally darker → sky light does not leak underground.

## Session A appendix (steps 14-16, audited)

- **Ores (14)**: ids 10-12; depth-weighted veins via frozen `hash01_3d` primitive (policy: `scripts/world/ore_field_reference.gd`), stone-only, post-carve, map==get_block verified over 4 probe chunks (ORE_GENERATION_GATE_PASS, 291 checks). Iron deep-bias verified statistically (deep >= 2x shallow).
- **Furnace (15)**: block 13; smelting contract `scripts/smelting/furnace_recipes.gd` (SMELT_MAP 11->14, 12->15, 4->17, 5->18; FUEL_SET {16,18,5}; same-stack guard: a fuel that is also the input requires 2 units). UI panel with sequential timed smelting (1.2 s/op). Coal ore drops coal (16). SMELTING_GATE_PASS (47 checks) over real BlockInventory incl. rollback paths.
- **Metal recipes (16)**: 8 stone -> furnace; 2 iron ingot + 1 copper ingot -> drill; 1 iron + 2 stone -> 2 shafts. Original wood path kept as fallback progression (see Decisions).
- **Color parity**: ids 10-18 present in BOTH `playable_world_mesher.gd` and `teknik_voxel_mesher.hpp` with identical literals; equivalence gate now force-places every new block via synthetic overrides: 18/18 exact geometry, max_color_error=0, 23620 samples.
- **Full battery at closeout**: parity, loader, equivalence, ore, cave, smelting, threaded, hitch, screenshot gates all PASS in one session.
