extends "res://scripts/world/playable_world_stage4_generation_runtime.gd"

const STAGE5_DATA := preload("res://scripts/world/playable_world_stage5_generation_data.gd")
const STAGE5_CACHE := preload("res://scripts/world/playable_world_stage5_cache_fast.gd")
const STAGE5_MESHER := preload("res://scripts/world/playable_world_mesher.gd")

# Frozen Stage 5 oracle. Later hydrology stages keep the stable shipping runtime
# path, while the Stage 5 gate uses this class so rivers are measured without
# lakes/ponds contaminating the accepted river behavior or performance result.

func _init() -> void:
	data = STAGE5_DATA.new()


func _build_column_caches(coord: Vector2i) -> Dictionary:
	return STAGE5_CACHE.build(coord, data)


static func _stage3_worker_build_chunk(
	coord: Vector2i,
	overrides_snapshot: Dictionary,
	revision: int,
	result_sink: Dictionary,
	result_mutex: Mutex,
	result_key: String
) -> void:
	var started_usec := Time.get_ticks_usec()
	var sampler = STAGE5_DATA.new()
	var cache_started_usec := Time.get_ticks_usec()
	var caches: Dictionary = STAGE5_CACHE.build(coord, sampler)
	var cache_usec := Time.get_ticks_usec() - cache_started_usec
	var heights: PackedInt32Array = caches.get("heights", PackedInt32Array())
	var biomes: PackedByteArray = caches.get("biomes", PackedByteArray())
	var mesh_height := STAGE2_RUNTIME_BASE._effective_mesh_height(coord, heights, overrides_snapshot)
	var mesh_started_usec := Time.get_ticks_usec()
	var mesh_data: Dictionary = STAGE5_MESHER.build(
		coord,
		heights,
		overrides_snapshot,
		12,
		mesh_height,
		STAGE5_DATA.SEA_LEVEL,
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
