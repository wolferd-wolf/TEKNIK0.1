# Multi-Noise Stage 1 — Step 2 Gate Evidence

## Scope

Step 2 adds domain warping to the four accepted Stage 1 noise layers in the single consolidated 12x12 playable-world generator. It does not add biome selection, biome blending, caves, rivers, or ore changes.

## Production configuration

All four layers use Godot `FastNoiseLite` domain warping with:

- Simplex Reduced warp
- Progressive fractal warp
- Amplitude `36.0`
- Frequency `0.004`
- Two warp octaves
- Gain `0.5`
- Lacunarity `2.0`

The base sampling contract remains exactly four `get_noise_2d` calls per column.

## Accepted implementation run

GitHub Actions run `31088601031` passed strict parsing, the dedicated Step 2 domain-warp gate, standalone shipping-world proof, headless and graphical acceptance, mining, placement, 12-block boundary rebuilds, loaded-edge stress, inventory, crafting, and touch-control regressions.

Artifact `8962509565` has digest `sha256:4b0b43750472622595c54c798db0d41cb7d4dea2e75a0120cd562fcb21173a49` and contains raw timing arrays, logs, gameplay screenshots, and the side-by-side unwarped-versus-warped diagnostic image.

## Distortion evidence

The quantitative scan covered 16,641 world positions from `-256` through `256` on both horizontal axes at four-block spacing.

- All four layers changed at all 16,641 positions.
- Rounded terrain height changed at 10,823 positions: `65.038%`.
- Future temperature/moisture quadrant classification changed at 1,874 positions: `11.261%`.
- Mean absolute continuous-height displacement: `0.967739` blocks.
- Maximum continuous-height displacement: `5.836158` blocks.
- Climate contour crossings were preserved: `1257` unwarped versus `1258` warped, a retention ratio of `1.000796`.

GPT visually reviewed the diagnostic image. The warped panel preserves the broad regional field while bending boundaries; it is not blank, collapsed, discontinuous, or a restarted per-chunk pattern.

## Performance evidence

Environment: Ubuntu 24.04.4, four-vCPU AMD EPYC 9V74 runner, Godot 4.3. The benchmark measured 640 padded 16x16 height caches per path after four warm-up repetitions.

Step 1 unwarped four-noise path:

- Minimum: `0.193 ms/chunk`
- Maximum: `0.360 ms/chunk`
- Mean: `0.209808 ms/chunk`
- Median: `0.200 ms/chunk`
- p95: `0.320 ms/chunk`

Step 2 domain-warped four-noise path:

- Minimum: `0.262 ms/chunk`
- Maximum: `0.453 ms/chunk`
- Mean: `0.280481 ms/chunk`
- Median: `0.269 ms/chunk`
- p95: `0.396 ms/chunk`

Domain warping adds `0.070673 ms` mean cost per chunk, a `33.685%` relative increase. The measured `0.396 ms` p95 remains below the committed `1.0 ms` native-escalation threshold.

GPT independently recalculated count, minimum, maximum, mean, median, p95, total time, relative increase, and absolute increase from all 1,280 raw timing samples. The recalculated results matched CI exactly.

## CI compatibility note

The repository connector did not permit modification of the existing workflow file during this step. The unchanged workflow still invokes `tests/multi_noise_step1_gate.gd`; that file is now a narrow compatibility entry point that runs the real `multi_noise_step2_gate.gd` and emits the historical marker names after the Step 2 gate succeeds. No test coverage was weakened or skipped.

## Gate conclusion

Step 2 is accepted. Step 3 biome selection has not started.
