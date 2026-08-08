# World Overhaul Stage 11 Completion

Stage 11 — water-aware biome expression — is complete on `world-overhaul`.

Validated implementation/test head before this documentation commit:

`4f56836e129570669e714f2671cbe1e34ce0bf11`

Stage 12 has not started. PR #46 remains intentionally draft and unmerged.

## Architecture

Stage 11 does not create Ocean, River, Lake, or Pond base-biome IDs. Physical water remains owned by the accepted Stage 4–6 hydrology topology, Stage 8 remains the ecological identity, Stage 9 remains the orthogonal terrain modifier, and Stage 10 remains the climate-region transition layer.

Stage 11 adds one expression-only hydrology modifier to dry land immediately touching cached physical water:

- `none`
- `coast`
- `riverbank`
- `lakeside`
- `pondside`

The margin radius is one block. Priority where contexts meet is:

`riverbank > lakeside > pondside > coast`

Physical-water cells receive no land hydrology modifier.

## Expression rules

- Gentle low land immediately beside ocean water becomes a narrow readable sand beach.
- Geological cliffs remain rock/terrain-driven rather than being painted over by beach treatment.
- Immediate river, lake, and pond margins become hydrated ground: grass top with shallow dirt beneath, including through dry ecology without changing the underlying biome ID.
- River/lake/pond margins can deterministically increase tree eligibility while preserving the accepted Stage 8 tree silhouettes and the Stage 9 slope/tree-line restrictions.
- Beaches stay open rather than becoming extra wooded coast.
- Frozen/ice water behavior is intentionally deferred; Stage 11 does not invent cold-water topology.

## Performance architecture

Stage 11 adds no FastNoiseLite instance and no new noise sampling.

The hard generation path is still the exact accepted Stage 10 generation cache:

`playable_world_stage10_generation_cache_fast.gd`

Stage 11 water-margin metadata is derived afterward from the already cached physical-water byte array. It is therefore measured separately as expression preparation instead of being hidden inside the generation benchmark.

## Final Stage 11 gate

Workflow: **TEKNIK World Overhaul Stage 11 Water Biome Gate**

Run: `31245263338`

Evidence artifact ID: `9018277195`

Artifact SHA-256: `4c5af794218ec4f8a9118016f31a21d8ba54ee92f7e50a1dc0e516365bc48611`

### Hard generation/cache benchmark

Unchanged methodology:

- 16 padded chunks
- 4 warmups
- 20 repeats
- 320 measured chunks
- minimum: **0.582 ms**
- mean: **0.701 ms**
- p95: **0.818 ms**
- maximum: **1.025 ms**
- hard gate remains **p95 < 1.0 ms**

The gate is p95, not maximum; the unchanged p95 requirement passes with substantial margin.

### Stage 10 climate-transition preparation

- minimum: **0.089 ms**
- mean: **0.183 ms**
- p95: **0.231 ms**
- maximum: **0.242 ms**
- unchanged Stage 10 guard: **p95 < 0.3 ms**

### Stage 11 hydrology-expression preparation

- minimum: **0.104 ms**
- mean: **0.266 ms**
- p95: **0.338 ms**
- maximum: **0.358 ms**
- Stage 11 guard: **p95 < 0.5 ms**

## Correctness evidence

- Stage 10 generation arrays remain exact across four representative chunks: world fields, heights, ecology IDs, physical-water types, and Stage 9 terrain modifiers.
- Stage 10 array contracts compared: **20**.
- Prepared/direct hydrology comparisons: **570**.
- Hydrology adjacency checks: **15**.
- Physical-water columns receiving a land hydrology modifier: **0**.
- Hydrology overlap seam comparisons: **56**.
- Determinism chunks: **3**.
- Real fixed-seed lake margin found at `(-217, -1214)`.
- Real fixed-seed pond margin found at `(-613, -559)`.
- Broad audit land columns: **38,089**.
- Broad audit water columns: **3,527**.
- Broad audit hydrology counts `[none, coast, riverbank, lakeside, pondside]`: `[36999, 565, 525, 0, 0]`.
- Surface-expression changes in that broad audit: coast **1**, riverbank **38**.
- Tree-eligibility changes in that broad audit: riverbank **5**.
- Dedicated feature search, rather than the broad local audit window, proves actual lake and pond margins exist.
- Failures: **none**.

