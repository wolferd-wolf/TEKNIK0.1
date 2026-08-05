# Changelog

This changelog records major user-visible and architectural milestones in TEKNIK 0.1. The project remains an early prototype and does not yet follow a formal public release cadence.

## Unreleased

### Planned Direction

- Multi-field procedural biome generation for the active mobile world path.
- Better large-scale terrain regions and vegetation distribution.
- Save-compatible world-generator versioning before incompatible terrain changes.

These items are not implemented yet.

## 0.1.0 Prototype Baseline

### Added

- Godot 4 project foundation and main gameplay scene.
- Procedural voxel terrain.
- Streamed world chunks around the player.
- Grass, dirt, stone, and sand terrain layers.
- Deterministic trees using log and leaf blocks.
- Localized water surface meshes.
- First-person movement, gravity, jumping, and camera pitch limits.
- Block ray targeting and visible target highlight.
- Mining and block placement.
- Placement rejection when a block would overlap the player.
- Saved world-edit overrides for mined and placed blocks.
- Touch joystick for movement.
- Right-side drag-to-look controls.
- Touch jump, mine, place, and craft actions.
- Touch hotbar selection.
- Mobile camera-sensitivity adjustment.
- Nine-slot hotbar.
- 36-slot inventory with 27 storage slots.
- Stack size of 64.
- Mining-to-inventory transactions.
- Inventory-backed placement consumption.
- Full-inventory mining rejection.
- Stack pickup, merging, swapping, splitting, and single-item placement.
- Desktop and touch inventory screen.
- Temporary crafting acceptance recipe: four dirt to one stone.
- Direction-based voxel face shading.
- Vertex ambient occlusion.
- Vertical skylight calculation.
- Skylight reduction through leaves.
- AO-aware face diagonal selection.
- Padded cross-chunk block and lighting sampling.
- Budgeted mobile chunk generation and nearby-only collision.
- Atomic chunk replacement during edit rebuilds.
- Godot acceptance and regression scripts.
- GitHub Actions validation gates.
- Gradle-based Android export presets.
- Manual Android debug APK export workflow.
- Debug keystore generation helper.
- Project icon.

### Changed

- Active Android gameplay moved to the optimized playable-world runtime.
- Camera sensitivity was increased for practical mobile turning.
- Real-time directional shadow maps were disabled in favour of classic voxel vertex lighting.
- Inventory capacity was expanded to 36 slots.
- Touch controls were separated from mouse emulation to avoid input conflicts.
- Chunk collisions were limited to the near-player ring for mobile performance.

### Fixed

- Android launch crashes in earlier exported builds.
- Terrain face-winding and back-face-culling problems.
- Mining and placement remesh behaviour at chunk boundaries.
- Player placement overlap cases.
- Slow mobile drag-to-look response.
- Tree-canopy face and lighting artifacts.
- Leaf skylight attenuation.
- Ambient-occlusion interpolation seams.
- Inventory transaction rollback edge cases.
- Gradle Android export configuration and debug keystore setup.

### Known Limitations

- Fixed world seed.
- No production biome system.
- No caves, ores, mobs, survival stats, or progression.
- Inventory and player position are not saved.
- Water has no fluid simulation.
- Crafting remains a test transaction.
- Active mobile world height is 30 blocks.
- Finished textures, audio, release signing, and store packaging are not complete.