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
