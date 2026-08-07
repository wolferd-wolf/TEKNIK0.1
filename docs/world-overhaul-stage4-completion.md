# World Overhaul Stage 4 — Ocean and Coast Topology

Stage 4 is complete on `world-overhaul`.

This stage adds physical ocean/coast geography to the shipping terrain pipeline. It does **not** add rivers, lakes, ponds, aquifers, or new biome IDs. Those remain later stages.

## Architecture

Stage 4 keeps Stage 2 structured terrain and Stage 3 macro warping as the provisional land surface, then applies explicit water topology before final height:

```text
Stage 2/3 provisional terrain
        +
continentalness water topology
        ↓
ocean basin / shelf / coast shaping
        ↓
final terrain height
        ↓
explicit ocean classification
        ↓
water surface renderer
```

Oceans are therefore geography, not a randomly selected biome and not an inference from any arbitrary low terrain patch.

## Shipping thresholds

- sea level: `7`
- ocean water begins at continentalness `<= -0.34`
- full ocean-basin strength at `-0.48`
- coastal transition reconnects to unchanged inland terrain by `-0.08`
- continental-shelf/ocean-edge floor: `Y=6`
- ocean-core floor: `Y=3`

The synthetic transition gate verifies this profile:

```text
ocean core       Y=3
continental shelf Y=6
first dry shore   Y=7
mid coast         Y=12
inland terrain    Y=18 (unchanged Stage 3 provisional height)
```

## Explicit water contract

The shipping generator now exposes explicit water topology:

- `WATER_NONE`
- `WATER_OCEAN`
- `water_type_at()`
- `is_ocean_column()`
- `is_coast_column()`

`localized_water_bodies.gd` consumes `is_ocean_column()` for the shipping world. It retains the old low-basin neighbor classifier only as a compatibility fallback for the legacy regression oracle.

This prevents unrelated inland depressions from becoming ocean water simply because they are below sea level.

## Performance design

Stage 4 adds no new `FastNoiseLite` stack.

Ocean/coast shaping is derived arithmetically from continentalness already sampled for each column. The public generation facade contains the authoritative topology functions, while the shipping padded-chunk cache inlines the same arithmetic to avoid dynamic GDScript calls/property lookups inside the hot per-column loop.

The hard generation gate remains unchanged: **p95 < 1.0 ms**.

## Final exact-head evidence before documentation commit

Implementation/test head: `7064aaed0cee9843846eb9f43e36a09a8d878d2c`

### Stage 4 ocean gate

- generation/cache benchmark: **0.925 ms p95** across 320 measured padded chunks
- hard limit: **< 1.0 ms p95**
- sampled columns: `66,049` at 4-block spacing
- ocean columns: `6,430`
- ocean coverage: **9.735%**
- coastal-transition columns: `18,948`
- coastal-transition coverage: **28.688%**
- ocean-core columns: `1,697`
- sampled ocean floor range: `Y=3..6`
- shoreline adjacency checks: `256`
- renderer/topology agreement checks: `512`
- runtime/public final-height comparisons: `1,024`
- deterministic chunk comparisons: `4`
- default spawn `(6,6)` is dry
- no inland low columns were incorrectly classified as ocean in the fixed audit

### Stage 2 compatibility

The Stage 2 gate was updated only to respect the staged architecture: it now audits Stage 2's provisional terrain directly and verifies that public terrain height composes that provisional surface through later stages.

- Stage 2 generation/cache benchmark: **0.971 ms p95** across 320 measured padded chunks
- Stage 2 provisional terrain remains `Y=3..86`
- structured plains, rolling terrain, uplands, ridged mountains and valleys remain present
- 192 cross-chunk overlap checks passed
- deterministic generation passed

## Full regression result

All exact-head workflows were green on `7064aaed0cee9843846eb9f43e36a09a8d878d2c`, including:

- TEKNIK Acceptance Gate
- TEKNIK World Overhaul Stage 4 Ocean Gate
- TEKNIK World Overhaul Stage 3 Warp Gate
- TEKNIK World Overhaul Stage 2 Terrain Gate
- TEKNIK Chunk Stream Biome Soak Diagnostic (fresh data, persisted relaunch, main-baseline comparison)
- TEKNIK Biome Contiguity Gate
- TEKNIK Polish Water Gate
- TEKNIK Playable World Standalone Gate
- TEKNIK Inventory on Consolidated World
- TEKNIK Step 3 Touch Gate
- TEKNIK Vanilla Minecraft Lighting Gate
- TEKNIK Diagnostic Log Capture Gate
- TEKNIK WORLD_HEIGHT 60 legacy-oracle gate
- TEKNIK Step 4 Android Export Setup Gate
- TEKNIK Step 5 Export Configuration Diagnostic
- TEKNIK Step 5 Android APK Export

## Stage boundary

Stage 5 has **not started**.

There is no river corridor field, river carving, river-valley shaping, river/ocean joining logic, lake placement, pond placement, or aquifer system in Stage 4.

The next world-overhaul stage is the dedicated terrain-integrated river system.