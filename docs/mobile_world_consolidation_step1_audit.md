# Mobile-Only World Consolidation — Step 1 Audit

## Scope

This audit defines the exact retirement boundary for the original desktop 16×16×16 GDScript chunk/terrain system and the conversion boundary for tests and CI. Step 1 makes no production-code, scene, test, or workflow deletion and introduces no gameplay or world-generation feature.

The current repository still has two world paths:

- `scenes/main.tscn` loads `scripts/world/playable_world_port.gd` on the node named `ChunkManager`.
- `playable_world_port.gd` extends the original `chunk_manager.gd` and activates the port only when forced or when Godot reports `mobile`/`android`.
- Desktop and headless runs therefore fall through to `super` and use the original desktop world unless a test explicitly sets `force_playable_world_port = true`.

That inheritance and conditional fallback are the central consolidation dependency.

## A. Original desktop world implementation — retire

The following files belong specifically to the superseded 16×16×16 desktop chunk/terrain pipeline and are not shared gameplay systems:

1. `scripts/world/chunk.gd`
   - Stores the original 16×16×16 voxel array, biome-column data, vegetation-density data, render mesh instance, and collision shape for one 3D chunk.
2. `scripts/world/chunk_manager.gd`
   - Generates and streams the original three-dimensional chunk grid.
   - Owns the old elevation/biome noise, block lookup and mutation, six-neighbor boundary handling, WorkerThreadPool remesh queue, stale-result handling, mesh application, and old remesh diagnostics.
3. `scripts/world/chunk_mesher.gd`
   - Builds the original synchronous cube mesh and material for `chunk.gd`.
4. `scripts/world/threaded_chunk_mesher.gd`
   - Builds mesh arrays from snapshots of the original `chunk.gd` representation on WorkerThreadPool tasks.
5. `scripts/world/biome_probe.gd`
   - Preloads `chunk.gd` and validates the original chunk’s biome and vegetation-density arrays. It is an old-world probe, not a reusable biome system.

## B. Bridge and scene files — modify, not retire

1. `scripts/world/playable_world_port.gd`
   - Keep the playable-world-facing role, but remove its inheritance from `chunk_manager.gd`, all conditional `super` delegation, and the desktop fallback.
   - Convert it into the single world adapter/root for all platforms, or replace it with an equivalent direct adapter backed only by `playable_world_runtime.gd`.
   - Preserve the public gameplay contract required by the player: `get_block_world`, `set_block_world`, `mine_block_world`, `place_block_world`, and any startup/recovery methods actually used at runtime.
2. `scenes/main.tscn`
   - Keep the scene and the node path/name expected by shared gameplay code.
   - Point the existing `ChunkManager` node at the single playable-world implementation. Do not create a second world node or parallel desktop scene.

## C. Dedicated original-world tests — retire

These tests directly validate old chunk storage, 16-block 3D boundaries, old mesh resources, old face definitions, or the old threaded-remesh implementation. Their implementation-specific contracts should not survive consolidation:

- `tests/null_mesh_remesh_gate.gd`
- `tests/boundary_remesh_spread_gate.gd`
- `tests/dummy_mesh_teardown_diagnostic.gd`
- `tests/face_winding_diagnostic.gd`
- `tests/threaded_remesh_step2_gate.gd`
- `tests/threaded_remesh_step3_concurrency_gate.gd`
- `tests/threaded_remesh_step5_playthrough_gate.gd`
- The generated `tests/threaded_remesh_step4_equivalence_gate.gd` materialized inside `.github/workflows/threaded-remesh-step4.yml`

Reason for retirement:

- They preload or inspect `chunk.gd`, `chunk_mesher.gd`, or `threaded_chunk_mesher.gd`.
- They require the original 16×16×16 `Vector3i` chunk model.
- They assert old mesh-array ordering, exact 30↔36 vertex counts, old mesh/collision object replacement, old queue/coalescing counters, or synchronous-versus-threaded byte equivalence.
- Those are implementation details of code that will no longer ship.

The Step 5 playthrough’s general gameplay actions—mine, place, craft, move, and jump—remain required, but their coverage belongs in the consolidated acceptance suite without the retired remesh diagnostics and timing contract.

## D. Shared gameplay tests — keep intent and repoint

These tests validate product behavior that must remain, but some currently run through the desktop fallback or assert old chunk internals.

### Keep with little or no structural change

- `tests/mining_targeting_gate.gd`
  - Uses world-facing block lookup plus target/highlight behavior. Run it against the single playable world.
