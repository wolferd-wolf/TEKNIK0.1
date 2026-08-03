# TEKNIK Build Plan — Session: World Subsystem

## Rules (apply to everything below)
1. Build in GDScript only. No native Rust/C++ core this session.
2. One numbered item = one commit. Do not bundle items together.
3. Do not build anything not listed here, even if it's in the full design doc. If you think of something extra, add it to a "Deferred" note at the bottom of this file instead of building it.
4. Commit message format: `[TEKNIK] step N: <short description>`
5. If a step fails or you have to guess at a design decision, write the decision and why in a `## Decisions` section at the bottom of this file, and commit that update alongside the code.
6. Stop at the end of step 5. Do not continue into mining, crafting, or mechanical systems even if there's time left — those are separate sessions.
7. Target platform is Android. Desktop keyboard/mouse is a temporary testing harness only — do not hardcode movement or camera logic directly to keyboard/mouse. Abstract input behind an input layer (e.g. Godot's InputMap actions, not raw key checks) so touch controls can be swapped in later without rewriting the player controller. If you write `Input.is_key_pressed()` or similar hardcoded checks anywhere, that's a rule violation — use `Input.is_action_pressed("move_forward")` etc. and bind those actions to keyboard for now.

## Steps

1. Chunk system: 16x16x16 chunks, dictionary keyed by chunk coordinate, load/unload by fixed radius around player (brute-force distance check, no priority queue).
2. Terrain generation: one noise layer for elevation, block-by-depth assignment (grass/dirt/stone), one additional noise channel for biome selection across 2-3 biomes (plains/forest/desert) affecting surface block and vegetation density only.
3. Chunk meshing: single mesh per chunk, hidden-face culling only (no greedy meshing).
4. Player controller: first-person, capsule collision, walk/jump/gravity/ground detection, keyboard/mouse input.
5. Atmosphere: pick ONE — full day/night cycle OR static lighting + sky color. State which and why in Decisions.

## Definition of done
Playable desktop build: player walks around chunked, biome-varied procedural terrain, with lighting/day-night working. No crashes on chunk load/unload at the edge of render radius.

## Report format
When done, list the commits (hash + message) in order. Do not summarize in prose — the commit log is the report.

## Decisions
- Hour 1: Use a Godot 4.x GDScript `Node3D` scaffold with the GL Compatibility renderer as the Android baseline. This avoids introducing platform-specific rendering code before the world subsystem is proven.
- Hour 1: Use `Vector3i` chunk coordinates as dictionary keys and floor-based world-to-chunk conversion. Floor conversion is required so negative world positions map consistently to negative chunk coordinates instead of truncating toward zero.
- Hour 2: Use a full three-dimensional Euclidean chunk radius rather than a horizontal-only radius because each chunk is explicitly 16x16x16. The implementation brute-forces offsets inside a radius-squared check and does not use a priority queue.
- Hour 2: Use a temporary `StreamingAnchor` node until the Step 4 player exists. The manager depends only on a `Node3D` position, so the future player can replace the anchor without rewriting streaming logic.
- Hour 2 blocker: Step 1 is not marked complete. The smoke probe checks stable chunk counts and positive/negative boundary transitions, but screenshot evidence is not meaningful yet because chunks intentionally have no mesh until Step 3, and no verified Godot runtime/CI screenshot artifact is currently available.
- Hour 3: Use one deterministic `FastNoiseLite` simplex-smooth FBM channel for elevation. Terrain data is stored as one byte per voxel in a `PackedByteArray` so the GDScript baseline remains compact enough for Android-oriented testing.
- Hour 3: Assign grass at the sampled surface, dirt for the next three blocks, stone below that, and air above the surface. Biome variation is intentionally deferred to Hour 4.
- Hour 3 blocker: Terrain data can be generated and queried, but it is not yet visually inspectable because Step 3 meshing has not started and the repository still lacks a verified runtime screenshot pipeline.
- Hour 4: Use one second deterministic `FastNoiseLite` simplex-smooth FBM channel at a lower frequency for broad biome regions. Samples below -0.25 select desert, above 0.25 select forest, and the middle band selects plains.
- Hour 4: Biomes affect only the surface block and per-column vegetation-density metadata. Desert uses sand with density 0, plains retain grass with density 20, and forest retains grass with density 75. No vegetation objects are spawned because that would exceed Step 2 scope.
- Hour 4 blocker: Step 2 data requirements are implemented and guarded by a biome metadata probe, but Step 2 is not marked complete because no visual mesh or verified runtime screenshot/crash evidence exists yet. The visual gate remains deferred until Step 3 makes terrain renderable.
- Hour 5: Build exactly one `ArrayMesh` and one `MeshInstance3D` per chunk using explicit six-face cube definitions. Vertex colors provide temporary grass, dirt, stone, and sand differentiation without introducing texture work outside the plan.
- Hour 5 blocker: The mesher currently emits all six faces for every solid block by design. Hidden-face culling, neighboring-chunk boundary checks, collision generation, and verified runtime screenshot/crash evidence remain for Hour 6, so Step 3 is not complete.
- Hour 6: Cull a face whenever its adjacent voxel is solid. For out-of-range local coordinates, resolve the adjacent voxel through a manager-owned world-coordinate lookup so culling works across loaded chunk boundaries and negative coordinates.
- Hour 6: Register a generated chunk before meshing it, then remesh its six loaded neighbors. When unloading, erase the chunk first and remesh surviving neighbors so newly exposed boundary faces are restored.
- Hour 6: Derive one concave trimesh collision shape from each chunk's already-culled render mesh. This keeps render and collision geometry consistent for the Step 4 controller without adding a second voxel traversal.
- Hour 6 blocker: Static repository inspection confirms the culling, neighbor-remesh, and collision paths are committed, but no verified Godot executable run, screenshot artifact, or crash-check workflow is available. Step 3 therefore remains open and no step completion commit is created.
- Hour 7: Replace the temporary streaming anchor with a `CharacterBody3D` player using a capsule collision shape. The chunk manager continues depending only on the target's `Node3D` position, so streaming now follows the player without coupling world logic to controller code.
- Hour 7: Define `move_forward`, `move_backward`, `move_left`, `move_right`, and `jump` in Godot InputMap. Keyboard bindings are desktop-only test mappings; the controller reads only actions through `Input.get_vector()` and `Input.is_action_just_pressed()`.
- Hour 7 blocker: Walk, jump, gravity, acceleration, ground detection, capsule collision, and player-driven streaming are statically implemented, but no verified Godot runtime movement test, screenshot, or crash-check evidence exists. Camera-look input is intentionally deferred to Hour 8, so Step 4 remains open.
- Hour 8: Route both mouse motion and future touch/controller look actions through one `apply_look_delta()` method. Mouse input is only a desktop harness; four empty InputMap look actions provide the Android-facing abstraction seam without hardcoding touch behavior prematurely.
- Hour 8: Clamp camera pitch to 89 degrees while yaw rotates the player body, preserving movement-relative facing and preventing camera inversion.
- Hour 8 blocker: Spawn wiring, camera ownership, movement-relative yaw, pitch clamping, and abstract look actions are statically present, but no verified Godot runtime, movement screenshot, collision test, or crash-check artifact exists. Step 4 remains open and no step completion commit is created.
- Hour 9: Choose static lighting plus a fixed procedural sky instead of a day/night cycle. A single `DirectionalLight3D` and `WorldEnvironment` avoid per-frame sun rotation, time-state logic, dynamic atmosphere transitions, and additional mobile validation risk while still making terrain readable on the Android-focused GL Compatibility baseline.
- Hour 9: Keep the sky procedural but static, use low sky radiance resolution, modest ambient energy, and a bounded directional-shadow distance. These settings reduce unnecessary atmosphere and shadow cost while preserving depth cues across the current chunk radius.
- Hour 9 blocker: Step 5 is statically implemented, but no verified Godot runtime render, screenshot artifact, lighting inspection, or crash-check evidence exists. No `[TEKNIK] step 5` completion commit is created until that gate passes.

## Session: Mining and Placement

### Rules (in addition to all prior session rules — GDScript only, one step per commit, no scope creep, screenshot/crash gate before marking any step complete, no Android export)

1. No inventory or crafting system this session. Mined blocks are removed from the world only — they do not go into any inventory yet.
2. Placement uses a hardcoded test palette: number keys 1-4 (via InputMap actions, not raw key checks) select stone/dirt/grass/sand as the block to place. This is a placeholder, not the real item system.
3. Do not build tool types, mining speed variation, or hardness values this session — mining is instant (single action removes the block) for now.

### Steps

1. Raycast targeting: cast a ray from the camera each frame (or on demand) into the voxel world, find the first solid block hit, return its coordinate and the hit face. Render a visible outline/highlight on the targeted block.
2. Mining: on mine-action input (InputMap action, not raw key), remove the targeted block (set to air), trigger a remesh of the affected chunk (and neighbor chunk if the removed block was on a boundary).
3. Placement: on place-action input, compute the adjacent position from the hit face, validate it's not inside the player's collision shape and not already solid, place the currently-selected palette block there, trigger remesh.
4. Palette selection: number keys 1-4 bound via InputMap select the active placement block type. Show the current selection somewhere visible (even placeholder on-screen text is fine — no real HUD system yet).
5. Edge cases: mining/placing at chunk boundaries must correctly update both affected chunks' meshes and collision. Placing must not allow blocks inside the player. Mining at the edge of render radius must not crash.

### Definition of done
Player can walk up to terrain, see a block highlight, mine a block (it disappears, hole remains, no crash), and place a block from the 4-block palette (appears, collides correctly, no clipping into player).

### Report format
Commit log in order, plus Actions run status. No prose summary in place of the commit log.

### Decisions and gate evidence
- Step 2 investigation: The recurring Godot 4.3 dummy-renderer message `Parameter "m" is null` is reproducible by creating and freeing a plain `MeshInstance3D` containing a built-in `BoxMesh`; it occurs between the pre-free and post-free markers without any voxel or mining code. The repeated messages in normal headless traversal therefore come from the dummy renderer when chunk mesh instances are freed during streaming, not from the mining action or the new remesh API.
- Step 2 investigation: A separate real zero-face weakness existed in the original mesher. Calling `SurfaceTool.commit()` after emitting no visible faces creates an unusable renderer mesh state. The mesher now counts emitted faces and skips `commit()` entirely when the count is zero. Render and collision nodes are created lazily only after a valid mesh exists; a later zero-face rebuild hides the retained valid mesh and clears collision.
- Step 2 safety classification: The remaining free-time dummy-renderer message is non-fatal engine-backend behavior in Godot 4.3 and is not emitted during the 128-cycle solid-to-empty remesh runtime window. The Xvfb GL Compatibility runs complete without this dummy-backend error. It is therefore not evidence of mining instability, while the zero-face application path was treated as a real defect and corrected before mining was accepted.
- Step 2 mining: `mine_block` is a Godot InputMap action with a desktop mouse-button test binding. One action removes the currently targeted solid voxel immediately, adds nothing to an inventory, rebuilds the affected chunk mesh and collision, and remeshes a loaded neighbor only when the voxel lies on a chunk boundary.
- Step 2 gate: Actions run `30796342902` passed project parsing, the 128-cycle remesh runtime gate, headless scene launch and traversal, the existing graphical acceptance suite, raycast targeting, instant mining, affected collision rebuild, cross-chunk boundary remesh, screenshot capture, and crash checks. Artifact `8849045843` contains the mining screenshot and logs.
- Step 3 preflight: The original 128-cycle remesh gate toggles one block at local coordinate `(0, 0, 0)` from stone to air and back repeatedly. It validates repeated resource replacement and cleanup but does not provide positional breadth.
- Step 3 preflight: Disposable diagnostic PR #9 and Actions run `30798728839` added the missing breadth check without changing the session branch. The gate passed 26 boundary topologies—six face interiors, twelve edge interiors, and eight corners—with 13 negative-coordinate base chunks and 108 verified loaded-neighbor remesh transitions across mine and restore operations. Every neighbor changed between 30 and 36 emitted vertices, replaced its mesh resource, retained collision, and emitted no null-mesh error before the pass marker. PR #9 was closed unmerged after validation.
- Step 3 placement: `place_block` is a Godot InputMap action with right mouse as the desktop-only test binding. Placement uses the targeted hit face to select the adjacent voxel. Step 3 deliberately defaults to stone block ID 3; number-key palette selection and visible selection state remain exclusively Step 4.
- Step 3 validation: Placement rejects occupied and unloaded cells before mutation. Player clipping is prevented with an analytic capsule-versus-unit-block-AABB test using the actual capsule dimensions, collision transform, and player position rather than a keyboard/mouse-specific or approximate point check.
- Step 3 gate: Actions run `30799476997` passed project parsing, the repeated 128-cycle remesh gate, the 26-position boundary breadth gate, headless scene launch and traversal, the complete graphical world suite, face winding, targeting, mining regression, actual `place_block` InputMap input, adjacent-coordinate placement, render and collision resource replacement, a physics ray hit on the new collision, occupied-cell rejection, unloaded-chunk rejection, capsule-overlap rejection, screenshot capture, and crash checks. The placed block was stone ID 3 at `(0, 9, 0)`; overlap coordinate `(4, 11, 0)` remained air. Artifact `8850253178` has digest `sha256:066693e612fdfe5e6d48ba79d701f88532c0862f866ea0cf2abe9fcb89ac481e` and contains the reviewed placement screenshot and logs.
- Step 4 palette: `select_block_1` through `select_block_4` are Godot InputMap actions with desktop number-key bindings. They select stone ID 3, dirt ID 2, grass ID 1, and sand ID 4 respectively. Placement continues through the existing `active_placement_block_id`; the only visible state is a lightweight placeholder `CanvasLayer` label, with no inventory, item counts, hotbar model, or broader HUD system.
- Step 4 initialization: The first validation run `30802487203` exposed a scene-tree timing defect in the placeholder indicator, not in palette selection. Godot rejected adding the overlay while the parent scene was still constructing children. Overlay creation was deferred until scene setup completed, removing the error and making the indicator visible without changing the palette contract.
- Step 4 gate: Actions run `30802761616` passed project parsing, the repeated 128-cycle remesh gate, the 26-position boundary breadth gate, headless traversal, the complete graphical world suite, face winding, targeting, mining regression, placement regression, all four number-key bindings, selection IDs and names, visible current-selection text, actual placement of stone/dirt/grass/sand at four verified coordinates, screenshot capture, and crash checks. Artifact `8851539722` has digest `sha256:29213538dc3f6812f869bd3ba16713d7361c978b5060de7ba2c6bd49592eac7b` and contains the palette screenshot and logs.
- Step 5 validation design: The final gate uses an isolated two-block cross-chunk pair at `(15, 20, 0)` and `(16, 20, 0)`. Mining the first block must clear its chunk collision, replace the neighbor mesh and collision, and expose the neighbor from 30 to 36 vertices. Placing sand back must restore both chunks to 30 vertices with valid, replaced collision resources and correct physics-ray hits.
- Step 5 render-edge safety: The gate mines `(47, 20, 0)` through the actual `mine_block` InputMap action while its outward chunk `(3, 1, 0)` is unloaded, then performs 16 additional place/mine cycles. The outward chunk must remain unloaded, the loaded chunk count must remain stable, and the edge chunk must alternate cleanly between valid render/collision and empty state without a crash.
- Step 5 gate: The first run `30804500497` was rejected because the new test script had an ambiguous inferred vector type; no production code was changed. After explicit `Vector3i` typing, Actions run `30804784558` passed the full inherited suite, the Step 4 four-coordinate placement-ID regression, exact boundary mesh/collision replacement, physics-ray verification, capsule-overlap rejection at `(8, 20, 4)`, actual render-edge InputMap mining, 16 unloaded-neighbor stress cycles, screenshot capture, and crash checks. Artifact `8852342031` has digest `sha256:51d16efdd7d3d4781ea5ec0ef1115adab8444ac45ad2197098b45bd2396cb371`.

## Session: Inventory and Crafting

### Rules (in addition to all prior session rules)
1. GDScript only, one step per commit, screenshot/crash gate before marking any step complete, no Android export this session.
2. This session modifies existing systems from the Mining and Placement session — mining currently discards blocks, placement currently uses a hardcoded palette. Both get rewired to use real inventory. Do not leave the old discard/hardcoded-palette behavior running in parallel with the new system — replace it.
3. No crafting recipes beyond a single simple test recipe this session (e.g. 4 dirt → 1 stone, or similar placeholder) — full recipe design is a later session. The goal is a working crafting mechanism, not a complete recipe list.
4. No hotbar/inventory art polish — placeholder text/shapes for slots are fine.

### Steps
1. Inventory data structure: a fixed-size slot array (e.g. 20-30 slots) storing block ID + stack count per slot. Add/remove/query methods. No UI yet — verify via test assertions reading the data structure directly.
2. Wire mining into inventory: mined blocks add to inventory (existing stacking logic if a matching ID/space exists, new slot otherwise). If inventory is full, define and test the fallback (block is lost, or mining is blocked — pick one and state which).
3. Wire placement into inventory: placement consumes one item from the currently selected inventory slot instead of the old 4-key hardcoded palette. Placement fails safely if the selected slot is empty.
4. Minimal UI: on-screen hotbar showing slot contents (block type + count) and current selection, using placeholder shapes/text — no art pass. Selection via number keys or scroll, via InputMap actions.
5. Single test crafting recipe: one simple recipe (e.g. 4 dirt → 1 stone) triggered by a dedicated crafting action, consuming inputs from inventory and producing output into inventory. Verify insufficient-ingredients case fails safely.

### Definition of done
Player mines a block, sees it appear in the hotbar with correct count, places it back out of inventory (stack decrements, empties correctly at 0), and can trigger the one test recipe when they have enough ingredients, with correct consumption and output.

### Report format
Commit log in order, plus Actions run status for each step. No prose summary in place of the commit log.

### Decisions and gate evidence
- Step 1 inventory: Use 24 fixed slots with a maximum stack size of 64. Empty slots are represented canonically as block ID 0 with count 0, and all slot/snapshot queries return detached copies so callers cannot mutate inventory state indirectly.
- Step 1 mutation semantics: Additions fill existing matching stacks before opening empty slots. Add and remove operations are transactional: insufficient capacity or quantity returns `false` and leaves every slot unchanged; reaching count 0 resets the slot to the canonical empty representation.
- Step 1 full-capacity scope: The inventory data structure rejects an item that cannot fit and performs no partial write. The player-facing mining fallback is intentionally not chosen or wired here because that belongs to Step 2, where mining and inventory become one transaction.
- Step 1 gate: Actions run `30810984833` passed the complete inherited parse, remesh, headless, graphical, mining, placement, palette, and edge-case suite plus direct inventory assertions for add/remove/query, stack spillover, snapshot isolation, atomic failure, zero-count clearing, and the full-inventory case. The 1280x720 inventory screenshot was captured and reviewed with no graphical crash. Artifact `8854805411` has digest `sha256:645647655ec11d8db810985b4b856815d740b76dfb63fbba9127c833979e9366`.
- Step 2 mining transaction: The player owns the accepted 24-slot, 64-item-stack inventory. Mining reads the targeted voxel's actual block ID, preflights capacity, removes the voxel, then adds exactly one item; a defensive rollback restores the voxel if the inventory write unexpectedly fails.
- Step 2 full-inventory fallback: Choose **mining is blocked**, not block loss. When all 24 slots are full and the mined block cannot fit, the mine action returns without changing the voxel, inventory snapshot, chunk mesh, chunk collision, or current target.
- Step 2 gate: Actions run `30818431108` passed the complete inherited suite and the real `mine_block` InputMap integration gate. Direct inventory assertions verified dirt `63+1` filled slot 0 to 64, sand opened slot 1, all 24 slots filled to 64, the full-inventory mine attempt was blocked with voxel/inventory/mesh/collision unchanged, and mining resumed after freeing slot 23, collecting one grass block. The reviewed 1280x720 screenshot and logs contain no Step 2 script error or crash. Artifact `8857830334` has digest `sha256:6b7667b8fb83f6335f835440bf9fb38c8da05e39a7d1a14bc53d4ed3f21d3fac`.
- Step 3 placement transaction: Runtime placement reads only the currently selected zero-based inventory slot. A successful placement writes that slot's block ID, removes exactly one item, and canonicalizes the slot to block ID 0/count 0 at depletion; a defensive rollback restores the world cell to air if item removal unexpectedly fails.
- Step 3 palette replacement: The legacy hardcoded four-block number-key actions, palette overlay runtime path, and palette-only acceptance gate are retired. Step 4 owns new InputMap slot-selection actions and the visible hotbar; Step 3 exposes programmatic slot selection only.
- Step 3 gate: Actions run `30820741042` passed the complete inherited suite plus the real `place_block` InputMap integration gate. Stone in selected slot 0 was consumed `2->1->air/0`; dirt remained in slot 1 while selected slot 0 was empty. The selected-empty-slot action attempt left the world voxel, inventory snapshot, chunk mesh, chunk collision, and current target unchanged, then selecting slot 1 allowed a successful dirt placement and cleared it to air/0. The reviewed 1280x720 screenshot shows the three placements with no legacy palette overlay or graphical crash. Artifact `8858807002` has digest `sha256:d5b5735295d735fed5b9909c860ae607541691fe5338f6415d8c6e8ee40c6d35`.
- Step 4 hotbar: Render inventory slots 0-8 as a nine-slot bottom hotbar while retaining the accepted 24-slot inventory. Each visible panel shows its 1-based key number, block type, and count; the selected slot uses a thicker highlighted border. Number keys 1-9 and mouse-wheel previous/next are InputMap actions.
- Step 4 refresh correction: Actions run `30822881300` was rejected after the inherited graphical gate reported a jump-timing failure while the first implementation rebuilt all nine labels and styles every frame. Hotbar refresh was changed to an inventory `changed` signal emitted only after successful mutations, plus explicit refresh on selection, removing the per-frame UI work without changing inventory semantics.
- Step 4 gate: Actions run `30823133143` passed the complete inherited suite plus direct inspection of the rendered Control tree. The gate read exact visible label text (`STONE x2`, `DIRT x5` then `x3`, `GRASS x1`, and `EMPTY x0`), verified selected/non-selected panel border widths, confirmed every panel and label and the 1008x92 hotbar rectangle were inside the 1280x720 viewport, and drove `select_hotbar_2`, wheel-next, and wheel-previous through InputMap. The reviewed screenshot visibly shows nine slots with slot 2 selected and no clipping or graphical crash. Artifact `8859762628` has digest `sha256:012c65ae0b9a6bed7070c8e71c2a3631c47e8b8c8c81239c5f9ca59bb7786125`.
- Step 4 inherited gate correction: Documentation-head run `30823690581` reproduced the jump failure after per-frame UI work was already removed, confirming an existing coroutine-order race in the acceptance harness rather than a hotbar runtime failure. The jump gate still requires more than 0.05 units of vertical rise, but now holds the InputMap action across two physics frames and observes that unchanged threshold for at most 12 physics frames before failing.
- Step 4 inherited input root cause: Runs `30824075898` and `30824376253` showed that extending the observation window and invoking the callback directly did not make frame-local `Input.is_action_just_pressed()` deterministic. The controller now samples the held `jump` InputMap action with a per-press edge latch, preserving exactly one jump per press while avoiding render-frame timing dependence; the gate still requires positive upward velocity and more than 0.05 units of vertical rise.
- Step 4 accepted correction gate: Actions run `30824644817` passed the complete inherited suite and rendered hotbar gate after the jump latch correction. Artifact `8860378015` has digest `sha256:c011526292250162518f318c022cfb685dd0c6486e75328adcbc81f9c61896a9`.
- Step 4 reachability gap: Player input currently selects only inventory slots 0-8 through the nine-slot hotbar. Slots 9-23 remain valid real inventory capacity used by mining, stacking, fullness checks, and crafting, but are intentionally not selectable until a later full-inventory screen/session.
- Step 5 recipe and action: The sole recipe is 4 dirt -> 1 stone, triggered by the `craft_test_recipe` InputMap action with physical key C as the desktop test binding. No recipe list, crafting UI, or additional recipes are added this session.
- Step 5 transaction semantics: Crafting duplicates all 24 slots, removes recipe inputs from the staged copy, inserts the output using normal matching-stack-first rules, and commits only when both operations complete. Insufficient ingredients or output capacity returns `false`, emits no inventory change signal, and preserves every slot exactly.
- Step 5 rejected gate: Actions run `30826752770` was rejected because the new test script had two ambiguous inferred integer types. Production scripts parsed and every inherited gate passed; adding explicit `int` annotations corrected only the gate script and did not change recipe behavior.
- Step 5 gate: Actions run `30827021640` passed the complete inherited suite plus the actual crafting-action gate. With 3 dirt, pressing `craft_test_recipe` left all 24 slots and rendered hotbar text unchanged. With 4 dirt and a 63-stone stack, the same action consumed dirt `4->0`, canonicalized its slot to air/0, stacked stone `63->64`, left slots 2-23 unchanged, refreshed the rendered hotbar, captured a valid 1280x720 screenshot, and completed without a crash. Artifact `8861353266` has digest `sha256:41019da1eb60107ea58b59012420b62462cf0750704fb2cd749ccb04e6e0025a`.

## Session: Touch Controls and Android Export

### Rules (in addition to all prior session rules)
1. GDScript only, one step per commit, screenshot/crash gate before marking any step complete.
2. All existing gameplay (movement, mining, placement, hotbar, crafting) already routes through InputMap actions — do not rewrite that logic. This session adds a touch input source that drives the same InputMap actions, alongside keyboard/mouse, not instead of it. Desktop testing must keep working after this session.
3. This is the first Android export attempt for this project. Expect and report real friction honestly — do not silently work around export failures.

### Steps
1. Virtual joystick (left side of screen): touch-drag emits the same move_forward/back/left/right actions as WASD currently does. Test via simulated touch input, not just visual placement.
2. Drag-look (right side of screen): touch-drag emits the same look input as mouse-look currently does, including the existing pitch clamp. Test via simulated touch input.
3. Touch buttons: jump, mine, place, craft — each fires the exact same InputMap action as its current keyboard/mouse binding. Hotbar slot selection (0-8) as tappable on-screen buttons, replacing/supplementing number-key input.
4. Android export setup: Android export template, debug keystore signing, correct ARM64 target, minimum API level appropriate for the "mid-range Android phone" target from the original design doc. Report the exact export settings used.
5. Export the APK from this session's completed branch (after steps 1-4 are gated and merged). Confirm it installs and launches on a real device if you have any way to verify that, or state plainly if you cannot and this needs manual verification on Akila's end.

### Definition of done
An APK that installs on Android, shows the touch joystick and buttons on screen, and allows walking, looking, mining, placing, hotbar selection, and crafting entirely via touch, with no keyboard/mouse required.

### Report format
Commit log in order, plus Actions run status for each step. State plainly which parts (if any) could only be verified via desktop touch-simulation and not on a real device, since that gap matters before Akila installs it.
