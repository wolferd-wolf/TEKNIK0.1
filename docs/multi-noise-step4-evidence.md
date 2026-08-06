# Multi-Noise Stage 1 — Step 4 Gate Evidence

## Scope

Step 4 replaces the hard climate-biome border with normalized biome weights and a deterministic voxel-resolution transition. It remains inside the single consolidated 12x12 playable-world generator. It does not add caves, rivers, ore changes, new biomes, or Step 5 integration work.

## Production behavior

The accepted four warped noise values per column are unchanged. Temperature and moisture are converted into normalized plains, forest, desert, and rocky weights using bounded smooth transition bands around the Step 3 climate thresholds.

Because voxel surface blocks are discrete, the weights are resolved through a deterministic three-block world-space patch selector. Pure climate interiors remain visually stable, while mixed climate bands contain proportionate neighboring biome materials and vegetation. The three-block patch size prevents one-block salt-and-pepper noise without producing large square biome tiles.

The shipping runtime still obtains one `Vector4` per padded column and derives both height and the resolved blended biome from that same sample. Direct world queries, tree generation, the biome cache, the shipping mesher, collision generation, mining, placement, and saved overrides therefore use one shared result rather than parallel blend paths.

## Gate history

- Rejected run `31095646795`, provisional commit `1c506adc2013aa96c10cf7e6546b9f8577154c83`: strict parsing passed, but the first source-isolation assertion scanned through `biome_at()`, whose legitimate purpose is to obtain the one permitted column sample. The assertion therefore falsely reported that the weight helper added noise calls. The scan boundary was narrowed to the weight and deterministic-selection helpers only. Production behavior was not accepted from this run, and the provisional commit was replaced rather than stacked.
- Accepted implementation run `31095772686`, commit `81e1d2167560ddfd3375fbf45aa898c0e3e95626`: strict parsing, the dedicated Step 4 contract/distribution/coherence/integration/benchmark gate, standalone shipping-world proof, headless and graphical acceptance, mining, placement, 12-block boundaries, loaded-edge stress, inventory, crafting, and touch controls all passed.

## Distribution and blending evidence

The quantitative scan covered `66,049` positions from `-1024` through `1024` on both horizontal axes at eight-block spacing.

| Resolved biome | Count | Ratio |
|---|---:|---:|
| Plains | 20,188 | 30.565186% |
| Forest | 23,250 | 35.201139% |
| Desert | 10,783 | 16.325758% |
| Rocky | 11,828 | 17.907917% |

`28,054` positions (`42.474526%`) carried at least two biome weights of `0.05` or greater. The average largest weight was `0.877789`, showing that biome interiors remain dominant while a substantial transition band is genuinely mixed.

Across `131,584` compared neighbor edges, `24,742` changed resolved biome, for a transition ratio of `18.803198%`. A separate full-resolution 257x257 coherence scan rejected isolated one-cell islands. Positive, negative, east, and south chunk-boundary cache comparisons matched direct world queries.

The generated weight map shows smooth broad gradients between biome colors. The resolved map preserves the large warped regions while expressing those gradients as deterministic three-block material patches. GPT visually reviewed both maps and the gameplay screenshot; none was blank, chunk-restarted, hard-threshold-only, or dominated by isolated one-block noise.

## Performance evidence

Environment: Ubuntu 24.04.4, four-vCPU Intel Xeon 6973P-C runner, Godot 4.3. The benchmark measured `640` padded 16x16 caches per path, alternating measurement order after four warm-up repetitions.

Step 3 discrete height-and-biome cache:

- Minimum: `0.228 ms/chunk`
- Maximum: `0.290 ms/chunk`
- Mean: `0.2443640625 ms/chunk`
- Median: `0.244 ms/chunk`
- p95: `0.259 ms/chunk`
- Total: `156.393 ms`

Step 4 blended height-and-biome cache:

- Minimum: `0.468 ms/chunk`
- Maximum: `0.577 ms/chunk`
- Mean: `0.5075 ms/chunk`
- Median: `0.506 ms/chunk`
- p95: `0.536 ms/chunk`
- Total: `324.800 ms`

Weight calculation and deterministic resolution add `0.2631359375 ms` mean cost per chunk, a `107.681929%` increase over the measured discrete cache. The absolute `0.536 ms` p95 remains below the committed `1.0 ms` native-escalation threshold.

The discrete and blended height checksums are both `1763840`, proving Step 4 preserved the accepted heightmap. The discrete biome checksum is `291440`; the blended checksum is `305600`, confirming the resolver changed biome output rather than passing the Step 3 field through unchanged.

GPT independently recalculated count, minimum, maximum, mean, median, p95, total, absolute cost, relative cost, distribution ratios, mixed-weight ratio, transition ratio, and checksum equality from the artifact's raw data. Every recalculated value matched CI.

## Artifact

Accepted implementation artifact `8965426750` has digest `sha256:0db42e092d7c76849584ee2dbb52800ad6435ecb61500c5c624bacb5ae24f89f`. It contains both Step 4 diagnostic maps, all 1,280 raw timing samples, environment capture, gameplay screenshots, and the complete inherited gate logs.

## Gate conclusion

The Step 4 implementation and evidence are accepted provisionally pending a final CI run on the exact evidence-bearing commit. Step 5 has not started. The pull request remains draft and unmerged pending explicit instruction.
