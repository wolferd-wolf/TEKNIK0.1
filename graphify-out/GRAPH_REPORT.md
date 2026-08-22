# Graph Report - TEKNIK0.1  (2026-08-20)

## Corpus Check
- cluster-only mode — file stats not available

## Summary
- 157 nodes · 229 edges · 14 communities (10 shown, 4 thin omitted)
- Extraction: 97% EXTRACTED · 3% INFERRED · 0% AMBIGUOUS · INFERRED: 7 edges (avg confidence: 0.84)
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `6c6c703b`
- Run `git rev-parse HEAD` and compare to check if the graph is stale.
- Run `graphify update .` after code changes (no API cost).

## Community Hubs (Navigation)
- luanti_carpathian_reference.cpp
- teknik_carpathian.cpp
- TeknikVoxelMesher
- AuditResult
- CompareResult
- .build
- NoiseParams
- NoiseParams
- teknik_voxel_mesher.hpp
- teknik_carpathian_library_init
- install_gradle_build_template.sh
- setup_debug_keystore.sh
- setup_release_keystore.sh

## God Nodes (most connected - your core abstractions)
1. `TeknikVoxelMesher` - 35 edges
2. `AuditResult` - 18 edges
3. `CompareResult` - 14 edges
4. `NoiseParams` - 11 edges
5. `NoiseParams` - 11 edges
6. `ColumnResult` - 9 edges
7. `TeknikCarpathianSampler` - 9 edges
8. `sample_column()` - 8 edges
9. `surface_height_carpathian()` - 8 edges
10. `audit_seed()` - 7 edges

## Surprising Connections (you probably didn't know these)
- `sample_column_single_probe()` --calls--> `fractal2d()`  [INFERRED]
  tools/reference/luanti_carpathian_surface_adapter_study.cpp → tools/reference/luanti_carpathian_reference.cpp
- `sample_column_single_probe()` --calls--> `fractal3d()`  [INFERRED]
  tools/reference/luanti_carpathian_surface_adapter_study.cpp → tools/reference/luanti_carpathian_reference.cpp
- `sample_column_single_probe()` --calls--> `lerp()`  [INFERRED]
  tools/reference/luanti_carpathian_surface_adapter_study.cpp → tools/reference/luanti_carpathian_reference.cpp
- `compare_seed()` --calls--> `sample_column()`  [INFERRED]
  tools/reference/luanti_carpathian_surface_adapter_study.cpp → tools/reference/luanti_carpathian_reference.cpp
- `initialize_teknik_carpathian()` --calls--> `register_teknik_voxel_mesher()`  [INFERRED]
  native/carpathian/src/teknik_carpathian.cpp → native/carpathian/src/teknik_voxel_mesher.hpp

## Import Cycles
- None detected.

## Communities (14 total, 4 thin omitted)

### Community 0 - "luanti_carpathian_reference.cpp"
Cohesion: 0.14
Nodes (28): path, audit_seed(), ColumnResult, height, hills, mountains, ridges, steps (+20 more)

### Community 1 - "teknik_carpathian.cpp"
Cohesion: 0.14
Nodes (19): ModuleInitializationLevel, PackedInt32Array, RefCounted, ease_curve(), fractal2d(), fractal3d(), initialize_teknik_carpathian(), lerp_value() (+11 more)

### Community 2 - "TeknikVoxelMesher"
Cohesion: 0.09
Nodes (21): RefCounted, TeknikVoxelMesher, BIOME_DESERT, BIOME_FOREST, BIOME_PLAINS, BIOME_ROCKY, BLOCK_AIR, BLOCK_DIRT (+13 more)

### Community 3 - "AuditResult"
Cohesion: 0.12
Nodes (17): AuditResult, elapsed_ms, grid, largest_low_relief_area_blocks2, largest_low_relief_cells, largest_low_relief_equiv_width_blocks, max_h, mean_h (+9 more)

### Community 4 - "CompareResult"
Cohesion: 0.15
Nodes (13): CompareResult, exact_pct, fast_max, fast_min, fast_p95, fast_slope_le1_pct, largest_low_relief_cells, largest_low_relief_equiv_width (+5 more)

### Community 6 - "NoiseParams"
Cohesion: 0.22
Nodes (9): NoiseParams, eased_2d, lacunarity, octaves, offset, persist, scale, seed (+1 more)

### Community 7 - "NoiseParams"
Cohesion: 0.22
Nodes (9): NoiseParams, eased_2d, lacunarity, octaves, offset, persist, scale, seed (+1 more)

### Community 8 - "teknik_voxel_mesher.hpp"
Cohesion: 0.40
Nodes (3): Color, Dictionary, Vector2i

### Community 9 - "teknik_carpathian_library_init"
Cohesion: 0.40
Nodes (5): GDExtensionBool, GDExtensionClassLibraryPtr, GDExtensionInitialization, GDExtensionInterfaceGetProcAddress, teknik_carpathian_library_init()

## Knowledge Gaps
- **73 isolated node(s):** `height`, `hills`, `mountains`, `ridges`, `height` (+68 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **4 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `TeknikVoxelMesher` connect `TeknikVoxelMesher` to `teknik_voxel_mesher.hpp`, `.is_tree_origin`, `.build`?**
  _High betweenness centrality (0.360) - this node is a cross-community bridge._
- **Why does `AuditResult` connect `AuditResult` to `luanti_carpathian_reference.cpp`?**
  _High betweenness centrality (0.187) - this node is a cross-community bridge._
- **Why does `CompareResult` connect `CompareResult` to `luanti_carpathian_reference.cpp`?**
  _High betweenness centrality (0.142) - this node is a cross-community bridge._
- **What connects `height`, `hills`, `mountains` to the rest of the system?**
  _73 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `luanti_carpathian_reference.cpp` be split into smaller, more focused modules?**
  _Cohesion score 0.13548387096774195 - nodes in this community are weakly interconnected._
- **Should `teknik_carpathian.cpp` be split into smaller, more focused modules?**
  _Cohesion score 0.13538461538461538 - nodes in this community are weakly interconnected._
- **Should `TeknikVoxelMesher` be split into smaller, more focused modules?**
  _Cohesion score 0.09090909090909091 - nodes in this community are weakly interconnected._