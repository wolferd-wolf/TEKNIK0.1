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
