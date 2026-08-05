# Current World Generation

This document describes the world generator that currently drives the Android/mobile TEKNIK 0.1 build.

It documents the existing implementation. It is not a specification for the future biome system.

## Active Generator

The active mobile path consists of:

```text
playable_world_port.gd
        -> playable_world_runtime.gd
        -> playable_world_data.gd
        -> playable_world_mesher.gd
```

`localized_water_bodies.gd` creates water surfaces separately.

## Deterministic World

The world uses a fixed integer seed:

```text
734921
```

The same seed and world coordinates produce the same:

- Terrain heights.
- Terrain layers.
- Tree positions.
- Tree blocks.

The base terrain is generated when needed rather than stored permanently.

## World Dimensions

Current active mobile values:

| Property | Value |
|---|---:|
| World height | 30 blocks |
| Minimum generated height | 3 |
| Maximum generated height | 27 |
| Sea level | 7 |
| Horizontal chunk size | 12 x 12 blocks |
| Height covered by one chunk | Full 30-block world height |
| Render radius | 3 chunks |
| Visible square | Up to 7 x 7 chunks |
| Collision radius | 1 chunk |
| Unload radius | 4 chunks |
| Height-cache padding | 2 blocks around each chunk |

The world can be sampled at positive or negative horizontal coordinates.

## Terrain Height

Two `FastNoiseLite` fields are used.

### Height Noise

- Seed: world seed.
- Frequency: `0.011`.
- Fractal octaves: `4`.
- Fractal gain: `0.48`.
- Fractal lacunarity: `2.05`.

### Region Noise

- Seed: world seed XOR `0x5f3759df`.
- Frequency: `0.0035`.
- Fractal octaves: `2`.

The height formula is:

```text
round(10.0 + height_noise * 6.4 + region_noise * 3.0)
```

The result is clamped between 3 and 27.

Despite its name, `region_noise` does not currently choose biomes. It only adds broad terrain-height variation.

## Terrain Layers

For each `x, z` column, the generator calculates one surface height.

### Low Terrain

When the surface height is at or below `SEA_LEVEL + 1`:

- Surface: sand.
- Next three blocks: sand.
- Deeper blocks: stone.

### Normal Land

When the surface is above `SEA_LEVEL + 1`:

- Surface: grass.
- Next three blocks: dirt.
- Deeper blocks: stone.

Everything above the surface is air unless a generated tree occupies the cell.

Coordinates below world `y = 0` resolve as stone. Coordinates at or above world height resolve as air.

## Trees

Current tree generation is deterministic and grid-based.

Constants:

| Property | Value |
|---|---:|
| Candidate grid spacing | 7 blocks |
| Candidate grid offset | 3 |
| Trunk height | 4 blocks |
| Canopy radius | 1 block |

A tree candidate exists only where:

```text
x mod 7 = 3
z mod 7 = 3
```

Candidates are rejected when:

- The surface is too close to sea level.
- The tree would exceed world height.
- The coordinate hash rejects the candidate.

The coordinate hash uses the world seed and fixed integer multipliers. Approximately one quarter of valid grid candidates are rejected.

A generated tree contains:

- One vertical four-block log trunk above the surface.
- Leaves around the top in a compact three-level canopy.

Because candidates come from a seven-block grid, tree spacing may look more regular than natural vegetation.

## Water

Water is not part of the solid block array.

A separate mesh is created at:

```text
SEA_LEVEL + 0.54
```

A water surface is added when:

- Terrain height at the column is below sea level.
- At least two of the four horizontal neighbouring columns are also below sea level.

This rule avoids many isolated single-column puddles. It does not implement rivers, fluid flow, water depth blocks, or swimming.

## Chunk Generation

When the player enters a new horizontal chunk:

1. The runtime calculates the desired 7 x 7 render area.
2. Missing chunk coordinates are queued.
3. Chunks closer to the player and chunks needing collision are prioritized.
4. The runtime builds a padded terrain-height cache.
5. The mesher builds a padded block cache.
6. The mesher creates visible face arrays.
7. The runtime creates an `ArrayMesh`.
8. Collision is created only within the smaller collision radius.
9. Chunks beyond the unload radius are removed.

The runtime processes chunk work within an approximate per-frame budget of 5.5 milliseconds.

## Block Lookup Order

For a world cell, block lookup follows this order:

1. Below zero: stone.
2. At or above world height: air.
3. Saved override exists: return override block ID.
4. Cell is at or below generated surface: return terrain layer.
5. Cell is above terrain and belongs to a generated tree: return log or leaves.
6. Otherwise: air.

Saved overrides therefore take priority over generated terrain and trees.

## Meshing

The mesher processes every possible cell inside the chunk.

For each solid block:

- Check six adjacent cells.
- Skip any face whose neighbour is not air.
- Emit four vertices for each visible face.
- Emit normals, vertex colours, and triangle indices.

Cross-chunk cache padding allows faces and lighting near chunk boundaries to sample neighbouring generated blocks.

## Voxel Lighting

### Directional Face Brightness

- Top: `1.0`.
- Bottom: `0.5`.
- East/west pair: `0.6`.
- North/south pair: `0.8`.

### Ambient Occlusion

Each face corner samples two side neighbours and one diagonal neighbour outside the visible face.

The four brightness levels are:

```text
0.55, 0.70, 0.85, 1.0
```

When both side neighbours occlude the corner, the darkest level is used.

The face diagonal is selected from the AO values to reduce visible interpolation seams.

### Skylight

Skylight starts at level 15 above each cached column and scans downward.

- Air preserves the current light level.
- Leaves reduce the light level by one.
- Other solid blocks set the level to zero below them.

Four nearby skylight samples are averaged per face vertex. A minimum brightness floor of `0.35` keeps enclosed surfaces readable.

## World Edits

Mining and placement call `set_block()` in the world data model.

Each edit is stored as:

```text
"x,y,z": block_id
```

Air has block ID `0`, so mined blocks are represented as air overrides.

Edits schedule the owning chunk for rebuild. Edits near chunk boundaries also schedule affected neighbouring chunks.

Repeated edits are debounced and coalesced before rebuilding.

## Save File

Current path:

```text
user://teknik_world_v1.json
```

Stored structure:

```json
{
  "version": 1,
  "seed": 734921,
  "overrides": {
    "x,y,z": 0
  }
}
```

The save is written after a short dirty delay and during world shutdown when unsaved edits remain.

## Current Generator Limitations

- One surface height per `x, z` column.
- No caves or overhangs.
- No production biome classification.
- No rivers or drainage simulation.
- No ores or underground features.
- No world-seed selection.
- No generator-version migration.
- Limited vertical space.
- Grid-based tree distribution.
- Water is a separate flat visual surface.

Any incompatible generator change must account for existing coordinate overrides before it is used for persistent player worlds.