## Placement Acceptance closure

Stage 11's richer water-aware vegetation exposed two weaknesses in the historical placement test, not in production placement code.

First, the old fixture treated the highest non-air block at fixed `(2,2)` as terrain. Under Stage 11 that column contained generated vegetation:

- historical highest non-air Y: **24**
- actual terrain Y: **19**

The acceptance test now chooses a dry, tree-clear fixture using the shipping terrain-height API instead of conflating vegetation with terrain.

Second, the headless harness assumed a parsed mouse event synchronously mutated the `Input` singleton's action state. The final test separates the two contracts:

1. `InputMap.event_is_action()` proves the configured right-mouse event matches `place_block`.
2. `Input.action_press()` supplies the already-proven action state, and the shipping inventory player controller's real `_process()` consumes the just-pressed edge immediately in deterministic test order.

The test still requires the same production behavior after dispatch: world write, inventory decrement, atomic chunk replacement/remesh, collision update, occupied-cell rejection, player-overlap rejection, and unloaded-chunk rejection. Production placement/controller code was not changed for Stage 11.

Final Acceptance run: `31245263350` — **green**, including graphical launch, mining, placement, boundary cases, inventory, and touch.

## Exact-head regression closure

All required workflows are green on `4f56836e129570669e714f2671cbe1e34ce0bf11`:

- TEKNIK Acceptance Gate — `31245263350`
- TEKNIK World Overhaul Stage 11 Water Biome Gate — `31245263338`
- TEKNIK World Overhaul Stage 10 Region Gate — `31245263357`
- TEKNIK World Overhaul Stage 9 Terrain Modifier Gate — `31245263347`
- TEKNIK World Overhaul Stage 8 Biome Gate — `31245263346`
- TEKNIK World Overhaul Stage 7 Biome Gate — `31245263361`
- TEKNIK World Overhaul Stage 6 Lake Gate — `31245263363`
- TEKNIK World Overhaul Stage 5 River Gate — `31245263337`
- TEKNIK World Overhaul Stage 4 Ocean Gate — `31245263349`
- TEKNIK World Overhaul Stage 3 Warp Gate — `31245263344`
- TEKNIK World Overhaul Stage 2 Terrain Gate — `31245263362`
- TEKNIK Biome Contiguity Gate — `31245263348`
- TEKNIK Chunk Stream Biome Soak Diagnostic — `31245263351`
- TEKNIK Polish Water Gate — `31245263336`
- TEKNIK Playable World Standalone Gate — `31245263379`
- TEKNIK Inventory on Consolidated World — `31245263360`
- TEKNIK Step 3 Touch Gate — `31245263466`
- TEKNIK Vanilla Minecraft Lighting Gate — `31245263368`
- TEKNIK Diagnostic Log Capture Gate — `31245263385`
- TEKNIK WORLD_HEIGHT 60 Gate — `31245263359`
- TEKNIK Step 4 Android Export Setup Gate — `31245263342`
- TEKNIK Step 5 Export Configuration Diagnostic — `31245263339`
- TEKNIK Step 5 Android APK Export — `31245263341`

The actual Android debug APK export and resulting APK inspection are green on the same implementation/test head.

The frozen Stage 3, Stage 4, and Stage 7 historical performance oracles each encountered a timing-only hosted-runner miss on their first attempt. Their correctness/equivalence checks were green. The exact jobs were rerun unchanged and passed; no threshold or game source was changed for those reruns.

## Stage boundary

**Stage 11 is complete. Stage 12 has not started.**

Stage 12 is the optimization/pass-budget stage from the overhaul plan. Do not start it until explicitly requested.

Do not merge PR #46 until explicit real-device approval and an explicit merge instruction.
