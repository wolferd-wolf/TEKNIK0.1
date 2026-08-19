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

1. **Network core data model**: `MechanicalNetwork` resource tracking nodes (sources/consumers/transmission), graph topology, RPM and Stress Units (SU = Torque × Speed / 1000), topological propagation with cycle detection. One headless-testable test: water wheel at 32 SU drives shaft → drill at 32 SU, no overstress. Gate: unit test passes in headless Godot, no scene tree required.

2. **Water Wheel block + scene**: Placeable block (ID 7), `MeshInstance3D` with rotating paddles, emits SU when adjacent to flowing water (check 6 face neighbors for `BLOCK_WATER`). Connects to `MechanicalNetwork` on placement, disconnects on break. Gate: place in world, verify SU > 0 in network debug overlay when next to water, SU = 0 when not.

3. **Shaft block + scene**: Placeable block (ID 8), `MeshInstance3D` with rotating core texture, transmits SU between connected faces (6-way). Connects to network on placement. Gate: chain of 5 shafts transmits SU from water wheel to drill with no loss.

4. **Mechanical Drill block + scene**: Placeable block (ID 9), `MeshInstance3D` with rotating drill head, consumes 32 SU, mines 3×3 area below it once per rotation tick (1 second at 1 RPM). Gate: powered drill mines stone/dirt/sand, drops items into inventory (via existing `mine_block_world` path), stops when network SU < 32.

5. **Network debug overlay**: `CanvasLayer` toggle (F3) showing per-node SU, RPM, connections, overstress warnings. Gate: overlay shows correct values for water wheel → shaft chain → drill setup.

## Definition of done
Player can place a water wheel in flowing water, connect shafts to a mechanical drill, and the drill mines a 3×3 hole below it, with visible rotation on all three blocks and correct SU values in the debug overlay. No crashes on placement, breakage, or network reconnection.

## Report format
When done, list the commits (hash + message) in order. Do not summarize in prose — the commit log is the report.

## Decisions
-