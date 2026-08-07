# TEKNIK World Overhaul Plan

After putting the terrain research and biome research together, the correct direction is **not** to rebuild TEKNIK from scratch and **not** to bolt water and extra biomes onto the current generator.

The right move is a controlled architectural overhaul of the existing column generator.

The current foundation—chunked deterministic generation, continentalness, temperature, moisture, and a column surface—is worth keeping. What changes is the entire middle of the pipeline: how terrain shape is produced, how water participates in that shape, and how biome identity is selected and expressed.

## Core architectural decision

TEKNIK's new world generator should be organized like this:

```text
WORLD COORDINATES
        │
        ▼
MACRO FIELDS
Continentalness
Temperature
Moisture
Terrain structure
Low-frequency warp
River corridor
        │
        ▼
TERRAIN SHAPING
Base elevation
Plains / hills / plateaus
Mountain masks
Ridged mountain structure
Valleys
River depression
        │
        ▼
HYDROLOGY / WATER TOPOLOGY
Ocean mask
Coast
River channel
Lake / pond basins
Water levels
        │
        ▼
FINAL SURFACE HEIGHT
        │
        ├── elevation
        ├── slope
        ├── mountain strength
        ├── water type
        └── coast proximity
        │
        ▼
CLIMATE + BIOME CLASSIFIER
Temperature
Moisture
Terrain context
Water context
        │
        ▼
BASE BIOME + MODIFIERS
        │
        ▼
SURFACE / VEGETATION / FEATURES
```

That is the architecture to commit to.

The important change is that terrain, water and biome classification become separate layers with explicit responsibilities, but they share information.

## Major design change: stop treating Mountain as one normal biome

A mountain is primarily terrain, not ecology.

Instead of:

```text
Mountain biome → make mountains.
```

Use:

```text
Terrain generator → this location is mountainous.
Then climate decides what that mountain looks like.
```

That allows combinations such as:

- dry rocky mountain,
- forested mountain,
- grassy mountain meadow,
- cold/snow-covered mountain,
- potentially wet mountain vegetation.

We do not need five mountain biome IDs immediately. The architecture just needs to stop equating mountain terrain == Mountain biome.

That alone will make the world feel much less repetitive.

## Base biomes and terrain modifiers should be separate

This is a better long-term model than generating dozens of explicit combination biomes.

For example:

```text
BASE ECOLOGY
Forest

TERRAIN
Mountain

HYDROLOGY
River nearby

RESULT
Mountain forest with riparian vegetation
```

Rather than needing separate IDs such as:

```text
MountainForest
RiverMountainForest
HillyMountainForest
ColdMountainForest
```

That becomes impossible to manage.

The system should therefore contain approximately three independent concepts:

| Layer | Examples |
| --- | --- |
| Base biome | Plains, Forest, Desert, Dry Grassland, Cold Plains, etc. |
| Terrain regime | Flat, rolling, plateau, mountain, valley |
| Water modifier | Coast, riverbank, lakeside, wetland |

Only environments that genuinely behave very differently should become special biome types.

Swamp, for example, could eventually justify being a biome because its water, vegetation and terrain relationship are fundamentally different.

# Stage 0 — Lock down the current baseline

Before changing generation, capture exactly where we are now.

This stage changes nothing visually.

Record the current main-head behaviour using fixed seeds:

- per-chunk terrain generation timing,
- meshing timing,
- p50/p95 results using the same benchmark methodology we've already used,
- existing biome percentages,
- current height distribution,
- current maximum/minimum terrain heights,
- map screenshots,
- representative gameplay screenshots.

The existing **1.0 ms p95 generation performance gate remains non-negotiable**.

Also add a biome-distribution report.

For every fixed test seed we should be able to see something such as:

```text
Forest    42.1%
Desert    24.7%
Plains     1.4%
Mountain  31.8%
```

Those values are illustrative, not assumed current values. The measurement is what matters.

That immediately settles the Plains question:

> Does Plains barely generate, or does it generate but fail visually?

### Stage 0 gate

Nothing proceeds until we have:

- baseline performance,
- baseline biome distribution,
- fixed regression seeds,
- deterministic output confirmation.

# Stage 1 — Refactor the generator internally without changing the world

This is a structural safety step.

Before changing terrain behaviour, split the existing generator into explicit stages.

Conceptually:

```text
sample_world_fields()
build_provisional_terrain()
apply_water_topology()
finalize_height()
classify_biome()
decorate_surface()
```

At this stage, those functions should reproduce today's world.

