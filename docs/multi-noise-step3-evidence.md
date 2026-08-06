# Multi-Noise Stage 1 — Step 3 Gate Evidence

## Scope

Step 3 adds climate-driven biome selection to the single consolidated 12x12 playable-world generator. It defines exactly four biomes: plains, forest, desert, and rocky. It does not add biome-border blending, caves, rivers, or ore changes.

## Production behavior

The accepted warped temperature and moisture samples select one biome per column:

- Desert: temperature at least `0.12` and moisture at most `-0.08`.
- Forest: moisture at least `0.10`, unless the desert rule matched first.
- Rocky: temperature at most `-0.12`, unless the forest rule matched first.
- Plains: remaining climate combinations.

The shipping runtime samples one `Vector4` per padded column, then derives both height and biome from that same sample vector. The base contract remains exactly four `FastNoiseLite.get_noise_2d` calls per column. The biome cache is passed into the shipping mesher, and the dedicated gate compares mesher block resolution against direct world-data queries across positive and negative chunks.

Surface behavior is intentionally discrete in Step 3:

- Plains and forest use grass over dirt.
- Desert uses sand.
- Rocky uses stone.
- Existing low/coastal columns remain sand in every biome.

Forest retains the existing deterministic tree lattice and adds a denser supplemental lattice. Plains retains the existing tree behavior. Desert and rocky generate no trees. Step 4 owns gradual biome-weight blending and has not started.

## Gate history

- Rejected run `31091251816`, provisional commit `34010f5bc8cad52d964a3f55fa15736bbd79b4f1`: strict parsing stopped before behavioral testing because the first dedicated gate omitted explicit integer annotations in several inferred values. Production behavior was not accepted from this run. The provisional commit was replaced rather than stacked.
- Rejected run `31091878022`, provisional commit `3b173aaa861334dd24a8c702b53158f7cbcedbcb`: the dedicated Step 3 gate and standalone shipping-world proof passed, but the inherited terrain acceptance test still asserted that every surface must be grass or sand. Rocky terrain intentionally uses stone, so the obsolete inherited expectation was corrected to accept the authorized rocky surface. The production data/mesher equivalence gate had already shown no generator mismatch. This provisional commit was also replaced rather than stacked.
- Accepted implementation run `31092174034`, commit `36f728b872a48d643925e91b07e0d37cbfcae0b6`: strict parsing, the dedicated biome gate, standalone shipping-world proof, headless and graphical consolidated-world acceptance, mining, placement, 12-block boundaries, loaded-edge stress, inventory, crafting, and touch controls all passed.

## Distribution evidence

The quantitative scan covered `66,049` world positions from `-1024` through `1024` on both horizontal axes at eight-block spacing.

| Biome | Count | Ratio |
|---|---:|---:|
| Plains | 19,532 | 29.571984% |
| Forest | 23,621 | 35.762843% |
| Desert | 10,762 | 16.293964% |
| Rocky | 12,134 | 18.371209% |

Across `131,584` compared neighbor edges, `11,761` crossed a biome boundary, for a transition ratio of `8.938017%`. This proves nontrivial regional variation without per-cell speckle.

The generated diagnostic map contains large contiguous warped regions in all four classes. GPT visually reviewed the map and confirmed that it is not blank, collapsed, restarted per chunk, or dominated by isolated single-cell noise. The graphical gameplay artifact also visibly contains grass, forest, sand, and exposed rocky surfaces in the shipping scene.

## Performance evidence

Environment: Ubuntu 24.04.4, four-vCPU AMD EPYC 7763 runner, Godot 4.3. The benchmark measured `640` padded 16x16 column caches per path.

Step 2 height-only cache:

- Minimum: `0.255 ms/chunk`
- Maximum: `0.320 ms/chunk`
- Mean: `0.2633875 ms/chunk`
- Median: `0.2615 ms/chunk`
- p95: `0.276 ms/chunk`
- Total: `168.568 ms`

Step 3 shared height-and-biome cache:

- Minimum: `0.370 ms/chunk`
- Maximum: `0.455 ms/chunk`
- Mean: `0.3865515625 ms/chunk`
- Median: `0.385 ms/chunk`
- p95: `0.402 ms/chunk`
- Total: `247.393 ms`

Biome selection adds `0.1231640625 ms` mean cost per chunk, a `46.761544%` relative increase over the measured height-only path. The `0.402 ms` p95 remains below the committed `1.0 ms` native-escalation threshold.

The height-only and shared-cache checksums are both `1763840`, proving that Step 3 preserved the accepted Step 2 height output. The biome checksum is `291440`.

GPT independently recalculated sample count, minimum, maximum, mean, median, p95, total time, absolute cost, relative cost, and checksum equality from all `1,280` raw timing samples. The recalculated values matched the CI report exactly.

## Artifact

Accepted artifact `8963990193` has digest `sha256:a4785860a47ae9dd3683e513f9a96bcd94adbbe660c1e45e44bd9702476febb5`. It contains the raw timing arrays, environment capture, dedicated biome map, gameplay screenshot, and all inherited gate logs and screenshots.

## Gate conclusion

Step 3 is accepted on the reviewed implementation. Step 4 biome-weight blending has not started. The pull request remains draft and unmerged pending explicit instruction.