- `tests/inventory_mining_step2_gate.gd`
  - Keep inventory stacking, full-inventory blocking, retry, and block mutation assertions. Adjust only fixture coordinates/readiness if needed for the playable world.
- `tests/inventory_placement_step3_gate.gd`
  - Keep item consumption, empty-slot rejection, retry, and block mutation assertions. Adjust only fixtures/readiness if needed.
- `tests/inventory_step1_gate.gd`
  - Pure inventory-model test; no world dependency. Keep unchanged.
- `tests/inventory_hotbar_step4_gate.gd`
- `tests/inventory_crafting_step5_gate.gd`
- `tests/inventory_vanilla_baseline_gate.gd`
  - Keep inventory UI, input lock, touch interaction, camera-sensitivity, and lighting-regression intent. It does not need the old world’s chunk internals.
- `tests/touch_joystick_step1_gate.gd`
- `tests/touch_drag_look_step2_gate.gd`
- Existing touch-action/hotbar tests, where present.

### Keep behavior, rewrite old structural assertions

- `tests/mining_step2_gate.gd`
  - Keep InputMap mining, data mutation, target clearing, collision correctness, and cross-boundary correctness.
  - Remove `world_to_chunk_coord`/`get_chunk` dependence and direct `mesh_instance`/`collision_shape` identity checks from the old chunk object.
  - Validate through playable-world chunk entries, collision readiness/physics rays, and observable block state.
- `tests/placement_step3_gate.gd`
  - Keep InputMap placement, inventory consumption, occupied-cell rejection, player-overlap rejection, unloaded/unavailable-cell rejection, and physics collision.
  - Remove old chunk object and old mesh-resource assumptions.
- `tests/edge_cases_step5_gate.gd`
  - Keep boundary mine/place correctness, collision correctness, player-overlap rejection, and safe mining at the loaded-world edge.
  - Remove `CHUNK_SIZE = 16`, 3D `last_center_chunk`, old `render_radius`, direct `chunks` dictionary checks, exact 30/36 vertex counts, and old remesh-idle/resource-identity requirements.
- `tests/acceptance_gate.gd`
  - Rewrite the world sections completely. It currently reads private old-manager biome noise, calls old `world_to_chunk_coord`, inspects old chunk biome arrays and vegetation density, and directly checks old mesh/collision nodes.
  - Keep scene launch, stable playable-world streaming, world variation, collision readiness, player movement/jump/look, atmosphere, screenshot, and crash checks.
  - Validate trees, water, and the actual playable-world terrain through the surviving system rather than preserving the retired desktop biome contract.

## E. Dedicated original-world workflows — retire

Remove these workflows after their corresponding old tests are retired:

- `.github/workflows/threaded-remesh-step2.yml`
- `.github/workflows/threaded-remesh-step3.yml`
- `.github/workflows/threaded-remesh-step4.yml`
- `.github/workflows/threaded-remesh-step5.yml`

They exist specifically to validate the retired WorkerThreadPool chunk mesher, old concurrency policy, old output equivalence, or old remesh timing/playthrough evidence.

## F. Existing workflows that must be rewritten

### `.github/workflows/acceptance-gate.yml`

Remove old-world-only steps for:

- `null_mesh_remesh_gate.gd`;
- `boundary_remesh_spread_gate.gd`;
- `face_winding_diagnostic.gd`;
- old 16×16×16 boundary mesh/collision assertions;
- old remesh queue/timing/equivalence assumptions.

Keep and repoint the gameplay, inventory, controller, touch, graphical, screenshot, and crash gates so desktop/headless CI instantiates the same playable-world implementation that ships on Android.

### `.github/workflows/inventory-vanilla-baseline-gate.yml`

Keep the inventory acceptance purpose, but remove or replace its historical scope lock that requires `scripts/world` and `scenes/main.tscn` to remain byte-unchanged from commit `cf99111d98f6259deda4535bfe9770bcba9d18e9`. That lock would reject the required consolidation by design.

Retain:

- 36-slot inventory model acceptance;
- inventory screen and input-lock behavior;
- mining/placement inventory regressions;
- approved camera sensitivity and vanilla-lighting regressions where still valid.

### `.github/workflows/playable-world-mining-port-gate.yml`

Keep this workflow and use it as the initial single-world reference. It already forces `playable_world_port.gd`, validates the collision-first startup ring, mines the playable terrain, and checks an atomic playable-world chunk replacement. Expand or reorganize it in Step 3 so its single-world assumptions become the normal desktop/headless acceptance path rather than a special forced-port exception.

## G. Shipping-world and feature files — keep

The surviving world implementation is:

