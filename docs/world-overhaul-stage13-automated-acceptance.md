# World Overhaul Stage 13 — Automated Acceptance / Device Pending

Stage 13 automated/current-shipping acceptance is complete on `world-overhaul`.

Validated implementation head before the documentation-only commits:

`66d81146fbe759d5799fb435b55c6fce6eeaa2f0`

Stage 13 is **not fully complete** until the resulting Android APK passes explicit real-device acceptance. PR #46 remains intentionally draft and unmerged. Do not merge until real-device approval is received and an explicit merge instruction is given.

## Final visual-audit correction: river periodicity

The first Stage 13 statistical audit passed numerically, but inspection of the required river diagnostic map exposed a real visual defect: river channels appeared as long, near-parallel translated copies with conspicuously regular spacing.

The problem was structural, not a map-rendering artifact. The accepted Stage 5 river field used a fixed 224-block lane spacing and one shared meander/phase pattern, so adjacent corridors inherited the same motion translated laterally.

Stage 13 corrects that without adding another procedural-noise stack or introducing a watershed simulation:

- each river lane receives a deterministic lane offset;
- each lane receives its own deterministic low-frequency meander sequence;
- the accepted river valley/channel shaping contract remains intact;
- adjacent lane centers remain safely separated;
- no additional FastNoiseLite field is introduced.

The final river-pattern audit reports:

- minimum adjacent center separation: approximately **135.801 blocks**;
- maximum adjacent center separation: approximately **312.641 blocks**;
- separation range: approximately **176.840 blocks**;
- adjacent lanes with identical motion signatures: **0**;
- theoretical minimum center separation under configured displacement limits: **88 blocks**.

The regenerated exact-head river, water-type and final-biome diagnostic maps were visually reviewed. The prior translated-copy stripe pattern is gone, river spacing and meander visibly vary, and water/biome topology remains coherent.

## Performance architecture

Two intermediate Stage 13 cache approaches were rejected because they violated the existing hard performance budget:

- full post-Stage-10 wrapper rebuild: approximately **1.359 ms p95**;
- sparse patch wrapper under hosted-runner load: approximately **1.440 ms p95**.

The hard gate was not relaxed.

The final architecture keeps the accepted Stage 10 cache immutable for historical Stages 10–12 and gives Stage 13 its own one-pass hot cache. Stage 13 computes its independent river-center selection inside the same generation pass rather than rebuilding generated columns afterward.

Exact-head successful Stage 13 shipping benchmark, unchanged methodology:

- 16 padded chunks;
- 4 warmups;
- 20 repeats;
- 320 measured chunks;
- minimum: **0.460 ms**;
- mean: **0.483 ms**;
- p95: **0.520 ms**;
- maximum: **2.064 ms**;
- hard gate: **p95 < 1.0 ms**;
- result: **PASS**.

The gate is p95, not maximum.

## River correctness evidence

The Stage 13 river-quality gate additionally proves:

- deterministic generation across three chunks and 15 compared arrays;
- direct/cache equivalence over five chunks and **1,280 columns**;
- a topology-aware real river fixture at chunk `(-62, -43)`;
- **136 river columns** exercised by direct/cache comparison;
- **160 total water columns** exercised by direct/cache comparison;
- four seam pairs and **128 overlap columns** compared;
- no height/water mismatches;
- no seam mismatches;
- no de-periodization failures.

## Multi-seed statistical audit

Fixed deterministic audit seeds:

`734921`, `19088743`, `11235813`

Aggregate sampled area:

- sampled columns: **3,981,312**;
- land columns: **3,424,073**.

Biome coverage as a percentage of audited land:

- Plains: **42.4673%**;
- Forest: **18.6872%**;
- Dry Grassland: **23.0204%**;
- Cold Forest: **13.3437%**;
- Dense Forest: **1.5388%**;
- Desert: **0.9426%**.

Hydrology / terrain coverage:

- Ocean: **10.1238%** of sampled columns;
- River: **3.55584%** of sampled columns;
- accepted lakes found: **20**;
- mountain terrain: **12.2141%** of audited land.

No active ecology disappeared and no statistical-audit correctness failure was reported.

## Diagnostic maps

The exact-head Stage 13 gate produced and verified all required diagnostic PNGs:

1. continentalness;
2. terrain height;
3. mountain strength;
4. river mask;
5. water type;
6. temperature;
7. moisture;
8. final biome.

Exact-head evidence artifact:

