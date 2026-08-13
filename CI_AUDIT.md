# TEKNIK CI Workflow Audit

Audit performed against `main` before any workflow modifications. No workflow file was changed by this audit.

## Scope

The current `.github/workflows/` tree contains **51 `.yml` workflow files**. GitHub Actions also reports older workflow definitions that are no longer present in the current directory; those stale definitions are not included here.

Classification is based on the workflow name, trigger model, and the actual scripts/files invoked by its jobs. `PERMANENT GATE` means the workflow protects an ongoing subsystem and should remain part of normal PR validation, but its trigger should be scoped to the files it actually exercises. `ONE-OFF DIAGNOSTIC` means the workflow is clearly historical, investigative, prototype/calibration, audit-only, or otherwise not a standing acceptance requirement.

## Audit table

| # | Workflow | Current `on:` block | Subsystem actually tested | Classification |
|---:|---|---|---|---|
| 1 | `acceptance-gate.yml` | `push: branches: [main]`; `pull_request:`; `workflow_dispatch:` | Consolidated playable world acceptance; retired-world reference scan; terrain height; mining/placement; inventory; touch; headless/graphical acceptance | **PERMANENT GATE** |
| 2 | `android-export-step4-gate.yml` | `push: branches: [session/touch-controls-android-export]`; `pull_request:`; `workflow_dispatch:`; `workflow_call:` | Android toolchain, debug keystore, Godot Android export template/Gradle setup, Android preset validation | **PERMANENT GATE** |
| 3 | `android-export-step5-diagnostic.yml` | `push: branches: [session/touch-controls-android-export]`; `pull_request:`; `workflow_dispatch:` | Historical Godot 4.3 Android Gradle-template/root-cause investigation; explicitly records diagnostic-only behavior and no APK output | **ONE-OFF DIAGNOSTIC** |
| 4 | `android-export-step5.yml` | `workflow_dispatch:`; `pull_request: branches: [main], paths: [.github/workflows/android-export-step5.yml, android/**, native/carpathian/**, export_presets.cfg, project.godot, scenes/**, scripts/**]` | Actual Android debug APK export and native Carpathian library packaging | **PERMANENT GATE** |
| 5 | `android-renderer-ab.yml` | `workflow_dispatch:`; `pull_request: branches: [main], paths: [.github/workflows/android-renderer-ab.yml, android/**, native/carpathian/**, export_presets.cfg, project.godot, scenes/**, scripts/**]` | Android Compatibility/OpenGL vs Mobile/Vulkan renderer APK A/B export and verification | **PERMANENT GATE** |
| 6 | `android-threaded-mesher-array-gate.yml` | `pull_request: branches: [main], paths: [scripts/world/playable_world_mesher.gd, tests/android_threaded_mesher_array_gate.gd, workflow]`; `workflow_dispatch:` | Concurrent threaded mesher array/table access and equivalence | **PERMANENT GATE** |
| 7 | `biome-contiguity-gate.yml` | `pull_request:`; `workflow_dispatch:` | Biome macro-zone sizing, minimap regional contiguity, and multi-noise integration | **PERMANENT GATE** |
| 8 | `carpathian-shipping-integration.yml` | `pull_request: branches: [main], paths: [native/carpathian/**, playable-world Carpathian/generation scripts, test, workflow]`; `workflow_dispatch:` | Shipping Carpathian native extension, generation/cache height and water consistency, performance | **PERMANENT GATE** |
| 9 | `chunk-boundary-hole-fix-gate.yml` | `pull_request: branches: [main], paths: [stage12 mesher, test, native/carpathian/**, workflow]`; `workflow_dispatch:` | Chunk-boundary exposed-face/hole suppression and native mesher integration | **PERMANENT GATE** |
| 10 | `chunk-generation-performance-baseline.yml` | `pull_request: branches: [main], paths: [scripts/world/**, native/carpathian/**, test, workflow]`; `workflow_dispatch:` | Shipping chunk worker generation performance baseline | **PERMANENT GATE** |
| 11 | `chunk-hitch-isolation.yml` | `workflow_dispatch:`; `pull_request: branches: [main], paths: [workflow file only]` | Controlled Android hitch isolation experiments; deliberately patches the Actions workspace and proves the production runtime is unchanged | **ONE-OFF DIAGNOSTIC** |
| 12 | `chunk-stream-biome-soak-diagnostic.yml` | `pull_request:`; `workflow_dispatch:` | Fresh/persisted chunk-stream biome soak and PR-vs-main comparison | **ONE-OFF DIAGNOSTIC** |
| 13 | `chunk-stream-state-isolation.yml` | `workflow_dispatch:`; `pull_request: branches: [main], paths: [four playable-world state scripts, test, workflow]` | Chunk-local generation/runtime state isolation | **PERMANENT GATE** |
| 14 | `diagnostic-log-capture-gate.yml` | `pull_request:`; `workflow_dispatch:` | Diagnostic log persistence and worker markers | **ONE-OFF DIAGNOSTIC** |
| 15 | `inventory-vanilla-baseline-gate.yml` | `push: branches: [main]`; `pull_request:`; `workflow_dispatch:` | Inventory transactions, inventory camera/lighting baseline, shipping-world binding | **PERMANENT GATE** |
| 16 | `luanti-carpathian-fast-prototype.yml` | `pull_request: branches: [main], paths: [reference prototype script, test, workflow]`; `workflow_dispatch:` | Luanti/Carpathian native-speed prototype characterization | **ONE-OFF DIAGNOSTIC** |
| 17 | `luanti-carpathian-fnl-calibration.yml` | `pull_request` scoped to Luanti FNL calibration/reference test files; `workflow_dispatch:` | Luanti fractal-noise calibration study | **ONE-OFF DIAGNOSTIC** |
| 18 | `luanti-carpathian-native-benchmark.yml` | `pull_request` scoped to Luanti/native benchmark inputs; `workflow_dispatch:` | Native Carpathian benchmark study | **ONE-OFF DIAGNOSTIC** |
| 19 | `luanti-carpathian-probe12.yml` | `pull_request` scoped to Luanti Probe12 inputs; `workflow_dispatch:` | Probe12 benchmark/characterization experiment | **ONE-OFF DIAGNOSTIC** |
| 20 | `luanti-carpathian-reference.yml` | `pull_request` scoped to Luanti reference-study inputs; `workflow_dispatch:` | Reference implementation study | **ONE-OFF DIAGNOSTIC** |
| 21 | `luanti-carpathian-surface-adapter-study.yml` | `pull_request` scoped to Luanti surface-adapter study inputs; `workflow_dispatch:` | Surface-adapter compatibility/characterization study | **ONE-OFF DIAGNOSTIC** |
| 22 | `native-voxel-mesher-equivalence.yml` | `pull_request` scoped to native mesher/world mesher/test/workflow inputs; `workflow_dispatch:` | Native voxel mesher vs shipping mesher equivalence | **PERMANENT GATE** |
| 23 | `playable-world-mining-port-gate.yml` | `pull_request:`; `workflow_dispatch:` | Consolidated playable-world standalone runtime and removal of legacy/fallback world inheritance | **PERMANENT GATE** |
| 24 | `polish-camera-sensitivity-gate.yml` | `push: branches: [session/polish-world-fixes], paths: [main scene, mobile camera script, test, workflow]`; `pull_request: branches: [main], same paths`; `workflow_dispatch:` | Real-scene mobile camera drag/sensitivity propagation | **PERMANENT GATE** |
| 25 | `polish-leaf-seam-gate.yml` | `push: branches: [session/polish-world-fixes], paths: [main scene, playable mesher/runtime, seam tests, workflow]`; `pull_request: branches: [main], same paths`; `workflow_dispatch:` | Leaf shared-face culling, winding/render settings, seam correctness | **PERMANENT GATE** |
| 26 | `polish-mineable-trees-gate.yml` | `push: branches: [session/polish-world-fixes], paths: [world data/mesher/runtime, inventory hotbar, test, workflow]`; `pull_request: branches: [main], same paths`; `workflow_dispatch:` | Deterministic generated/mineable trees and protected-scope behavior | **PERMANENT GATE** |
| 27 | `polish-minecraft-shadows-gate.yml` | `push: branches: [session/polish-world-fixes], paths: [main scene, world mesher/port/runtime, lighting tests, workflow]`; `pull_request: branches: [main], same paths`; `workflow_dispatch:` | Vanilla-style face dimming, AO, skylight and chunk-boundary lighting | **PERMANENT GATE** |
| 28 | `polish-release-export.yml` | `push: branches: [session/polish-world-fixes], paths: [export_presets.cfg, release-keystore script, workflow]`; `pull_request: branches: [main], same paths`; `workflow_dispatch:` | Signed Android release APK export, signing certificate, manifest and size checks | **PERMANENT GATE** |
| 29 | `polish-step1-apk-audit.yml` | `push: branches: [main], paths: [workflow file only]`; `workflow_dispatch:` | APK size/content forensic audit, duplicate assets and historical port contribution | **ONE-OFF DIAGNOSTIC** |
| 30 | `polish-water-gate.yml` | `push: branches: [session/polish-world-fixes], paths: [main scene, localized water script, test, workflow]`; `pull_request: branches: [main], same paths`; `workflow_dispatch:` | Localized water behavior on forced mobile-world path | **PERMANENT GATE** |
| 31 | `touch-actions-step3-gate.yml` | `pull_request:`; `workflow_dispatch:` | Simulated touch controls, InputMap, hotbar selection, screenshot and clean exit; also calls Step 4 Android export setup | **PERMANENT GATE** |
| 32 | `water-hitch-isolation.yml` | `workflow_dispatch:`; `pull_request: branches: [main], paths: [water scripts, Carpathian data, water test, export/project settings, workflow]` | Android water mesher/export path and optimized APK verification | **PERMANENT GATE** |
| 33 | `world-height-60-gate.yml` | `pull_request:`; `workflow_dispatch:` | WORLD_HEIGHT=60 terrain-shape validation plus real chunk generation/meshing benchmark | **PERMANENT GATE** |
| 34 | `world-map-biome-gate.yml` | `push: branches: [world-overhaul], paths: [map overlay, world port, test, workflow]`; `pull_request: branches: [main], same paths`; `workflow_dispatch:` | World-map overlay/current-biome HUD and Stage 13 terrain map | **PERMANENT GATE** |
| 35 | `world-overhaul-flatness-cause-diagnostic.yml` | `pull_request:`; `workflow_dispatch:` | Multi-seed physical terrain flatness cause analysis using Stage 13 audit/cache data | **ONE-OFF DIAGNOSTIC** |
| 36 | `world-overhaul-plains-open-terrain-gate.yml` | `pull_request:`; `workflow_dispatch:` | Plains terrain distribution/open-terrain statistics and performance | **PERMANENT GATE** |
| 37 | `world-overhaul-plains-terrain-diagnostic.yml` | `pull_request:`; `workflow_dispatch:` | Plains terrain diagnostic investigation | **ONE-OFF DIAGNOSTIC** |
| 38 | `world-overhaul-screenshot-coordinate-diagnostic.yml` | `pull_request:`; `workflow_dispatch:` | Screenshot/coordinate diagnostic investigation for world-overhaul terrain | **ONE-OFF DIAGNOSTIC** |
| 39 | `world-overhaul-stage1-gate.yml` | `workflow_dispatch:` only | Historical Stage 1 legacy-terrain assertion equivalence; comments explicitly say it is retained as a manual historical check | **ONE-OFF DIAGNOSTIC** |
| 40 | `world-overhaul-stage2-terrain-gate.yml` | `pull_request: branches: [main], paths: [Stage 2 generation/cache/runtime scripts, shared generation scripts, port, test, workflow]`; `workflow_dispatch:` | Structured terrain, seams and Stage 2 performance | **PERMANENT GATE** |
| 41 | `world-overhaul-stage3-warp-gate.yml` | `pull_request: branches: [main], paths: [Stage 2/3 generation/cache/runtime scripts, shared generation scripts, test, workflow]`; `workflow_dispatch:` | Macro warp/lattice equivalence, seams and Stage 3 performance | **PERMANENT GATE** |
| 42 | `world-overhaul-stage4-ocean-gate.yml` | `pull_request: branches: [main], paths: [Stage 4 generation/runtime, Stage 3 dependencies, localized water, test, workflow]`; `workflow_dispatch:` | Ocean topology, coast transition and performance | **PERMANENT GATE** |
| 43 | `world-overhaul-stage5-river-gate.yml` | `pull_request: branches: [main], paths: [Stage 5 river generation/data/runtime dependencies, test, workflow]`; `workflow_dispatch:` | River topology/layout and performance | **PERMANENT GATE** |
| 44 | `world-overhaul-stage6-lake-gate.yml` | `pull_request: branches: [main], paths: [Stage 6 lake generation/data/runtime dependencies, test, workflow]`; `workflow_dispatch:` | Lake topology/placement and performance | **PERMANENT GATE** |
| 45 | `world-overhaul-stage7-biome-gate.yml` | `pull_request: branches: [main], paths: [Stage 7 biome data/runtime dependencies, test, workflow]`; `workflow_dispatch:` | Stage 7 biome/water-type generation and performance | **PERMANENT GATE** |
| 46 | `world-overhaul-stage8-biome-gate.yml` | `pull_request: branches: [main], paths: [Stage 8 biome data/runtime dependencies, test, workflow]`; `workflow_dispatch:` | Stage 8 biome transitions/contiguity and performance | **PERMANENT GATE** |
| 47 | `world-overhaul-stage9-terrain-modifier-gate.yml` | `pull_request: branches: [main], paths: [Stage 9 terrain-modifier scripts/dependencies, test, workflow]`; `workflow_dispatch:` | Terrain modifiers and resulting terrain behavior/performance | **PERMANENT GATE** |
| 48 | `world-overhaul-stage10-region-gate.yml` | `pull_request: branches: [main], paths: [Stage 10 region scripts/dependencies, test, workflow]`; `workflow_dispatch:` | Region generation/classification and performance | **PERMANENT GATE** |
| 49 | `world-overhaul-stage11-water-biome-gate.yml` | `pull_request: branches: [main], paths: [Stage 11 water-biome scripts/dependencies, test, workflow]`; `workflow_dispatch:` | Water-biome integration and performance | **PERMANENT GATE** |
| 50 | `world-overhaul-stage12-optimization-gate.yml` | `pull_request: branches: [main], paths: [Stage 12 optimization/mesher scripts/dependencies, test, workflow]`; `workflow_dispatch:` | Stage 12 optimized generation/meshing and performance | **PERMANENT GATE** |
| 51 | `world-overhaul-stage13-acceptance-gate.yml` | `pull_request: paths: [Stage 13 audit/acceptance tests, workflow, scripts/world/**]`; `workflow_dispatch:` | Final Stage 13 river quality, statistical multi-seed audit and required diagnostic maps | **PERMANENT GATE** |

