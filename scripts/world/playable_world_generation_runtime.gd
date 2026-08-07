extends "res://scripts/world/playable_world_stage3_generation_runtime.gd"

# Stable public runtime path. Stage 2's compatibility contract remains present
# through the inherited `_stage2_build_column_caches_for_sampler` entry point,
# while Stage 3's shipping cache still calls
# `sampler.build_provisional_terrain(terrain_fields)` after warped-structure
# lattice interpolation.