- workflow: **TEKNIK World Overhaul Stage 13 Final Acceptance Gate**;
- run: `31251151315`;
- final unchanged rerun: **green**;
- artifact ID: `9020064671`;
- artifact SHA-256: `3371d0cfa1ab3e0e547a33eb7ce9477f7e79242d614f55f7e32db6cbd51a97d8`.

## Full current-shipping acceptance

The exact-head **TEKNIK Acceptance Gate** run `31251151310` is green on `66d81146fbe759d5799fb435b55c6fce6eeaa2f0`.

It passed:

- strict project parsing;
- generation baseline checks;
- 150-block-overhaul compatibility through the retained historical height gates;
- shipping-world wiring;
- headless launch;
- graphical consolidated-world acceptance;
- mining targeting;
- mining and chunk-boundary remeshing;
- placement collision and rejection behavior;
- playable-world boundary / loaded-edge cases;
- inventory model and world transactions;
- touch controls.

The exact-head regression matrix also has green results for Stages 2, 3, 4, 5, 6, 7, 8, 10, 11 and 12, plus biome contiguity, chunk-stream soak, water, standalone-world, inventory, touch, lighting, diagnostic logging and Android export/configuration checks.

## Historical Stage 9 hosted-runner timing exception

One historical, non-shipping gate remains red: **TEKNIK World Overhaul Stage 9 Terrain Modifier Gate**.

This is a timing-only exception in the frozen historical Stage 9 oracle. All Stage 9 correctness evidence remains exact on every attempt:

- determinism passes;
- seam continuity passes;
- Stage 8 height/biome equivalence passes;
- terrain-modifier correctness passes;
- synthetic modifier checks pass;
- broad world audit passes.

Only the frozen historical 320-sample performance p95 is currently hovering above its strict `< 1.0 ms` threshold on the current GitHub-hosted Ubuntu runner image.

Unchanged current-runner samples include approximately:

`1.034`, `1.003`, `1.002`, `1.000`, `1.020`, `1.015`, `1.107`, and `1.107 ms p95` across repeated attempts.

The same accepted Stage 9 implementation previously passed at **0.934 ms p95** on the Stage 12 validated implementation run. No Stage 9 source, benchmark methodology, or threshold was changed in response to the Stage 13 reruns.

This exception does not describe the current shipping generator. The exact-head Stage 13 shipping generator independently passes at **0.520 ms p95** under the same hard `< 1.0 ms` requirement.

The Stage 9 result is therefore recorded transparently as a frozen historical hosted-runner timing exception rather than papered over by weakening the gate.

## Android device-test build

Exact-head Android export:

- workflow run: `31251151316` — **green**;
- artifact ID: `9020064989`;
- artifact name: `teknik-step5-consolidated-apk-export`;
- source commit: `66d81146fbe759d5799fb435b55c6fce6eeaa2f0`;
- APK package: `com.wolferdwolf.teknik`;
- versionCode: `1`;
- versionName: `0.1.0`;
- minSdkVersion: `24`;
- targetSdkVersion: `34`;
- compileSdkVersion: `34`;
- APK size: **69,965,756 bytes**;
- APK Signature Scheme v2 verification: **pass**;
- zipalign verification: **pass**;
- APK SHA-256: `010d42b983da37c012bc9d1e2d3e5c4ec1372f82c0ad0c7961baa16ab2fcb970`;
- GitHub Actions artifact digest: `e8a17c51b595063644a632916b9ba42f6741f78385189112b1f1f39a9ae7bdeb`.

The user-handoff ZIP downloaded from the artifact service was independently unpacked and checked. It contains the same 69,965,756-byte APK with the same APK SHA-256 above. The local handoff ZIP itself has SHA-256 `0d375cffa59f08100dbf300f4f58e8980aa795f7ed0b309654fdfdb809b48717`; this ZIP hash differs from the GitHub Actions artifact digest because the downloaded archive is a transport package, while the contained APK identity is unchanged.

## Required real-device acceptance

Before Stage 13 can be declared complete, the exact-head APK must be played on the target Android device and checked for:

- extended traversal across multiple chunk boundaries;
- at least one clear biome transition;
- mountain approach / climbing;
- ocean and coast appearance;
- river traversal, including confirmation that rivers do not read as repeated parallel strips;
- lake or pond shoreline behavior;
- mining;
- placement;
- inventory updates;
- touch responsiveness;
- absence of blank chunks, visible chunk seams, freezes or crashes.

## Stage boundary

**Stage 13 automated/current-shipping acceptance is complete. Real-device acceptance is pending.**

PR #46 must remain **draft and unmerged** until both conditions are met:

1. explicit real-device approval;
2. an explicit instruction to merge.
