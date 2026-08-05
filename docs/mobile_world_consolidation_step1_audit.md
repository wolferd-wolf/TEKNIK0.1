# Mobile-Only World Consolidation — Step 1 Audit

## Scope and evidence

This audit identifies the original desktop 16×16×16 chunk/terrain implementation, its dedicated CI coverage, the surviving playable-world port, and the shared gameplay layers that must remain. No production file is removed or changed in Step 1.

Evidence used:
- PR #27 introduced the playable-world port and explicitly retained the old `ChunkManager` as the desktop fallback.
- PR #25 contains the threaded-remeshing implementation and dedicated gates for the old chunk system.
- PR #13 contains the mining/placement integration and the acceptance workflow additions built around the old chunk API.
- Current `playable_world_port.gd` inherits `chunk_manager.gd` and conditionally delegates to the port only on mobile/Android or when forced. This inheritance/fallback is the central consolidation dependency to remove in later steps.

## A. Original desktop world files — retire

These files implement the superseded 16×16×16 terrain/chunk/mesh pipeline and are not shared gameplay systems:

1. `scripts/world/chunk.gd`
   - Stores one 16×16×16 voxel chunk and its render/collision resources.
2. `scripts/world/chunk_manager.gd`
   - Generates and streams the original 3D chunk grid.
   - Owns old-world block lookup/mutation, boundary-neighbor remeshing, queueing, and mesh application.
3. `scripts/world/chunk_mesher.gd`
   - Synchronous hidden-face cube mesher retained as the old-world reference implementation.
4. `scripts/world/threaded_chunk_mesher.gd`
   - Worker-thread mesh-data builder for the old chunk representation.

## B. Original desktop-world tests — retire or replace

### Dedicated old-world tests: remove

These directly instantiate or assert the old chunk, mesher, chunk-coordinate, boundary-remesh, mesh-resource, or threaded-remesh implementation:

- `tests/null_mesh_remesh_gate.gd`
- `tests/boundary_remesh_spread_gate.gd`
- `tests/dummy_mesh_teardown_diagnostic.gd`
- `tests/face_winding_diagnostic.gd` when it targets `chunk_mesher.gd`
- `tests/threaded_remesh_step2_gate.gd`
- `tests/threaded_remesh_step3_concurrency_gate.gd`
- Any Step 4 threaded output-equivalence gate embedded in `tests/acceptance_gate.gd` or a threaded-remesh workflow
- Any Step 5 old-world remesh timing/recording assertions embedded in `tests/acceptance_gate.gd`

### Gameplay tests currently coupled to old-world assumptions: keep intent, repoint

These cover gameplay behavior that remains required, but their fixtures/assertions currently depend on the old chunk API, 16-block boundaries, exact old mesh vertex counts, old `chunks` dictionary contents, or old remesh diagnostics:

- `tests/mining_targeting_gate.gd`
- `tests/mining_step2_gate.gd`
- `tests/placement_step3_gate.gd`
- `tests/edge_cases_step5_gate.gd`
- `tests/acceptance_gate.gd`
- Inventory-mining and inventory-placement regressions contained in the acceptance suite
- Hotbar, crafting, touch-control, movement, jump, and camera regressions contained in the acceptance suite

Required Step 3 conversion: drive these against the playable-world API and data model, replacing old implementation assertions with behavior assertions such as block mutation, collision replacement/readiness, inventory transaction integrity, successful targeting, placement rejection, and stable streaming.

## C. Original desktop-world CI gates — retire or rewrite

### Dedicated workflows to remove

- `.github/workflows/threaded-remesh-step2.yml`
- `.github/workflows/threaded-remesh-step3.yml`
- `.github/workflows/threaded-remesh-step4.yml`
- `.github/workflows/threaded-remesh-step5.yml`

These validate an implementation that will no longer ship.

### Acceptance workflow steps to remove

Within `.github/workflows/acceptance-gate.yml`, remove old-world-only jobs/steps for:

- empty/zero-face remesh runtime cycling;
- 128-cycle old chunk remesh stress;
- 26-position 16×16×16 chunk-boundary remesh spread;
- old cube-face winding diagnostics tied to `chunk_mesher.gd`;
- exact old mesh/collision resource replacement and 30↔36 vertex-count assertions;
- unloaded-neighbor render-radius edge cycling tied to old 3D chunk coordinates;
- threaded queue/coalesce/stale-result diagnostics;
- synchronous-versus-threaded old-mesher byte-equivalence;
- old remesh timing thresholds and old remesh diagnostic fields.

### CI to keep and expand

- `.github/workflows/playable-world-mining-port-gate.yml`, initially as focused port coverage.
- `.github/workflows/acceptance-gate.yml`, rewritten so desktop/headless execution forces or directly uses the playable-world implementation.
- Android export/signing/runtime workflows, because they validate the shipping platform rather than the retired desktop world.

## D. Surviving world system — keep as the single implementation

- `scripts/world/playable_world_data.gd`
- `scripts/world/playable_world_mesher.gd`
- `scripts/world/playable_world_runtime.gd`
- `scripts/world/playable_world_port.gd` temporarily, then convert it from an old-manager subclass/conditional bridge into the single world-facing adapter or replace it with a direct playable-world root script.
- `tests/playable_world_mining_port_gate.gd`, then broaden it or split it into focused single-world gates.
- `.github/workflows/playable-world-mining-port-gate.yml`

Current architectural blocker: `playable_world_port.gd` extends `scripts/world/chunk_manager.gd`, calls `super` for the desktop path, mirrors old fields such as `chunks`, `render_radius`, and `last_center_chunk`, and exposes compatibility methods. The old manager cannot be deleted until this inheritance and fallback path are removed.

## E. Shared gameplay files/systems — keep

The following are outside the retirement scope even where they currently call the world adapter:

- `scripts/player/inventory_first_person_controller.gd`
- the base first-person movement/look controller where still used;
- inventory model and inventory transaction logic;
- mining and placement input handling;
- block targeting/highlight behavior;
- crafting recipe/action logic;
- hotbar UI and selection;
- touch joystick, drag-look, action buttons, and tappable hotbar;
- `project.godot` InputMap actions and Android/input settings;
- `scenes/main.tscn`, updated only to point at the single surviving world implementation;
- lighting/environment settings not owned by the retired terrain implementation;
- Android export configuration and signing scripts.

## F. Shared-code dependency findings to address in Step 2/3

1. The player/gameplay controller relies on a world-facing method contract including block lookup, set/mine/place, streaming refresh, recovery position, and collision readiness. Preserve this contract or update the controller once; do not duplicate gameplay logic.
2. `playable_world_port.gd` currently exposes old-manager compatibility fields/methods. Replace this compatibility inheritance with a clean playable-world implementation before deleting `chunk_manager.gd`.
3. Tests use desktop-only structural facts: 16-block chunk boundaries, three-dimensional chunk coordinates, exact old mesh vertex counts, old mesh object replacement, and old threaded diagnostic counters. Those are not valid product behavior requirements and must not be carried into the consolidated tests.
4. Mining, placement, inventory, crafting, hotbar, touch, movement, and camera behavior remain product requirements and must be preserved and retested against playable-world.
5. The playable-world port was originally mobile-conditional. Desktop/headless CI must explicitly activate the same system after consolidation; no fallback to old terrain is permitted.

## Step 1 gate result

PASS — the retirement boundary, surviving implementation, shared gameplay boundary, CI removals, test conversions, and central inheritance blocker are explicitly identified. No deletion or behavior change was made in this commit.