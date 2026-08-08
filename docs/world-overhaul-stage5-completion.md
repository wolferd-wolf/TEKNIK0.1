# World Overhaul Stage 5 — Rivers

Stage 5 adds rivers as first-class terrain and water topology on top of the accepted Stage 4 ocean/coast geography. It does **not** add lakes, ponds, aquifers, caves, or a full watershed/flow solver.

## Stage boundary

Stage 5 is responsible for:

- deterministic long river corridors,
- broad river-valley terrain influence,
- narrow carved channels,
- local river-water surfaces above sea level,
- river/ocean joining,
- mountain crossings that shape valleys instead of painting water over peaks,
- deterministic chunk/halo behavior,
- maintaining the hard generation/cache performance gate of **p95 < 1.0 ms**.

Stage 6 lakes/ponds have not started.

## River field

The final Stage 5 field is a continuous deterministic centerline system rather than arbitrary 2D zero contours.

Each river family is described by a world-space centerline of the form:

```text
x + diagonal_drift(z) + low_frequency_meander(z)
```

The meander is deterministic hash/value interpolation on a **192-block lattice**. Parallel centerlines repeat every **224 blocks**. The field exposed to terrain shaping is the physical block-distance to the nearest centerline.

This choice was made after the first 2D contour prototype produced good-looking macro coverage but many tiny closed fragments. Continuous graph centerlines guarantee long coherent corridors and eliminate those closed-loop fragments while remaining cheap enough for GDScript.

No additional `FastNoiseLite` stack was added.

### Current river dimensions

- river family spacing: **224 blocks**
- meander lattice spacing: **192 blocks**
- diagonal drift: **0.28 blocks X per block Z**
- maximum meander amplitude: **48 blocks**
- inner channel distance: **1.8 blocks**
- outer channel distance: **6.8 blocks**
- inner valley distance: **7.2 blocks**
- outer valley distance: **14.4 blocks**
- subtle coast width scale: **1.04**
- inland width scale: **0.96**

The water channel is deliberately narrower than its terrain influence so rivers read as valleys with a channel inside them rather than trenches cut directly through every landform.

## Terrain shaping

Stage 5 runs after Stage 4 ocean/coast shaping and before final surface height.

For a river-active land column:

1. Calculate river block-distance and channel/valley strengths.
2. Compute available relief above sea level.
3. Lower the broad valley by up to **55% of local relief**, capped at **24 blocks**.
4. Lower the inner channel by up to **2 additional blocks**.
5. Clamp to the existing Stage 2 safe terrain ceiling and world-height contract.

Therefore the maximum possible Stage 5 river influence is **26 blocks** at the channel center: 24 blocks of valley shaping plus 2 blocks of channel depth.

This is intentionally terrain-aware. A mountain crossing modifies the mountain into a valley rather than placing water across the untouched peak.

## Water topology and rendering

Stage 5 extends the explicit Stage 4 water contract:

```text
WATER_NONE  = 0
WATER_OCEAN = 1
WATER_RIVER = 2
```

Ocean water remains at global sea level **Y=7**.

River water is local:

```text
river_surface_y = final_river_terrain_height + 1
```

`localized_water_bodies.gd` now consumes `water_info_at()` and builds each water cell at the returned local water level. This allows inland rivers to climb through the world instead of being flattened onto the ocean plane.

The Stage 5 renderer test exercised an inland river chunk with **59 river-water cells above sea level** and a maximum rendered water vertex height of **Y=20.54**.

## Shipping-cache performance architecture

The initial Stage 5 implementation used a separate river post-pass and exceeded the generation budget. The final shipping cache is fused with the existing Stage 3/4 generation pass.

Key optimizations:

- no extra `FastNoiseLite` sampler,
- no persistent per-column river field in the chunk cache,
- only the 2–3 low-frequency meander hash nodes needed by a 16-row padded chunk are cached,
- one meander interpolation per row,
- one periodic centerline interval is resolved per row,
- `river_active_min` / `river_active_max` skip almost all river-specific arithmetic on ordinary columns,
- ocean columns bypass river shaping,
- Stage 2 provisional terrain arithmetic is inlined exactly in the hot path,
- the accepted biome classifier is inlined exactly in the hot path,
- biome patch X coordinates are precomputed once per chunk,
- no per-column `Vector4`/`Vector2` allocations for terrain/biome classification.

Public/direct generation remains the readable source-of-truth implementation; the fused cache is required to remain assertion-equivalent to it.

## Fixed-seed Stage 5 evidence

Dedicated Stage 5 gate evidence on the accepted shipping implementation:

- fixed audit area: **66,049 columns** at 4-block spacing across `-512..512`,
- river columns: **2,263**,
- river coverage: **3.426%**,
- ocean columns in the same audit: **6,430**,
- river connected components: **34**,
- long river components: **15**,
- isolated one-chunk fragments: **0**,
- maximum measured component span: **696 blocks**,
- mountain river crossings: **104**,
- maximum observed terrain carve: **26 blocks**,
- river/ocean join checks: **46**,
- runtime/public padded-column height comparisons: **1,024 passed**,
- river columns exercised in runtime-equivalence chunks: **117**,
- maximum adjacent river block-distance delta: approximately **1.0 block per block**,
- maximum adjacent width-scale delta: approximately **0.0064**,
- default player spawn remains dry.

## Performance evidence

The dedicated Stage 5 gate uses the established world-generation benchmark methodology:

- 16 representative padded chunks,
- 4 warmups,
- 20 repeats,
- 320 measured cache builds,
- generation/cache only,
- hard gate remains **p95 < 1.0 ms**.

Successful measurements include:

- **0.937 ms p95** on commit `b4bcac55e398985a8f249a563e633f8e58ee9b93`,
- **0.911 ms p95** on commit `118a32d30f5863d3df3b89f049215abd6bff1919`.

The threshold was not relaxed during optimization.

## Regression discipline

Later-stage work exposed that some older Stage 2/3/4 CI gates were benchmarking the newest shipping runtime instead of the stage they were intended to preserve. Those gates are being isolated to frozen stage-specific data/runtime implementations so they remain meaningful historical oracles while Stage 5 remains the shipping path.

Stage 5 itself has passed the full game regression and Android export suites on its shipping-code head, including Acceptance, threaded chunk-stream soak, standalone world, water, biome contiguity, inventory, touch, lighting, diagnostics, Android export setup/configuration, and debug APK export.

## Not included

Stage 5 deliberately does **not** implement:

- lakes,
- ponds,
- aquifers,
- cave water,
- full watershed accumulation,
- physically simulated downstream flow,
- erosion simulation,
- biome-classifier replacement.

Those remain outside the Stage 5 boundary. Stage 6 is the planned lake/pond stage.

## Merge status

All Stage 5 work remains on `world-overhaul`. PR #46 must remain draft/unmerged until real-device approval and an explicit merge instruction.
