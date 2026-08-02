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
