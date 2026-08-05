# Architecture

TEKNIK 0.1 is a Godot 4 voxel sandbox prototype with a shared scene and two world-generation paths:

- An optimized mobile/Android playable-world runtime.
- An older desktop-oriented voxel chunk system retained in the repository.

The active path is selected at runtime by `playable_world_port.gd`.

## Main Scene

The project starts from:

```text
res://scenes/main.tscn
```

Important scene nodes include:

- `WorldEnvironment`: procedural sky and ambient environment.
- `Sun`: directional light with real shadow maps disabled.
- `Player`: first-person character controller with inventory integration.
- `TargetHighlight`: selected-block overlay.
- `ChunkManager`: world streaming entry point.
- `LocalizedWaterBodies`: mobile water surface generation.
- `TouchControls`: movement joystick and drag-to-look input.
- `TouchActionControls`: jump, mine, place, craft, and hotbar touch input.
- `MobileCameraSensitivity`: mobile look configuration.

## World Runtime Selection

`scripts/world/playable_world_port.gd` extends the legacy `chunk_manager.gd` and chooses the runtime path.

The optimized playable-world port activates when:

- The build has the `mobile` feature.
- The build has the `android` feature.
- `force_playable_world_port` is enabled for testing.

When the port is inactive, calls are forwarded to the inherited legacy chunk manager.

When the port is active, it creates `PlayableWorldRuntime` and delegates world operations to it.

## Active Mobile World Path

### `playable_world_data.gd`

Owns deterministic world data and saved edits.

Responsibilities:

- Configures terrain noise from the fixed world seed.
- Calculates the terrain height for any world `x, z` coordinate.
- Resolves generated terrain block types.
- Generates deterministic tree blocks.
- Stores block-edit overrides.
- Saves and loads the override dictionary.

Current core values:

- World seed: `734921`.
- World height: `30`.
- Sea level: `7`.
- Tree spacing: `7` blocks.
- Tree trunk height: `4` blocks.

The base world is not stored block-by-block. It is recalculated from the seed and coordinates, then modified by overrides.

### `playable_world_runtime.gd`

Owns chunk streaming, mesh commits, collision management, and edit rebuild scheduling.

Current mobile runtime configuration:

- Horizontal chunk size: `12 x 12` blocks.
- Render radius: `3` chunks.
- Maximum visible square: `7 x 7`, or 49 chunks.
- Collision radius: `1` chunk from the player.
- Unload radius: `4` chunks.
- Per-frame build budget: approximately `5.5 ms`.
- Edit rebuild debounce: `75 ms`.

Main responsibilities:

1. Convert player positions and world cells to horizontal chunk coordinates.
2. Queue missing chunks nearest-first.
3. Build height caches with cross-chunk padding.
4. Ask the mesher to create packed vertex data.
5. Commit `ArrayMesh` resources to the scene tree.
6. Add collision only near the player.
7. Unload distant chunks.
8. Coalesce block edits before remeshing.
9. Place the player after the nearby collision ring is ready.
10. Save dirty world overrides after a delay or during shutdown.

The mobile runtime performs budgeted synchronous generation rather than using the legacy worker-thread remesh pipeline.

### `playable_world_mesher.gd`

Converts generated block data into renderable mesh arrays.

The mesher:

- Builds a padded block cache for the chunk and neighbours.
- Builds a vertical skylight cache.
- Visits every block in the chunk.
- Skips air blocks.
- Emits a face only when the adjacent block is air.
- Writes vertices, normals, vertex colours, and indices.
- Selects face diagonals based on corner ambient occlusion.
- Applies block colour variation and classic face lighting.

The runtime then creates one indexed `ArrayMesh` surface from these arrays.

### `localized_water_bodies.gd`

Creates water as separate flat mesh surfaces.

A column is considered a water column when:

- Terrain height is below sea level.
- At least two horizontal neighbours are also below sea level.

Water chunks follow the same horizontal streaming area as the active mobile world.

## Legacy Desktop World Path

The older path is centered around:

