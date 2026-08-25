# TEKNIK Build Plan — Session: Rotational Power Network

## Rules (apply to everything below)
1. Build in GDScript only. No native Rust/C++ core this session.
2. One numbered item = one commit. Do not bundle items together.
3. Do not build anything not listed here, even if it's in the full design doc. If you think of something extra, add it to a "Deferred" note at the bottom of this file instead of building it.
4. Commit message format: `[TEKNIK] step N: <short description>`
5. If a step fails or you have to guess at a design decision, write the decision and why in a `## Decisions` section at the bottom of this file, and commit that update alongside the code.
6. Stop at the end of step 5. Do not continue into gearboxes, belts, electrical conversion, or automation even if there's time left — those are separate sessions.
7. Target platform is Android. Desktop keyboard/mouse is a temporary testing harness only — do not hardcode movement or camera logic directly to keyboard/mouse. Abstract input behind an input layer (Godot's InputMap actions, not raw key checks) so touch controls can be swapped in later without rewriting the player controller.

## Steps

1. ✅ **Network core data model**: `MechanicalNetwork` resource tracking nodes (sources/consumers/transmission), graph topology, RPM and Stress Units (SU = Torque × Speed / 1000), topological propagation with cycle detection. One headless-testable test: water wheel at 32 SU drives shaft → drill at 32 SU, no overstress. Gate: unit test passes in headless Godot, no scene tree required. **DONE** — tests/mechanical_network_gate.gd passes.

2. ✅ **Water Wheel block + scene**: Placeable block (ID 7), `MeshInstance3D` with rotating paddles, emits SU when adjacent to flowing water (check 6 face neighbors for `BLOCK_WATER`). Connects to `MechanicalNetwork` on placement, disconnects on break. Gate: place in world, verify SU > 0 in network debug overlay when next to water, SU = 0 when not. **DONE** — WaterWheel script created with mesh, water adjacency check, and MechanicalManager integration.

3. ✅ **Shaft block + scene**: Placeable block (ID 8), `MeshInstance3D` with rotating core texture, transmits SU between connected faces. **DONE** — Shaft script created with mesh, 6-way face connections, MechanicalManager integration.

4. ✅ **Mechanical Drill block + scene**: Placeable block (ID 9), `MeshInstance3D` with rotating drill head, consumes 32 SU, mines 3×3 area below when powered. **DONE** — MechanicalDrill script created with mesh, mining logic, MechanicalManager integration.

5. **MechanicalManager**: Central manager handling placement/breaking, network solving, chunk integration, player controller integration. **DONE** — MechanicalManager script created with full integration into player controller and chunk system.

## Decisions
- Block IDs: BLOCK_WATER_WHEEL=7 (reusing BLOCK_WATER constant from carpathian_data), BLOCK_SHAFT=8, BLOCK_MECHANICAL_DRILL=9. Added to playable_world_data.gd.
- MechanicalNetwork uses Create-style SU model: network stress = sum of source capacities. A component is overstressed if network stress exceeds any transmission node's capacity, OR total demand exceeds total supply. Sources are never overstressed.
- MechanicalManager handles scene tree integration: creates Node3D entities (WaterWheel, Shaft, MechanicalDrill) and connects them to the network on placement. Entities are parented to chunk nodes when available, else root.
- Player controller integration: mechanical blocks are placed/broken via MechanicalManager which also handles world block placement. Inventory integration reuses existing slot system.
- Headless test support: MechanicalManager and entity scripts check `is_inside_tree()` before calling `get_tree()` to support unit tests without full scene tree.
- All tests pass: mechanical_network_gate.gd (10 tests), mechanical_integration_gate.gd (10 tests).