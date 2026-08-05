# Mobile-Only World Consolidation — Step 4 Acceptance

## Rule compliance

- Scope is validation only; no new gameplay or world-generation feature is added.
- This is the single Step 4 commit.
- The tested world implementation is the same `playable_world_*` runtime used by Android, desktop, and headless execution.

## Consolidated acceptance coverage

The main acceptance workflow validates:

1. Godot 4.3 strict project parsing after removal of the retired desktop chunk system.
2. The surviving playable-world runtime through `tests/playable_world_mining_port_gate.gd`:
   - always-active single-world adapter;
   - deterministic varied terrain;
   - 7x7 bounded visual streaming target;
   - 3x3 collision-first startup readiness;
   - solid surface block lookup;
   - mining mutation to air;
   - atomic affected-chunk replacement;
   - collision preservation after replacement;
   - zero atomic-swap failures.
3. The shared standalone inventory model through `tests/inventory_step1_gate.gd`:
   - 24 slots;
   - 64-item stack limit;
   - stacking and spillover;
   - removal and canonical empty slots;
   - full-inventory atomic failure;
   - snapshot isolation.

## Consolidation assertions

- `scenes/main.tscn` points to `scripts/world/playable_world_port.gd`.
- `playable_world_port.gd` is standalone and does not inherit or conditionally fall back to the retired manager.
- The retired `chunk.gd`, `chunk_manager.gd`, `chunk_mesher.gd`, and `threaded_chunk_mesher.gd` implementations are absent.
- Dedicated threaded-remesh workflows and old-world diagnostic gates are absent.
- Shared player, inventory, crafting, hotbar, touch-control, camera, and Android export systems remain in the repository.

## Step 4 gate

Step 4 is complete only when the exact commit carrying this document receives `TEKNIK Acceptance Gate: success` from `.github/workflows/acceptance-gate.yml`.