- `scripts/world/chunk_manager.gd`
- `scripts/world/chunk.gd`
- `scripts/world/chunk_mesher.gd`
- `scripts/world/threaded_chunk_mesher.gd`
- `scripts/world/biome_probe.gd`

Characteristics:

- Uses `16 x 16 x 16` voxel chunks.
- Streams in three dimensions around the player.
- Stores block data per chunk.
- Includes primitive plains, forest, and desert column metadata.
- Uses background worker tasks for remeshing.
- Applies completed mesh results on the main thread.

This path is not the source of the terrain seen in the current Android APK. New mobile world-generation work must target the playable-world data/runtime/mesher path unless the architecture is deliberately consolidated.

## Player and Interaction Architecture

### `first_person_controller.gd`

Provides:

- Movement and gravity.
- Mouse and action-based look.
- Camera pitch clamping.
- Block ray targeting.
- Target highlighting.
- Mining and placement hooks.
- Player-overlap rejection during placement.

### `inventory_first_person_controller.gd`

Extends the base controller and adds transactional inventory behaviour.

It:

- Owns the `BlockInventory` model.
- Configures the hotbar and inventory screen.
- Adds mined blocks to inventory.
- Consumes selected blocks during placement.
- Rolls back world edits when an inventory transaction fails.
- Locks movement, looking, mining, and placement while inventory is open.

## Inventory Architecture

### `block_inventory.gd`

The inventory model owns 36 slot dictionaries containing:

```gdscript
{
    "block_id": int,
    "count": int,
}
```

It handles:

- Stack merging.
- Empty-slot allocation.
- Capacity checks.
- Item removal.
- Full-stack pickup.
- Stack splitting.
- Single-item placement.
- Stack swapping.
- Atomic test crafting.

### UI

- `inventory_hotbar.gd`: renders the active nine slots.
- `minecraft_inventory_screen.gd`: renders 27 storage slots plus the nine-slot hotbar and manages cursor-stack interaction.
- `touch_action_controls.gd`: overlays touch hit areas over hotbar slots and action buttons.

## Input Architecture

All gameplay input is routed through Godot's `InputMap`.

Desktop devices emit keyboard and mouse actions. Touch controls emit the same named actions explicitly, allowing the player controller to remain input-device independent.

Touch-to-mouse emulation is disabled to prevent movement or camera touches from entering the desktop mouse-look path.

## Lighting Architecture

The playable mobile material is unshaded and uses vertex colours as the final visible lighting signal.

Lighting components:

- Fixed directional face brightness.
- Four-level vertex ambient occlusion.
- Vertical skylight from level 15 to 0.
- One-level skylight reduction through each leaf block.
- Minimum brightness floor for readability.

The main directional light remains available for the environment, but its shadow maps are disabled. This avoids expensive mobile shadow rendering and prevents it from conflicting with the voxel-lighting model.

## Persistence Model

The active mobile world save is:

```text
user://teknik_world_v1.json
```

The save contains:

- Save format version.
- World seed.
- Coordinate-keyed block overrides.

A coordinate key uses this format:

```text
x,y,z
```

The save currently does not contain player position, inventory contents, or chunk meshes.

## Threading and Scene-Tree Safety

The legacy remesh path performs mesh-data computation through Godot's worker thread pool and applies scene changes on the main thread.

The active mobile path uses a strict per-frame CPU budget and performs scene-tree and resource operations on the main thread. Any future threading work must keep these boundaries:

- Worker-safe: numeric generation, block arrays, packed mesh arrays.
- Main-thread only: adding/removing nodes, assigning mesh instances, creating or swapping collisions.

## Known Architectural Debt

- Two separate world-generation systems remain in the repository.
- The mobile world uses one horizontal chunk covering the full 30-block height.
- Inventory and player state are not yet persisted.
- Water is a separate visual surface system rather than a voxel/fluid system.
- The fixed generator seed and save version limit world-creation flexibility.
- Biome work must be implemented in the active mobile path, not only in the legacy chunk metadata.