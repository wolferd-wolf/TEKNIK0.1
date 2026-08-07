extends "res://scripts/world/playable_world_stage4_generation_runtime.gd"

const SHIPPING_STAGE6_DATA := preload("res://scripts/world/playable_world_stage6_tree_consistent_data.gd")
const SHIPPING_STAGE6_CACHE := preload("res://scripts/world/playable_world_stage6_cache_fast.gd")
const SHIPPING_STAGE6_MESHER := preload("res://scripts/world/playable_world_stage6_mesher.gd")

# Stable public runtime path. Stage 6 keeps the accepted Stage 5 terrain/ocean/
# river path and adds sparse contained lake/pond basins before final meshing.
# Streaming, remeshing and the 150-block active-content mesh ceiling remain the
# proven inherited implementations. The shipping Stage 6 data subclasses add
# topology-equivalent candidate prefilters and reuse the Stage 5 padded cache
# when a basin center is already available there. Wet tree-origin columns are
# also passed to the Stage 6 mesher so gameplay queries, collision and visuals
# agree that trees do not originate inside generated water.

func _init() -> void:
	data = SHIPPING_STAGE6_DATA.new()


func _build_column_caches(coord: Vector2i) -> Dictionary:
	return SHIPPING_STAGE6_CACHE.build(coord, data)


static func _stage3_worker_build_chunk(
	coord: Vector2i,
	overrides_snapshot: Dictionary,
	revision: int,
	result_sink: Dictionary,
	result_mutex: Mutex,
	result_key: String
) -> void:
	var started_usec := Time.get_ticks_usec()
	var sampler = SHIPPING_STAGE6_DATA.new()
	var cache_started_usec := Time.get_ticks_usec()
	var caches: Dictionary = SHIPPING_STAGE6_CACHE.build(coord, sampler)
	var cache_usec := Time.get_ticks_usec() - cache_started_usec
	var heights: PackedInt32Array = caches.get("heights", PackedInt32Array())
	var biomes: PackedByteArray = caches.get("biomes", PackedByteArray())
	var blocked_tree_columns: PackedInt32Array = caches.get(
		"blocked_tree_columns",
		PackedInt32Array()
	)
	var mesh_height := STAGE2_RUNTIME_BASE._effective_mesh_height(coord, heights, overrides_snapshot)
	var mesh_started_usec := Time.get_ticks_usec()
	var mesh_data: Dictionary = SHIPPING_STAGE6_MESHER.build(
		coord,
		heights,
		overrides_snapshot,
		12,
		mesh_height,
		SHIPPING_STAGE6_DATA.SEA_LEVEL,
		biomes,
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
