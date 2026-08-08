extends "res://scripts/world/playable_world_stage4_generation_runtime.gd"

const FROZEN_STAGE9_DATA := preload("res://scripts/world/playable_world_stage9_terrain_data.gd")
const FROZEN_STAGE9_CACHE := preload("res://scripts/world/playable_world_stage9_cache_fast.gd")
const FROZEN_STAGE9_MESHER := preload("res://scripts/world/playable_world_stage9_mesher.gd")
const FROZEN_STAGE6_TREE_HELPER := preload("res://scripts/world/playable_world_stage6_cache_fast.gd")

func _init() -> void:
	data = FROZEN_STAGE9_DATA.new()

func _build_column_caches(coord: Vector2i) -> Dictionary:
	return FROZEN_STAGE9_CACHE.build(coord, data)

static func _stage6_blocked_tree_columns(
	coord: Vector2i,
	caches: Dictionary,
	sampler
) -> PackedInt32Array:
	var heights: PackedInt32Array = caches.get("heights", PackedInt32Array())
	if heights.is_empty():
		return PackedInt32Array()
	var biomes: PackedByteArray = caches.get("biomes", PackedByteArray())
	var world_fields: PackedFloat32Array = caches.get("world_fields", PackedFloat32Array())
	var width: int = 16
	var min_x: int = coord.x * 12 - 2
	var min_z: int = coord.y * 12 - 2
	var max_x: int = min_x + width - 1
	var max_z: int = min_z + width - 1
	var features: Array = caches.get("stage6_features", [])
	if features.is_empty():
		features = sampler.stage6_collect_features_for_cached_bounds(
			min_x, min_z, max_x, max_z, width, world_fields, heights
		)
	return FROZEN_STAGE6_TREE_HELPER._collect_blocked_tree_columns(
		min_x, min_z, width, heights, biomes, world_fields, features, sampler
	)

static func _stage3_worker_build_chunk(
	coord: Vector2i,
	overrides_snapshot: Dictionary,
	revision: int,
	result_sink: Dictionary,
	result_mutex: Mutex,
	result_key: String
) -> void:
	var started_usec := Time.get_ticks_usec()
	var sampler = FROZEN_STAGE9_DATA.new()
	var cache_started_usec := Time.get_ticks_usec()
	var caches: Dictionary = FROZEN_STAGE9_CACHE.build(coord, sampler)
	var cache_usec := Time.get_ticks_usec() - cache_started_usec
	var heights: PackedInt32Array = caches.get("heights", PackedInt32Array())
	var biomes: PackedByteArray = caches.get("biomes", PackedByteArray())
	var water_types: PackedByteArray = caches.get("stage7_water_types", PackedByteArray())
	var terrain_modifiers: PackedByteArray = caches.get("stage9_terrain_modifiers", PackedByteArray())
	var mesh_height := mini(
		FROZEN_STAGE9_DATA.OVERHAUL_WORLD_HEIGHT,
		STAGE2_RUNTIME_BASE._effective_mesh_height(coord, heights, overrides_snapshot) + 2
	)
	var mesh_started_usec := Time.get_ticks_usec()
	var blocked_tree_columns := _stage6_blocked_tree_columns(coord, caches, sampler)
	var mesh_data: Dictionary = FROZEN_STAGE9_MESHER.build(
		coord,
		heights,
		overrides_snapshot,
		12,
		mesh_height,
		FROZEN_STAGE9_DATA.SEA_LEVEL,
		biomes,
		water_types,
		terrain_modifiers,
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