- `scripts/world/playable_world_data.gd`
- `scripts/world/playable_world_mesher.gd`
- `scripts/world/playable_world_runtime.gd`
- `scripts/world/playable_world_port.gd`, after removal of old-manager inheritance/fallback
- `scripts/world/localized_water_bodies.gd`

Keep the current playable-world feature gates and their tests, including:

- water/localized-water validation;
- mineable-tree validation;
- playable-world leaf-seam and face-winding validation;
- vanilla/Minecraft-style playable-world lighting validation;
- camera-sensitivity validation;
- Android release/export validation.

These target the world that ships to the phone or shared presentation/input behavior, not the retired desktop terrain generator.

## H. Shared gameplay and platform systems — keep

Do not retire or duplicate:

- `scripts/player/first_person_controller.gd`
- `scripts/player/inventory_first_person_controller.gd`
- `scripts/inventory/block_inventory.gd`
- inventory hotbar and full inventory UI scripts;
- mining/placement targeting and input handling;
- crafting logic;
- touch joystick, drag-look, action buttons, and tappable hotbar;
- `project.godot` InputMap actions and mobile input settings;
- camera-sensitivity and lighting/environment settings;
- Android export presets, signing scripts, and export workflows.

## I. Shared-code dependency findings for Steps 2 and 3

1. `first_person_controller.gd` statically types `_chunk_manager` as `ChunkManager`. The consolidated adapter must either retain `class_name ChunkManager` or the player type annotation must be updated once. Do not rewrite or fork gameplay logic.
2. Runtime gameplay requires only the world-facing transaction contract: block lookup, block set/rollback, mining, placement, and scene/world availability. Preserve that contract on the playable-world adapter.
3. Inventory mining rollback calls `set_block_world`; inventory placement rollback also calls `set_block_world`. The surviving adapter must keep both operations reliable and synchronous at the data level even when visual/collision rebuild is asynchronous.
4. Old compatibility fields and methods such as `chunks`, 3D `last_center_chunk`, old `render_radius`, `world_to_chunk_coord`, `get_chunk`, old queue diagnostics, and old mesh-object identity are test/bridge baggage, not gameplay requirements.
5. The `ChunkManager` node name and `../ChunkManager` NodePath are shared scene contracts. Keeping the node name is lower-risk than renaming every gameplay and UI reference.
6. Desktop/headless CI must not depend on `OS.has_feature("mobile")` or test-only forcing after consolidation. The playable world must be the unconditional implementation on every platform.

## Explicit Step 2 retirement set

Production files to delete after the adapter dependency is removed:

- `scripts/world/biome_probe.gd`
- `scripts/world/chunk.gd`
- `scripts/world/chunk_manager.gd`
- `scripts/world/chunk_mesher.gd`
- `scripts/world/threaded_chunk_mesher.gd`

Dedicated tests to delete:

- `tests/boundary_remesh_spread_gate.gd`
- `tests/dummy_mesh_teardown_diagnostic.gd`
- `tests/face_winding_diagnostic.gd`
- `tests/null_mesh_remesh_gate.gd`
- `tests/threaded_remesh_step2_gate.gd`
- `tests/threaded_remesh_step3_concurrency_gate.gd`
- `tests/threaded_remesh_step5_playthrough_gate.gd`

Dedicated workflows to delete:

- `.github/workflows/threaded-remesh-step2.yml`
- `.github/workflows/threaded-remesh-step3.yml`
- `.github/workflows/threaded-remesh-step4.yml`
- `.github/workflows/threaded-remesh-step5.yml`

Files to modify rather than delete:

- `scripts/world/playable_world_port.gd`
- `scenes/main.tscn`
- `.github/workflows/acceptance-gate.yml`
- `.github/workflows/inventory-vanilla-baseline-gate.yml`
- `.github/workflows/playable-world-mining-port-gate.yml`
- `tests/acceptance_gate.gd`
- `tests/mining_step2_gate.gd`
- `tests/placement_step3_gate.gd`
- `tests/edge_cases_step5_gate.gd`
- Any shared integration test whose fixture needs playable-world startup/collision readiness rather than old chunk readiness.

## Step 1 gate result

PASS.

- The old production implementation, dedicated tests, dedicated workflows, bridge dependency, shared gameplay boundary, and CI conversion set are explicitly identified.
- No original-world file, test, workflow, gameplay file, or scene was deleted or behaviorally changed in Step 1.
- Step 2 must begin by removing the adapter’s inheritance/fallback dependency before deleting `chunk_manager.gd`; deleting the old files first would break scene parsing and the player’s `ChunkManager` type.