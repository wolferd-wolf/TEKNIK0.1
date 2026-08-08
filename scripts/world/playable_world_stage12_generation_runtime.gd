extends "res://scripts/world/playable_world_stage11_generation_runtime.gd"

const STAGE12_DATA := preload("res://scripts/world/playable_world_stage11_water_biome_data.gd")
const STAGE12_GENERATION_CACHE := preload("res://scripts/world/playable_world_stage10_generation_cache_fast.gd")
const SHIPPING_STAGE12_CACHE := preload("res://scripts/world/playable_world_stage12_cache_fast.gd")
const SHIPPING_STAGE12_MESHER := preload("res://scripts/world/playable_world_stage12_mesher.gd")
const FROZEN_STAGE11_RUNTIME := preload("res://scripts/world/playable_world_stage11_generation_runtime.gd")
const STAGE12_STAGE2_RUNTIME_BASE := preload("res://scripts/world/playable_world_stage2_generation_runtime.gd")

# Stable public Stage 12 runtime. The hard generation/cache path remains the
# exact accepted Stage 10 cache used by Stage 11 (the frozen path was
# SHIPPING_STAGE10_GENERATION_CACHE.build). Stage 12 only reduces post-generation
# expression preparation and mesher bookkeeping overhead.
# build_expression_codes internally preserves the accepted build_transition_codes
# + build_hydrology_codes contract from Stage 11.

func _init() -> void:
	data = STAGE12_DATA.new()


func _build_column_caches(coord: Vector2i) -> Dictionary:
	return STAGE12_GENERATION_CACHE.build(coord, data)


static func _stage3_worker_build_chunk(
	coord: Vector2i,
	overrides_snapshot: Dictionary,
	revision: int,
	result_sink: Dictionary,
	result_mutex: Mutex,
	result_key: String
) -> void:
	var started_usec := Time.get_ticks_usec()
	var sampler = STAGE12_DATA.new()
	var cache_started_usec := Time.get_ticks_usec()
	var caches: Dictionary = STAGE12_GENERATION_CACHE.build(coord, sampler)
	var cache_usec := Time.get_ticks_usec() - cache_started_usec
	var heights: PackedInt32Array = caches.get("heights", PackedInt32Array())
	var biomes: PackedByteArray = caches.get("biomes", PackedByteArray())
	var water_types: PackedByteArray = caches.get("stage7_water_types", PackedByteArray())
	var terrain_modifiers: PackedByteArray = caches.get(
		"stage9_terrain_modifiers",
		PackedByteArray()
	)
	var mesh_height := mini(
		STAGE12_DATA.OVERHAUL_WORLD_HEIGHT,
		STAGE12_STAGE2_RUNTIME_BASE._effective_mesh_height(coord, heights, overrides_snapshot) + 2
	)
	var mesh_started_usec := Time.get_ticks_usec()
	var expression_codes: Dictionary = SHIPPING_STAGE12_CACHE.build_expression_codes(
		caches,
		sampler
	)
	var transition_codes: PackedByteArray = expression_codes.get(
		"transition_codes",
		PackedByteArray()
	)
	var hydrology_codes: PackedByteArray = expression_codes.get(
		"hydrology_codes",
		PackedByteArray()
	)
	var blocked_tree_columns: PackedInt32Array = FROZEN_STAGE11_RUNTIME._stage6_blocked_tree_columns(
		coord,
		caches,
		sampler
	)
	var mesh_data: Dictionary = SHIPPING_STAGE12_MESHER.build(
		coord,
		heights,
		overrides_snapshot,
		12,
		mesh_height,
		STAGE12_DATA.SEA_LEVEL,
		biomes,
		water_types,
		terrain_modifiers,
		transition_codes,
		hydrology_codes,
		sampler,
		blocked_tree_columns
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
