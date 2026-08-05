# Gameplay

This document describes the gameplay that is implemented in the current TEKNIK 0.1 prototype. It is not a design promise for unfinished systems.

## Core Loop

The current playable loop is:

1. Explore the streamed procedural world.
2. Aim at a block within interaction range.
3. Mine the block and collect it into the inventory.
4. Select a block stack in the hotbar.
5. Place blocks to alter the terrain or build structures.
6. Reopen the inventory to move and split stacks.

There are currently no enemies, health, hunger, tools, durability, or progression systems.

## Block Types

The active mobile world currently uses these block IDs:

| ID | Block |
|---:|---|
| 0 | Air |
| 1 | Grass |
| 2 | Dirt |
| 3 | Stone |
| 4 | Sand |
| 5 | Log |
| 6 | Leaves |

Grass, dirt, stone, and sand can be stored and placed through the current inventory path. Trees use log and leaf blocks as generated world content.

## Movement

The player uses a first-person capsule controller with:

- Walking and air acceleration.
- Gravity and jumping.
- Horizontal body rotation and clamped camera pitch.
- Collision against nearby chunk meshes.
- Recovery above the generated terrain when required by the mobile world runtime.

### Desktop Movement

- `W`, `A`, `S`, `D`: move.
- Mouse: look.
- `Space`: jump.

### Touch Movement

- Left virtual joystick: movement.
- Drag in the upper-right gameplay area: look.
- `JUMP`: jump.

The lower-right area is reserved for action buttons and the hotbar, preventing look touches from conflicting with gameplay controls.

## Block Targeting

The camera casts a ray up to six blocks forward. A translucent highlight appears around the targeted solid block.

The target stores:

- The world block coordinate.
- The face that was hit.

Placement occurs in the empty cell immediately outside the hit face. Placement is rejected when:

- The destination already contains a block.
- The destination overlaps the player's collision capsule.
- The selected hotbar slot is empty.
- The runtime refuses the edit.

## Mining

### Desktop

Use the left mouse button.

### Touch

Use the `MINE` button.

Successful mining:

1. Checks that the targeted block exists.
2. Checks that the inventory can accept the block.
3. Removes the block from the world.
4. Adds one item of that block type to the inventory.
5. Rolls the world edit back if the inventory transaction unexpectedly fails.

When all 36 inventory slots are full and no existing stack has capacity, mining is blocked and the voxel remains unchanged.

## Placement

### Desktop

Use the right mouse button.

### Touch

Use the `PLACE` button.

Successful placement:

1. Reads the selected hotbar stack.
2. Validates the destination.
3. Places the selected block ID.
4. Removes one item from the selected stack.
5. Rolls the placed block back if inventory removal unexpectedly fails.

## Hotbar

The first nine inventory slots form the hotbar.

### Desktop

- Keys `1` through `9`: select a slot.
- Mouse wheel: select the previous or next slot.

### Touch

Tap one of the nine on-screen hotbar slots.

## Inventory

The current inventory layout contains:

- 9 hotbar slots.
- 27 storage slots.
- 36 slots total.
- Maximum stack size of 64.

### Opening the Inventory

- Desktop: press `E`.
- Touch: tap the `INVENTORY` button.

Opening the inventory:

- Stops player movement.
- Releases gameplay input actions.
- Disables mining, placement, and camera look.
- Shows the mouse cursor on desktop.

### Stack Interaction

Primary interaction:

- Pick up a full stack from a slot.
- Place a carried stack into an empty slot.
- Merge carried items into a matching stack.
- Swap the carried stack with a different compatible slot stack.

Secondary interaction:

- Desktop: right-click a slot.
- Touch: long-press a slot for approximately 0.45 seconds.

Secondary interaction splits a stack when the cursor is empty, or places one carried item into the target slot.

The inventory cannot close while it is carrying a stack that cannot be returned safely to available inventory capacity.

## Crafting Test

The current `CRAFT` action is an acceptance-test implementation, not a final crafting interface.

```text
4 Dirt -> 1 Stone
```

- Desktop: press `C`.
- Touch: tap `CRAFT`.

The transaction succeeds only when the required input exists and the output can fit in the inventory.

## World Persistence

The generated base world is deterministic. Player block edits are stored as coordinate overrides in:

```text
user://teknik_world_v1.json
```

On load, TEKNIK regenerates the base terrain and applies the saved overrides.

Currently saved:

- Mined block coordinates.
- Placed block coordinates and block IDs.

Currently not saved:

- Inventory contents.
- Selected hotbar slot.
- Player position.

## Water

Water is currently visual terrain support rather than a complete gameplay system.

- Water surfaces appear over connected low terrain below sea level.
- Water is rendered as localized flat meshes.
- Water is not currently a mineable block.
- Swimming, currents, fluid spreading, and underwater gameplay are not implemented.

## Lighting

The visible voxel mesh uses classic game-style lighting rather than real-time directional shadow maps:

- Top faces are brightest.
- Bottom and side faces receive fixed directional dimming.
- Face corners receive ambient-occlusion levels from neighbouring blocks.
- Skylight is evaluated vertically.
- Leaves reduce passing skylight gradually.

This keeps the block forms readable while remaining suitable for the mobile target.