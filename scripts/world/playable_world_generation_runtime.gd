extends "res://scripts/world/playable_world_stage3_generation_runtime.gd"

const STAGE3_DATA := preload("res://scripts/world/playable_world_generation_data.gd")
const STAGE3_CACHE := preload("res://scripts/world/playable_world_stage3_cache.gd")
const STAGE3_MESHER := preload("res://scripts/world/playable_world_mesher.gd")
const STAGE2_RUNTIME_BASE := preload("res://scripts/world/playable_world_stage2_generation_runtime.gd")

# Stable public runtime path. Stage 2's compatibility contract remains present
# through the inherited `_stage2_build_column_caches_for_sampler` entry point,
# while Stage 3 keeps Stage 2's `sampler.build_provisional_terrain(terrain_fields)`
# formula after warped-structure interpolation.
#
# The shipping wrapper uses the optimized cache builder for both synchronous
# diagnostics and threaded workers. Terrain-only climate became unused in Stage
# 2, so its reserved slots reuse the already-sampled biome climate values rather
# than paying for a duplicate pair of noise calls. Biome classification itself is
# unchanged.


func _build_column_caches(coord: Vector2i) -> Dictionary:
	return STAGE3_CACHE.build(coord, data)


static func _stage3_worker_build_chunk(
	coord: Vector2i,
	overrides_snapshot: Dictionary,
	revision: int,
	result_sink: Dictionary,
	result_mutex: Mutex,
	result_key: String
) -> void:
	var started_usec := Time.get_ticks_usec()
	var sampler = STAGE3_DATA.new()
	var cache_started_usec := Time.get_ticks_usec()
	var caches: Dictionary = STAGE3_CACHE.build(coord, sampler)
	var cache_usec := Time.get_ticks_usec() - cache_started_usec
	var heights: PackedInt32Array = caches.get("heights", PackedInt32Array())
	var biomes: PackedByteArray = caches.get("biomes", PackedByteArray())
	var mesh_height := STAGE2_RUNTIME_BASE._effective_mesh_height(
		coord,
		heights,
		overrides_snapshot
	)
	var mesh_started_usec := Time.get_ticks_usec()
	var mesh_data: Dictionary = STAGE3_MESHER.build(
		coord,
		heights,
		overrides_snapshot,
		12,
		mesh_height,
		STAGE3_DATA.SEA_LEVEL,
		biomes
	)
	var result := {
		"coord": coord,
		"revision": revision,
		"mesh_data": mesh_data,
		"cache_usec": cache_usec,
		"mesh_usec": Time.get_ticks_usec() - mesh_started_usec,
		"mesh_height": mesh_height,
		"compute_usec": Time.get_ticks_usec() - started_usec,
	}
	result_mutex.lock()
	result_sink[result_key] = result
	result_mutex.unlock()
