# Project Status

TEKNIK 0.1 is an early playable voxel sandbox prototype. It has a stable core interaction loop, but it is not yet a complete game or public release.

## Implemented

### World

- Deterministic procedural terrain.
- Streamed chunks around the player.
- Grass, dirt, stone, sand, logs, and leaves.
- Deterministic trees.
- Localized water surfaces.
- Saved mined and placed block overrides.
- Nearby collision generation.
- Distant chunk unloading.

### Rendering

- Hidden-face culling.
- Indexed procedural chunk meshes.
- Back-face culling.
- Directional voxel face shading.
- Vertex ambient occlusion.
- Vertical skylight.
- Skylight attenuation through leaves.
- Mobile-oriented unshaded vertex-colour material.

### Player

- First-person movement.
- Mouse and touch camera control.
- Jumping and gravity.
- Block targeting and highlighting.
- Mining.
- Placement.
- Placement collision rejection against the player.

### Inventory

- 36 slots.
- Nine-slot hotbar.
- 27 storage slots.
- Stack size of 64.
- Mining pickup.
- Placement consumption.
- Full-inventory mining rejection.
- Stack pickup, merging, swapping, and splitting.
- Desktop and touch inventory interaction.
- Temporary crafting transaction test.

### Mobile

- Android touch joystick.
- Drag-to-look.
- Jump, mine, place, and craft buttons.
- Touch hotbar selection.
- Touch inventory toggle and long-press interaction.
- ARM64 Gradle export configuration.
- Manual GitHub Actions debug APK export.

### Validation

- Godot parse checks.
- Feature-specific acceptance scripts.
- Inventory regression gates.
- Remesh diagnostics in the world systems.
- Android artifact logging and signature verification.

## Current Technical Baseline

- Engine automation target: Godot 4.3 stable.
- Renderer: Compatibility.
- Android minimum SDK: 24.
- Android target SDK: 34.
- Android architecture: ARM64.
- Active mobile chunk size: 12 x 12 x 30.
- Active mobile render radius: 3 chunks.
- Active mobile collision radius: 1 chunk.
- Active world seed: fixed.
- Save format: generated world plus block overrides.

## Not Implemented

The following systems are not currently part of the game:

- Production biome generation.
- Caves and underground terrain systems.
- Ores and mining tools.
- Multiple world seeds or a world-creation screen.
- World-generator version migration.
- Inventory persistence.
- Player-position persistence.
- Texture atlas and finished art direction.
- Audio and music.
- Mobs, wildlife, or enemies.
- Health, hunger, armour, or combat.
- Tool durability.
- Production crafting recipes or crafting UI.
- Furnaces or processing systems.
- Structures, villages, ruins, or dungeons.
- Fluid simulation or swimming.
- Day/night cycle.
- Weather.
- Multiplayer.
- Public release signing and store distribution.

## Immediate Product Direction

The next major area under consideration is world quality:

- Better large-scale terrain regions.
- Biomes driven by multiple deterministic climate fields.
- Biome-specific surface blocks and vegetation.
- More natural tree placement.
- Water improvements.
- Caves only after the surface generator is stable.

These items are direction, not completed functionality.

## Known Risks

### Dual World Systems

The repository contains both the active mobile playable-world runtime and an older desktop chunk system. Features added to only one path may not appear on the other platform.

### Save Compatibility

Changing terrain generation can move the generated blocks beneath existing coordinate overrides. A generator-version strategy is required before incompatible world changes are released broadly.

### Vertical Scale

The active mobile world is 30 blocks high. This is suitable for the current prototype but restrictive for mountains, caves, deep oceans, and underground progression.

### Main-Thread Generation

The active mobile runtime uses a per-frame generation budget, but generation and mesh application remain sensitive to device performance. Every increase in world complexity must be measured on actual Android hardware.

### Prototype User Interface

The inventory and action UI are functional and testable but are not final production visuals.

## Definition of Done

A feature is complete only when:

- The intended gameplay works.
- Relevant tests pass.
- Existing approved behaviour remains intact.
- Android behaviour is checked on-device when applicable.
- Performance impact is measured when applicable.
- The change is documented.
- The repository owner explicitly approves merging it.

## Repository Policy

Do not merge feature branches automatically or without explicit owner approval. A working branch may remain unmerged while it is being inspected or tested.