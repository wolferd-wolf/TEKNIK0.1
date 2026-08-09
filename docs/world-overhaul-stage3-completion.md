# World Overhaul Stage 3 — Low-Cost Domain Warping

**Status: complete on `world-overhaul`.**

Stage 3 introduces explicit low-frequency coordinate warping for TEKNIK's broad terrain-structure field while preserving the Stage 2 terrain model, the 150-block legal vertical range, deterministic chunk generation, biome climate, and the hard 1.0 ms p95 generation/cache budget.

Stage 4 hydrology has **not started**.

## Shipping architecture

The shipping pipeline keeps Stage 2's nonlinear continental base elevation, terrain regimes, ridged mountain shaping, valley shaping, and climate-independent terrain height.

Stage 3 changes only the broad terrain-structure coordinates:

```text
world X/Z
   ↓
64-block deterministic macro warp lattice
   ↓
interpolated warp offset
   ↓
4-block terrain-structure lattice
   ↓
warped terrain-structure samples
   ↓
interpolated per-column structure
   ↓
Stage 2 terrain shaping
```

Continentalness remains sampled at the original world coordinates. Biome temperature and moisture remain sampled at their accepted coordinates and continue to drive the existing biome classifier unchanged.

No new `FastNoiseLite` stack was added for Stage 3. The explicit warp uses deterministic integer-hash/value vectors and interpolation, while the existing terrain-structure noise is sampled at the warped coordinates.

## Performance implementation

The first correct Stage 3 implementation was too close to the hard performance limit on some CI runners. The final shipping cache therefore performs the expensive/repeated work once and reuses it:

- 64-block macro warp vectors are cached once per padded chunk,
- terrain structure is sampled on a 4-block lattice,
- the fixed 16×16 padded-cache X/Z lattice indices and smooth interpolation weights are precomputed,
- per-column structure interpolation uses arithmetic instead of repeated floor/divide/smoothstep work,
- Stage 2 terrain height is climate-independent, so the shipping cache does not pay for an unused second terrain-climate noise pair,
- biome temperature/moisture sampling and biome classification remain unchanged.

The legal world height remains **150** and the Stage 2 safe generated terrain top remains **138**.

## Exact Stage 3 gate evidence

On commit `75f292429741063a25b5cb8818ca03774dd06ae3`, the dedicated Stage 3 gate reported:

- generation/cache p95: **0.907 ms** over 320 measured padded chunks,
- generation/cache mean: **0.870 ms**,
- hard gate: **< 1.0 ms p95**,
- terrain minimum: **3**,
- terrain maximum: **86**,
- terrain vertical range: **83 blocks**,
- warp samples: **1,089**,
- mean warp magnitude: **11.54 blocks**,
- maximum warp magnitude: **27.66 blocks**,
- maximum adjacent-column warp delta: **1.17 blocks**,
- long-range warp changes: **1,021 / 1,089**,
- terrain-structure samples materially changed: **7,943 / 9,409**,
- final terrain heights changed versus the unwarped structure field: **3,240 / 9,409**,
- mountain-capable height changes: **1,483**,
- runtime/public structure comparisons: **1,024 passed**,
- runtime/public height comparisons: **1,024 passed**,
- maximum runtime/public structure error: approximately **7.45e-9**,
- cross-chunk overlap comparisons: **192 passed**,
- deterministic chunk comparisons: **4 passed**.

The Stage 2 compatibility gate on the same commit also remained green at **0.900 ms p95**, with the accepted 3–86 terrain range, 150-block legal height, climate independence, halo continuity and determinism intact.

## Regression fixes made while gating Stage 3

Two old integration gates still waited for threaded streaming using the pre-consolidation rule `chunk_count == expected_chunk_count`. The modern streamer can legitimately retain completed chunks from the previous center while moving to a distant fixture. Those tests now use the established shipping readiness contract instead:

- at least the expected active chunk count,
- playable collision ring ready,
- remesh queue idle.

This changed test readiness only; it did not change world generation or biome thresholds.

The public shipping runtime also explicitly forwards the Stage 3 worker entry point so `WorkerThreadPool` resolves the worker against the public runtime script and always publishes completed chunk results.

## Stage 3 acceptance criteria

Stage 3 is considered complete only when the final `world-overhaul` head has all of the following green:

- Stage 3 domain-warp gate,
- Stage 2 structured-terrain compatibility gate,
- full Acceptance Gate,
- threaded chunk-stream soak including persisted relaunch,
- biome contiguity and zone-size gates,
- localized-water compatibility gate,
- standalone world gate,
- mining/placement/inventory/touch regressions,
- lighting/diagnostic gates,
- Android export setup and actual debug APK export.

## Boundary to Stage 4

Stage 3 does **not** implement oceans, coast topology, rivers, lakes, ponds, river corridors, or water-level logic.

The low continental basins retained from Stage 2 exist only to keep the current localized-water behavior physically compatible. Explicit hydrology begins in Stage 4 after Stage 3 is accepted.