The purpose is preventing one gigantic generator function from becoming even more tangled as rivers, oceans and more biomes arrive.

Also introduce a per-chunk field cache.

Instead of repeatedly asking:

```text
temperature(x,z)
moisture(x,z)
continentalness(x,z)
```

throughout terrain, biome and vegetation code, compute them once and reuse them.

The cache should include a small halo around the chunk boundary so neighbouring information such as slope and river continuity does not create seams.

### Stage 1 gate

The refactored generator must produce assertion-equivalent world output to the existing generator.

Performance must remain at or below the existing threshold.

If a refactor alone materially slows generation, fix that before proceeding.

# Stage 2 — Replace the current terrain-shape calculation

This is the biggest terrain change.

Do not simply increase terrain noise amplitude again.

The new terrain system should build terrain from several derived structural components.

## 2A. Continental base elevation

Continentalness becomes the authority for large-scale world elevation.

It should distinguish things such as:

- deep ocean,
- ocean basin,
- continental shelf,
- coast,
- low inland,
- normal inland,
- deep inland,

through a nonlinear mapping rather than a simple linear height addition.

This gives oceans a proper architectural foundation later.

## 2B. Broad terrain regime

A low-frequency terrain field establishes things like:

- flat regions,
- rolling regions,
- uplands,
- mountain-capable regions.

It should not directly equal final height.

Think:

```text
terrain field
    ↓
terrain regime
    ↓
different shaping rules
```

## 2C. Ridged mountains

Mountain regions then use a ridged transform rather than simply amplifying ordinary smooth noise.

That produces actual mountain spines and ranges.

Reuse existing sampled noise where possible and derive ridge information mathematically instead of paying for a new expensive stack of octaves.

## 2D. Mountain masks

Ridges should only become large where the macro terrain says mountains belong.

Otherwise ridged noise everywhere would make the whole world rough.

Conceptually:

```text
mountain_height =
    mountain_region_strength
    × ridge_strength
    × mountain_amplitude
```

## 2E. Plateaus / foothills / ordinary hills

These should come from different remappings of the same terrain fields.

That is how we get more landform types without multiplying random noise calls.

# Stage 3 — Introduce low-cost domain warping

Only after Stage 2 works.

The purpose is to make macro geography less obviously noise-shaped.

Use low-frequency warping on:

- mountain structure,
- perhaps continental boundaries,
- later river corridors.

Do not domain-warp every detail noise.

The warp should be computed on a coarse grid and reused/interpolated.

For the first implementation, start macro-field sampling at approximately a **4-block lattice**, with even coarser sampling acceptable for temperature/moisture. A field should only move to finer sampling if visual tests demonstrate aliasing.

This is where Android discipline matters.

### Terrain gate

Across the fixed seed suite demonstrate:

- recognizable plains,
- rolling terrain,
- distinct mountain ranges,
- valleys,
- plateaus/uplands,
- no chunk seams,
- no clipping against the current world-height limit,
- no repetitive terracing,
- generation still **≤ 1.0 ms p95** using the established benchmark.

The current world height of **60** remains unchanged during this overhaul unless terrain statistics prove it is actually insufficient.

Do not mix another vertical-range change into the same architecture work without evidence.

# Stage 4 — Build water topology into terrain

Only once the new land generator is stable.

This is where previous water research becomes part of the core architecture.

## Oceans first

Oceans are simplest.

Continentalness determines broad oceanic regions.

Terrain elevation falls below a global sea level.

Water fills them.

The important part is that the ocean exists because terrain was shaped as an ocean basin, not because a biome classifier randomly selected `OCEAN`.

Then create a coastal transition:

```text
ocean
↓
continental shelf
↓
shore
↓
low inland terrain
```

No separate complex ocean generator should be necessary.

# Stage 5 — Rivers become a first-class terrain field

This is the most delicate part of the overhaul.

A dedicated river influence field should be generated before final terrain height.

It must produce long, coherent narrow corridors.

It can use:

- low-frequency noise,
- ridge/absolute-value transformations,
- low-frequency coordinate warping,
- continentalness constraints.

But the river corridor cannot merely be painted onto finished terrain.

Instead:

```text
provisional terrain
        +
river influence
        ↓
valley shaping
        ↓
final terrain
```

When a river crosses mountainous terrain, its influence should reduce mountain elevation around the corridor and create a valley or saddle.

That avoids the ugly alternative:

> Generate a mountain first, then cut a giant vertical trench through it.

## Important scope boundary

This will not be a full watershed simulation.

We are not calculating rainfall, catchments or physical erosion.

The goal is:

