# TEKNIK Build Plan — Session: Native Acceleration (C++ / Rust) + Cave Systems

## Verified starting state (audited from repo, branch `feature/rotational-power-network`)
- Godot **4.3.stable** pinned everywhere; GL Compatibility renderer; Android export is **arm64-v8a only**, NDK r23c, minSdk 24.
- Shipping path: `scenes/main.tscn` -> `scripts/world/playable_world_port.gd` -> `playable_world_generation_runtime.gd` (one dedicated generation thread, WorkerThreadPool fallback, per-chunk revisions) + `playable_world_stage13_data.gd` (terrain) + `playable_world_stage12_mesher.gd` (meshing, includes water faces).
- The world is a **2D heightfield**: continentalness/structure/temperature/moisture fields, rivers, biomes, trees. **No caves exist anywhere** — every stage doc explicitly excluded them.
- **No ore blocks.** Block IDs stop at 9 (air..leaves + water wheel/shaft/drill).
- Native layer: `native/carpathian/src/teknik_carpathian.cpp` (terrain sampler) and `teknik_voxel_mesher.hpp/.cpp` (`TeknikVoxelMesher`) already target **godot-cpp (GDExtension)**. CI workflow `native-voxel-mesher-equivalence.yml` clones godot-cpp 4.3, generates an SConstruct inline, builds a **desktop Linux** library, and runs an equivalence gate. It is **not wired into the shipping runtime**, has **no Android build**, **no committed SConstruct/build profile**, **no `.gdextension` file in the repo**, and the native mesher has **no water support**.
- **Rust: nothing yet.** Local toolchains verified: `cargo`, `rustc`, `clippy`, `miri`, `scons`, `g++`. CI runs ubuntu-24.04.

## Language charter (division of labor — one owner per module, never dual-port)
| Language | Mechanism | Owns | Why |
|---|---|---|---|
| **C++** | GDExtension (godot-cpp) | Render-facing hot paths: voxel mesher core, bulk `PackedByteArray` transforms | Zero-overhead per-voxel loops, direct Variant/PackedArray access; code + CI equivalence infrastructure already exists |
| **Rust** | GDExtension (godot-rust / gdext) | Deterministic simulation & field evaluation: cave/noise fields now; later mechanical network solver and item-logistics ticks | Memory safety + cargo test/clippy/miri fit deterministic, growing simulation modules |
| **GDScript** | engine-native | Always the reference implementation and permanent fallback for every native module | Keeps gates green without native libs; single behavioral source of truth |

Both native languages compile to arm64-v8a via the pinned NDK and load through GDExtension. Neither may become a hard dependency of play.

## Rules (apply to every step below)
1. **Native is always optional at runtime.** If any native library is missing or fails to load, the GDScript path must carry full behavior. Gates exercise both paths.
2. **Parity before performance.** Native output must match the GDScript reference exactly (mesh arrays / field values) on fixed seeds before any perf claim is made.
3. **Perf gates after parity.** Baselines are recorded as CI artifacts; a regression beyond the recorded threshold fails CI.
4. Every native module gets an **Android arm64 build in the same session** that introduces it. Desktop-only work must say so explicitly in the step.
5. Worldgen fields are **pure deterministic functions** of (seed, world coordinates). No wall-clock, no unseeded randomness.
6. One numbered item = one commit. Commit message format `[TEKNIK] step N: <short description>`.
7. Guesses and design decisions go in `## Decisions` at the bottom, committed alongside the code.
8. Do not build anything not listed here. Extra ideas go in `## Deferred`.

## Steps

### Session N0 — Native infrastructure hardening (C++)
1. ✅ **DONE** (6a43e23) — SConstruct + build_profile committed; CI uses them; local full build of the .so succeeded at -j2.
2. ✅ **DONE** (8214787, 17ebf77) — `.gdextension`, NativeLoader autoload, dual-path headless gate; both runs PASS. Required fixing a pre-existing corrupted theme resource that aborted project parse.
3. ✅ **DONE** (committed with workflow job `android-arm64-build`) — builds template_debug + template_release arm64 .so with NDK r23c, verifies aarch64 ELF, uploads artifacts. Gate runs on PR (CI-only; no local SDK by design). Committed .gdextension already declares matching android paths so APK export bundles them automatically.

### Session N1 — C++ mesher reaches shipping quality
4. ✅ **DONE** — discovery: full parity implementation already shipped in headers (AO, sky light, biome colors, trees); water faces are NOT part of this contract (stage12 layers overrides before calling; fluid geometry is separate). Gate: existing equivalence test passes byte-exact (18/18 geometry, 23388 colors, max error 0). See docs/native-mesher-step4-6-evidence.md.
5. ✅ **DONE** — integration pre-existed inside stage12 `_build_base_mesh()` (ClassDB probe, GDScript oracle fallback). Gates: threaded build PASS (17 tasks), hitch PASS (62.9% peak reduction), NativeLoader dual-path PASS.
6. ✅ **DONE** — baselines recorded in docs/native-mesher-step4-6-evidence.md (native mean 0.194 ms vs GDScript 56.18 ms per chunk; 261x p95). Regression policy stated there; CI equivalence workflow publishes timing JSON artifacts on every run.