## Key finding

The repository has a mixture of well-scoped gates and broad historical gates. The immediate CI fan-out problem is caused by workflows whose `pull_request` trigger has no `paths:` filter. The clearest examples are `acceptance-gate.yml`, `biome-contiguity-gate.yml`, `inventory-vanilla-baseline-gate.yml`, `playable-world-mining-port-gate.yml`, `touch-actions-step3-gate.yml`, `world-height-60-gate.yml`, and `world-overhaul-plains-open-terrain-gate.yml`; each runs tests outside crafting when an unrelated PR changes only crafting files.

Several workflows are already correctly path-scoped and should not be widened or rewritten unnecessarily. Examples include the threaded mesher gate, chunk-generation performance baseline, Carpathian shipping integration, Android renderer A-B, polish gates, Stage 2, Stage 3, Stage 4, and Stage 13. Their existing path filters provide the model for Step 2.

The `acceptance-gate.yml` job is intentionally broad in what it validates: it touches world, mining, placement, inventory and touch acceptance tests. It therefore needs a deliberate union of the actual production/test inputs used by those steps rather than a generic `scripts/**` catch-all.

The diagnostic classification is deliberately conservative. Workflows explicitly named diagnostic, historical, prototype, calibration, benchmark study, audit, or isolation are marked `ONE-OFF DIAGNOSTIC` and are not candidates for Step 2 changes unless the owner later promotes them to permanent gates.

## Step 1 status

- Branch created: `fix/ci-path-scoping`
- Audit report committed as `CI_AUDIT.md`
- No workflow file modified
- No crafting, inventory, water, or terrain source code modified
- Step 2 path-filter work is intentionally **not** started