> convincing continuous voxel rivers generated procedurally.

Not:

> scientifically correct drainage networks.

That is the correct complexity level for TEKNIK at this stage.

### River acceptance gate

Automatically examine generated river corridors over multiple fixed seeds and verify:

- continuity across chunk boundaries,
- no one-chunk river fragments,
- reasonable minimum path lengths,
- river width changes are gradual,
- mountain crossings form valleys instead of sheer trenches,
- rivers can meet oceans cleanly,
- no unexplained floating or isolated water patches.

Any systematic dry breaks mean the river algorithm is not complete.

# Stage 6 — Surface lakes and ponds

Do not build Minecraft-style aquifers.

Not yet.

Surface lakes can use a lightweight system:

```text
local terrain basin
+
suitable basin containment
+
moisture probability
        ↓
lake
```

Or use deterministic lake-feature placement that modifies terrain before final block generation.

Lake water gets its own local water level.

Ponds are simply smaller versions with stricter size limits.

High moisture can increase likelihood but should not directly command lake existence.

### Lake gate

A lake must:

- actually be enclosed,
- not spill through terrain incorrectly,
- survive chunk boundaries,
- not create single-block water noise,
- remain meaningfully distinct from river/ocean generation.

# Stage 7 — Replace biome classification

Only now do we classify biomes, because we finally know:

- terrain height,
- mountain strength,
- slope,
- water type,
- coastal state,
- temperature,
- moisture.

That is much better input than the current biome classifier has.

## Main climate space

Keep the primary biome classification simple:

```text
temperature × moisture
```

Those fields should change much more slowly than ordinary terrain.

That creates large regions naturally.

Use a **nearest-prototype climate classifier** rather than dozens of hard-coded nested thresholds.

Conceptually:

```text
Plains target       = temperate / medium moisture
Forest target       = temperate / wet
Desert target       = hot / dry
...
```

At a location, find the nearest eligible biome profile.

Eligibility is determined first by terrain/water context.

For example, a physical ocean column cannot select Forest.

This architecture also guarantees a fallback biome instead of holes in the classification table.

# Stage 8 — Establish the first genuinely readable biome set

This stage should not begin by creating fifteen names.

First decide which biome identities can be made visibly different with the game's actual assets.

A reasonable target for the initial overhaul is roughly **6–8 strong land ecologies**, not twenty weak ones.

The climate architecture should be capable of supporting concepts in this family:

- Plains
- Forest
- Dense/Wet Forest
- Desert
- Dry Grassland / Savanna-like region
- Cold Plains / Tundra-like region
- Cold Forest / Taiga-like region
- potentially a wet lowland biome once water exists

These are design candidates, not a commitment that every one must ship in this overhaul.

A biome is only admitted when it can receive at least three strong distinguishing cues.

For example, Plains cannot merely be:

> Forest minus 15% trees.

It needs to read immediately as open country:

- strongly reduced tree density,
- broad open sightlines,
- different ground vegetation pattern,
- potentially different colour/terrain character.

Similarly, Dense Forest must look materially denser than Forest.

# Stage 9 — Terrain modifiers instead of biome explosion

Once the base ecology is selected, apply terrain context.

Example:

```text
Base biome: Forest
Terrain: Mountain
Elevation: High
Temperature: Cold
```

The expression system can reduce normal trees, expose more stone, apply snow or cold vegetation rules.

We do not necessarily need to register another independent biome ID called:

```text
ColdMountainForest
```

This is how the biome system remains scalable.

Mountain, hill, valley and plateau become terrain regimes.

Coast, riverbank and lakeside become hydrology modifiers.

Base biome remains ecological identity.

That is probably the single most important biome-architecture decision in this plan.

# Stage 10 — Solve biome region size correctly

Do not return to tiny patch blending.

Temperature and moisture themselves should operate at broad scales.

Then apply a transition zone only near climate boundaries.

The transition should affect things like:

- vegetation density,
- vegetation selection,
- ground-decoration probability.

It should not randomly alternate complete biome identities block-by-block.

For testing, use the same **2-block minimap sampling resolution** that already exposed the previous speckle problem.

The new statistical gate should include:

- no isolated 1–2 sample biome islands except intentionally tiny special features,
- no salt-and-pepper patterns,
- common biomes forming clearly contiguous regions,
- Plains visibly occupying substantial regions,
- transition widths readable at both minimap and first-person scale.

Record connected-component statistics instead of merely counting biome percentages.

# Stage 11 — Water-aware biome expression

Now water and biome systems finally meet.

Not to generate the water—the water already exists.