### Session R0 — Rust bootstrap (gdext)
7. ✅ **DONE** — `native/rust_fields` on godot 0.1.3 (gdext), own `teknik_rust_fields.gdextension` (entry `gdext_rust_init`), loads alongside the C++ extension. Local gates: fmt OK, clippy -D warnings clean, RUST_FIELDS_GATE_PASS (probe class answers 42 through ClassDB). CI job `rust-fields-build` added: lint + desktop + NDK r23c android arm64 builds + headless gate.
8. Define the **cave field contract**: pure functions `field(seed, x, y, z) -> float` + tunnel/carve decision helpers. Write the GDScript reference implementation and freeze fixed parity vectors. Port to Rust. *Gate: Rust matches the frozen vectors exactly; GDScript reference matches the same vectors.*

### Session W1 — Caves, stage 14 (GDScript reference first)
9. ✅ **DONE** — Stage 14 data: 3D cave fields — spaghetti tunnels (product of two 3D fields near zero) plus cheese caverns (single low-frequency threshold, deep bands only). Depth guards: no carving within 4 blocks of the surface except a sparse deterministic entrance field; no carving under ocean/river columns above a safety margin; clamp to `y >= min_y + 2`.
10. ✅ **DONE** — Carve during column fill: after height assignment, before water/tree fill. River/ocean columns follow the guard rules. Fully deterministic per world coordinate.
11. ✅ **DONE** — Extend boundary testing: cave seams across chunk borders + the existing 26-topology diagnostic re-run with caves enabled. Same-seed neighbor agreement must be exact.
12. ✅ **DONE** — Verify lighting: sky light does not leak underground; AO darkens interiors correctly. *Gate: screenshot evidence standing inside a cave.*
13. ✅ **DONE** — Measure chunk generation time against the mobile budget. **Decision point:** if over budget, flip cave field evaluation to the Rust module from R0 (parity already proven). Record numbers either way.

### Session A — Metals & smelting (progression loop fix; ores are placed post-carve so veins show in cave walls)
14. Ore generation: coal, iron, copper veins in stone, depth-weighted, seeded deterministically, respecting persistent edits. Ore blocks mineable, drop raw items.
15. Furnace block + smelting UI: fuel + input -> output over time. Recipes: raw iron -> ingot, sand -> glass, log -> charcoal.
16. New items (ingots, coal, charcoal); machine recipes (water wheel, shaft, drill) now cost iron.

### Later sessions (accepted direction, each becomes its own build-plan session)
- **B — Mechanical expansion:** hand crank, cogwheel, gearbox, windmill, SU/RPM HUD.
- **C — Item logistics:** chest, conveyor belt, funnel/filter -> drill auto-mines into chest.
- **D — Steam tier:** boiler, steam engine, one SU-hungry machine.
- **E — Fluids:** tank, pipes, SU-driven pump, automated boiler feed.
- **F — Android hardening:** performance overlay, machine save/load, full on-device pass.
- **Cleanup track:** archive superseded stage2–stage12 world variants after proving unused (consolidation discipline).

## Definition of done (this plan)
Native C++ mesher ships behind a runtime flag with Android arm64 support and recorded perf wins; a Rust gdext module exists with CI and owns the cave field; caves generate deterministically with boundary/lighting/perf gates green; ores + smelting close the progression loop. All previous gates remain green.

## Report format
Commit log in order (hash + message). No prose summary in place of the commit log.

## Decisions
- (to be filled during execution)

## Deferred
- Aquifers / cave water and waterfall physics.
- Day/night cycle (still deferred; static sky stays until factories need it).
- Greedy meshing (revisit only if native mesher still misses budget).
- Native collision generation.
- Rails/trains, ships, airships (movable structures get their own session series).
- Merging `feature/procedural-pixel-textures` (decide before Session A; ore readability favors merging early).

## Decisions
- Step 2: The native extension registers only `TeknikCarpathianSampler`; `TeknikVoxelMesher` exists in headers but was never registered or implemented for shipping. NativeLoader therefore probes a list of known classes and passes via the sampler until N1 registers the mesher.
- Step 2: Godot only loads extensions listed in `.godot/extension_list.cfg`, regenerated by an editor scan (`--editor --quit`). All gate procedures must run the editor scan before headless gates when the `.gdextension` set changes.
- Step 2 fix: `assets/shadcn_dark_theme.tres` was syntactically invalid (theme items outside a `[resource]` section, `#` comment lines which .tres does not support), so project.godot failed to fully parse (error 43) on every runtime/headless start. Repaired by adding the `[resource]` section and converting comments to `;`. Also replaced non-standard `[gui] theme/default_theme = ExtResource(...)` with the standard `gui/theme/custom` string setting.
