# World Overhaul Stage 12 — Optimization / Pass-Budget Completion

Stage 12 is complete on the `world-overhaul` branch.

Validated implementation head: `00b3ec1e2b017d418dd20c83b13d533fa13bffe3`.

Stage 12 is deliberately output-preserving. It does not change terrain geography, water topology, climate, ecology IDs, terrain modifiers, biome-region sizing, water-aware surface expression, or generated vegetation. It optimizes the post-generation expression/meshing path while keeping the hard generation cache exactly on the accepted Stage 10 implementation used by Stage 11.

## What changed

### Frozen Stage 11 oracle

`scripts/world/playable_world_stage11_generation_runtime.gd` preserves the accepted Stage 11 runtime path so Stage 12 can prove equivalence against a stable reference rather than a moving public facade.

### Hydrology-expression preparation

`scripts/world/playable_world_stage12_cache_fast.gd` keeps Stage 10/11 climate-transition preparation unchanged and replaces the interpreted nested 8-neighbor hydrology scan with eight fixed packed-array reads.

The exact Stage 11 priority remains:

`riverbank > lakeside > pondside > coast`

No new procedural noise is sampled.

### Mesher bookkeeping

`scripts/world/playable_world_stage12_mesher.gd` preserves Stage 11 block output while removing avoidable repeated work:

- legacy/generated tree-suppression membership uses a packed byte mask instead of a Dictionary on the normal path;
- Stage 11 surface-expression and custom-tree eligibility passes are fused;
- world coordinates, biome, terrain modifier, transition code, hydrology code and cached slope are computed once per dry column and reused;
- final geometry is still produced by the same base mesher.

The shipping public runtime now uses the Stage 12 expression cache and equivalent Stage 12 mesher while retaining the exact Stage 10 generation cache.

## Dedicated Stage 12 gate

Workflow: `TEKNIK World Overhaul Stage 12 Optimization Gate`

Run: `31246537042` — **green** on implementation head `00b3ec1e2b017d418dd20c83b13d533fa13bffe3`.

Evidence artifact ID: `9018676079`.

### Exact-equivalence checks

- 4 generation-equivalence chunks;
- 20 generation array contracts exactly preserved (`world_fields`, `heights`, `biomes`, `stage7_water_types`, `stage9_terrain_modifiers`);
- 16 transition-code arrays exactly preserved;
- 16 hydrology-code arrays exactly preserved;
- 4,096 hydrology columns compared;
- 4 full mesh-data chunks exactly preserved;
- exact mesh comparison includes face count, vertices, normals, colors and indices;
- 1,319 total compared faces;
- failures: none.

### Hard generation/cache benchmark

Unchanged methodology: 16 representative padded chunks, 4 warmups, 20 repeats, 320 measured chunks.

- minimum: **0.580 ms**
- mean: **0.675 ms**
- p95: **0.769 ms**
- maximum: **0.895 ms**
- hard gate: **p95 < 1.0 ms**

### Hydrology preparation

Frozen Stage 11:
- mean: **0.254 ms**
- p95: **0.324 ms**

Stage 12:
- mean: **0.208 ms**
- p95: **0.272 ms**

Stage 12 therefore reduces the measured hydrology-expression p95 by about **16%** while preserving byte-identical hydrology codes.

### Combined transition + hydrology preparation

Frozen Stage 11:
- mean: **0.434 ms**
- p95: **0.544 ms**

Stage 12:
- mean: **0.391 ms**
- p95: **0.496 ms**

The combined preparation p95 improves by about **9%**.

### Equivalent mesher benchmark

Four prepared chunks, one warmup, three repeats.

Frozen Stage 11:
- mean: **89.653 ms**
- p95: **97.891 ms**

Stage 12:
- mean: **89.178 ms**
- p95: **97.353 ms**

The optimized mesher is slightly faster on this hosted-runner sample while producing exactly identical mesh-data output.

## Full implementation-head regression closure

All required workflows are green on `00b3ec1e2b017d418dd20c83b13d533fa13bffe3`:

- TEKNIK Acceptance Gate — `31246537012`
- TEKNIK World Overhaul Stage 12 Optimization Gate — `31246537042`
- TEKNIK World Overhaul Stage 11 Water Biome Gate — `31246537029` (green unchanged rerun after a timing-only hosted-runner spike)
- TEKNIK World Overhaul Stage 10 Region Gate — `31246536985`
- TEKNIK World Overhaul Stage 9 Terrain Modifier Gate — `31246536988`
- TEKNIK World Overhaul Stage 8 Biome Gate — `31246537030`
- TEKNIK World Overhaul Stage 7 Biome Gate — `31246537007`
- TEKNIK World Overhaul Stage 6 Lake Gate — `31246537033`
- TEKNIK World Overhaul Stage 5 River Gate — `31246537025`
- TEKNIK World Overhaul Stage 4 Ocean Gate — `31246537003`
- TEKNIK World Overhaul Stage 3 Warp Gate — `31246536994` (green unchanged rerun after a timing-only hosted-runner spike)
- TEKNIK World Overhaul Stage 2 Terrain Gate — `31246537048`
- TEKNIK Biome Contiguity Gate — `31246537023`
- TEKNIK Chunk Stream Biome Soak Diagnostic — `31246536982`
- TEKNIK Polish Water Gate — `31246537019`
- TEKNIK Playable World Standalone Gate — `31246537018`
- TEKNIK Inventory on Consolidated World — `31246537034`
- TEKNIK Step 3 Touch Gate — `31246537091`
- TEKNIK Vanilla Minecraft Lighting Gate — `31246536987`
- TEKNIK Diagnostic Log Capture Gate — `31246536990`
- TEKNIK WORLD_HEIGHT 60 Gate — `31246537006`
- TEKNIK Step 4 Android Export Setup Gate — `31246537015`
- TEKNIK Step 5 Export Configuration Diagnostic — `31246536986`
- TEKNIK Step 5 Android APK Export — `31246537020`

The actual Android debug APK export and APK inspection are green on this implementation head.

APK artifact:
- ID: `9018760237`
- name: `teknik-step5-consolidated-apk-export`
- SHA-256: `c8b7ea609864bf3a5f554a9c760e6c0ce42a50c8457f3576ea5a21b412420325`

## Timing-only historical reruns

Two frozen historical gates hit hosted-runner timing spikes on their first attempt:

- Stage 3 frozen oracle: `1.293 ms p95`; all correctness checks passed; unchanged rerun green.
- Stage 11 frozen oracle: `1.134 ms p95`; all Stage 11 correctness checks passed; unchanged rerun green.

No source change and no threshold relaxation was made in response. The current Stage 12 shipping-generation path remained green at `0.769 ms p95` in its dedicated 320-sample gate.

## Stage boundary

**Stage 12 is complete. Stage 13 has not started.**

Stage 13 remains the final full regression / real-device acceptance stage from the overhaul plan. This branch and PR must remain unmerged until explicit real-device approval and an explicit merge instruction.