Instead they change the environment around it.

Examples:

```text
Forest + river
→ greener / denser riverbank

Dry grassland + river
→ narrow lush riparian corridor

Cold region + river
→ cold/frozen treatment later

Wet lowlands + lake
→ potential marsh/swamp expression

Land + ocean edge
→ coastal/beach treatment
```

This is dramatically more powerful than making one universal `RIVER_BIOME`.

The river remains geographical.

The surrounding ecology determines what the river feels like.

# Stage 12 — Performance optimization before adding decoration complexity

Before fancy additional foliage/features, profile the completed generator.

The intended optimization model should be:

> sample expensive randomness once → derive many cheap signals.

That means:

- reuse field samples,
- derive ridges arithmetically,
- derive slope from neighbour heights,
- derive elevation context from final height,
- interpolate slow climate fields,
- perform domain warping at macro scale,
- avoid repeated noise requests inside vertical block loops.

One important rule:

> No procedural noise call should happen once per Y block unless there is no alternative.

This remains a surface/column generator. Most calculations should happen once per X/Z column.

## Hard performance gate

Same existing benchmark methodology.

**p95 ≤ 1.0 ms per chunk.**

If the overhaul exceeds it, optimize before continuing.

Do not accept:

> It looks better, so 1.4 ms is probably fine.

The whole reason for staying column-based is to avoid that trade.

# Stage 13 — Full regression and device acceptance

Before merging anything:

## Automated

Check:

- deterministic generation,
- chunk-border terrain continuity,
- river-border continuity,
- lake-border continuity,
- biome continuity,
- vegetation consistency,
- valid terrain heights,
- valid water levels,
- all worldgen tests,
- mining/placement compatibility,
- inventory/gameplay suite unchanged,
- performance gate.

## Statistical world audit

Run several fixed seeds through a large sampled area.

Produce:

- Biome coverage
- Region sizes
- Terrain-height histogram
- Slope histogram
- Ocean percentage
- River coverage
- Lake count
- Mountain coverage

Common biomes that are supposed to be ordinary should not accidentally appear at 0.2%.

This is specifically how we prevent another situation where Plains technically exists but essentially disappears from gameplay.

## Visual

Generate diagnostic maps for:

- continentalness,
- terrain height,
- mountain strength,
- river mask,
- water type,
- temperature,
- moisture,
- final biome.

Those maps make worldgen defects much easier to diagnose than looking only at the rendered game.

## Real Android device

The final acceptance must be based on the actual Android build:

- traverse multiple biomes,
- cross multiple biome transitions,
- reach mountain terrain,
- inspect ocean coast,
- inspect river,
- inspect lake/pond,
- verify chunk loading remains smooth.

Only after that should the overhaul be considered ready for approval to merge.

As with the rest of this project, **do not merge the overhaul branch into `main` until Akila explicitly confirms the tested build is good and instructs the merge**.

# What we deliberately will NOT do

This is equally important.

Do not:

- replace TEKNIK with a full Minecraft-style 3D density generator;
- add caves/aquifers as part of this overhaul;
- implement full hydrological watershed simulation;
- add dozens of independent noise layers;
- add fifteen biome IDs just for variety;
- let biome IDs directly dictate terrain height;
- generate rivers after terrain is finished;
- make Ocean merely another random biome;
- increase world height again without evidence;
- loosen the 1.0 ms performance gate to accommodate the new system.

Those would make this session larger and riskier without proportionate benefit.

# Final recommended scope

| Existing system | Overhauled system |
| --- | --- |
| Continentalness | Keep, make it authoritative for macro geography/oceans |
| Terrain-shape | Replace with structured terrain subsystem |
| Temperature | Keep, slow-scale climate |
| Moisture | Keep, slow-scale climate |
| Mountains | Terrain regime with ridged shaping |
| Plains | Proper ecological biome with strong visual identity |
| Forest / Desert | Remain ecological biomes |
| New biomes | Add a small strong set through climate classification |
| Oceans | Physical continental/sea-level system |
| Rivers | Dedicated terrain-integrated corridor field |
| Lakes | Local basin/feature system |
| Biome blending | Large-scale climate continuity + transition bands |
| 3D density | Do not add |
| Aquifers | Do not add yet |

# Central philosophy

The new generator should think in this order:

> **Build geography → add water → understand terrain context → apply climate → choose ecology → decorate it.**

Not:

> Choose biome → make some terrain → randomly add water.

That is the architecture that gives TEKNIK the largest jump in world quality without throwing away the performant foundation already stabilized.