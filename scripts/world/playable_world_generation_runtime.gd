extends "res://scripts/world/playable_world_stage11_generation_runtime.gd"

const SHIPPING_DATA := preload("res://scripts/world/playable_world_carpathian_data.gd")
const SHIPPING_GENERATION_CACHE := preload("res://scripts/world/playable_world_carpathian_generation_cache_fast.gd")
const SHIPPING_STAGE12_CACHE := preload("res://scripts/world/playable_world_stage12_cache_fast.gd")
const SHIPPING_STAGE12_MESHER := preload("res://scripts/world/playable_world_stage12_mesher.gd")
const FROZEN_STAGE11_RUNTIME := preload("res://scripts/world/playable_world_stage11_generation_runtime.gd")
const STAGE12_STAGE2_RUNTIME_BASE := preload("res://scripts/world/playable_world_stage2_generation_runtime.gd")

const PREPARED_COLLISION_META := &"_teknik_prepared_collision_shape"

# Public shipping runtime. With no native extension this is the accepted Stage
# 13 generator. When TeknikCarpathianSampler is present, only the base terrain
# height source changes; the accepted water, biome, expression and meshing paths
# stay in place.
#
# Chunk geometry is generated as pure arrays first, then each worker prepares
# its own ArrayMesh and trimesh collision resource before publishing the result.
# The active SceneTree remains main-thread-only: applying a completed chunk now
# only creates/attaches lightweight nodes instead of uploading mesh arrays and
# extracting collision triangles during the frame.

func _init() -> void:
	data = SHIPPING_DATA.new()


func _build_column_caches(coord: Vector2i) -> Dictionary:
	return SHIPPING_GENERATION_CACHE.build(coord, data)


static func _prepare_chunk_resources(mesh_data: Dictionary) -> Dictionary:
	var vertices: PackedVector3Array = mesh_data.get("vertices", PackedVector3Array())
	if vertices.is_empty():
		return {}
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = mesh_data.get("normals", PackedVector3Array())
	arrays[Mesh.ARRAY_COLOR] = mesh_data.get("colors", PackedColorArray())
	arrays[Mesh.ARRAY_INDEX] = mesh_data.get("indices", PackedInt32Array())
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	if mesh.get_surface_count() <= 0:
		return {}
	var collision_shape: Shape3D = mesh.create_trimesh_shape()
	if collision_shape is ConcavePolygonShape3D:
		collision_shape.backface_collision = true
		mesh.set_meta(PREPARED_COLLISION_META, collision_shape)
	return {
		"mesh": mesh,
		"collision_shape": collision_shape,
	}


static func _stage3_worker_build_chunk(
	coord: Vector2i,
	overrides_snapshot: Dictionary,
	revision: int,
	result_sink: Dictionary,
	result_mutex: Mutex,
	result_key: String
) -> void:
	var started_usec := Time.get_ticks_usec()
	var sampler = SHIPPING_DATA.new()
	var cache_started_usec := Time.get_ticks_usec()
	var caches: Dictionary = SHIPPING_GENERATION_CACHE.build(coord, sampler)
	var cache_usec := Time.get_ticks_usec() - cache_started_usec
	var heights: PackedInt32Array = caches.get("heights", PackedInt32Array())
	var biomes: PackedByteArray = caches.get("biomes", PackedByteArray())
	var water_types: PackedByteArray = caches.get("stage7_water_types", PackedByteArray())
	var terrain_modifiers: PackedByteArray = caches.get("stage9_terrain_modifiers", PackedByteArray())
	var mesh_height := mini(
		SHIPPING_DATA.OVERHAUL_WORLD_HEIGHT,
		STAGE12_STAGE2_RUNTIME_BASE._effective_mesh_height(coord, heights, overrides_snapshot) + 2
	)
	var mesh_started_usec := Time.get_ticks_usec()
	var expression_codes: Dictionary = SHIPPING_STAGE12_CACHE.build_expression_codes(caches, sampler)
	var transition_codes: PackedByteArray = expression_codes.get("transition_codes", PackedByteArray())
	var hydrology_codes: PackedByteArray = expression_codes.get("hydrology_codes", PackedByteArray())
	var blocked_tree_columns: PackedInt32Array = FROZEN_STAGE11_RUNTIME._stage6_blocked_tree_columns(
		coord, caches, sampler
	)
	var mesh_data: Dictionary = SHIPPING_STAGE12_MESHER.build(
		coord,
		heights,
		overrides_snapshot,
		12,
		mesh_height,
		SHIPPING_DATA.SEA_LEVEL,
		biomes,
		water_types,
		terrain_modifiers,
		transition_codes,
		hydrology_codes,
		sampler,
		blocked_tree_columns
	)
	var mesh_usec := Time.get_ticks_usec() - mesh_started_usec
	var resource_started_usec := Time.get_ticks_usec()
	var prepared_resources := _prepare_chunk_resources(mesh_data)
	var resource_usec := Time.get_ticks_usec() - resource_started_usec
	var result := {
		"coord": coord,
		"revision": revision,
		"mesh_data": mesh_data,
		"prepared_mesh": prepared_resources.get("mesh"),
		"prepared_collision_shape": prepared_resources.get("collision_shape"),
		"cache_usec": cache_usec,
		"mesh_usec": mesh_usec,
		"resource_usec": resource_usec,
		"mesh_height": mesh_height,
		"compute_usec": Time.get_ticks_usec() - started_usec,
	}
	result_mutex.lock()
	result_sink[result_key] = result
	result_mutex.unlock()


func _create_entry(coord: Vector2i, mesh_data: Dictionary, with_collision: bool) -> Dictionary:
	var prepared_mesh := mesh_data.get("_prepared_mesh") as ArrayMesh
	if prepared_mesh == null:
		return super._create_entry(coord, mesh_data, with_collision)
	if prepared_mesh.get_surface_count() <= 0:
		return {}
	var root_node := Node3D.new()
	root_node.name = "Chunk_%d_%d" % [coord.x, coord.y]
	root_node.position = Vector3(coord.x * CHUNK_SIZE, 0, coord.y * CHUNK_SIZE)
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "TerrainMesh"
	mesh_instance.mesh = prepared_mesh
	mesh_instance.material_override = material
	root_node.add_child(mesh_instance)
	var collision: StaticBody3D
	if with_collision:
		collision = _create_collision(prepared_mesh)
		if collision == null:
			return {}
		root_node.add_child(collision)
	return {"root": root_node, "mesh": prepared_mesh, "collision": collision}


func _create_collision(mesh: ArrayMesh) -> StaticBody3D:
	var shape := mesh.get_meta(PREPARED_COLLISION_META, null) as ConcavePolygonShape3D
	if shape == null:
		return super._create_collision(mesh)
	var body := StaticBody3D.new()
	body.name = "TerrainCollision"
	body.collision_layer = 1
	body.collision_mask = 1
	var shape_node := CollisionShape3D.new()
	shape_node.shape = shape
	body.add_child(shape_node)
	return body


func _apply_completed_builds(max_applies: int) -> void:
	# Preserve the frozen runtime's revision/atomic-swap behavior. The only extra
	# step is passing the worker-prepared mesh through the private mesh-data copy
	# consumed by our _create_entry() override.
	var applies := 0
	while applies < max_applies and not build_apply_queue.is_empty():
		var apply_data: Dictionary = build_apply_queue.pop_front()
		var coord: Vector2i = apply_data.get("coord", Vector2i.ZERO)
		var revision := int(apply_data.get("revision", 0))
		var latest_revision := int(build_revisions.get(coord, 0))
		var replacing := bool(apply_data.get("replacing", false))
		var still_wanted := distance(coord, center) <= RENDER_RADIUS
		var target_state_valid := loaded.has(coord) if replacing else not loaded.has(coord)
		if revision != latest_revision or not still_wanted or not target_state_valid:
			stale_results_discarded += 1
			if revision != latest_revision and still_wanted:
				if pending_rebuilds.has(coord) or not loaded.has(coord):
					_queue_latest_revision(coord, true)
			continue
		var result: Dictionary = apply_data.get("result", {})
		var mesh_data: Dictionary = result.get("mesh_data", {}).duplicate(false)
		var prepared_mesh := result.get("prepared_mesh") as ArrayMesh
		if prepared_mesh != null:
			mesh_data["_prepared_mesh"] = prepared_mesh
		var apply_started_usec := Time.get_ticks_usec()
		var applied := false
		if replacing:
			if _swap_chunk(coord, mesh_data):
				pending_rebuilds.erase(coord)
				rebuild_deadlines.erase(coord)
				applied = true
			else:
				atomic_failures += 1
				rebuild_deadlines[coord] = Time.get_ticks_msec() + EDIT_DEBOUNCE_MSEC
		else:
			applied = _commit_chunk(coord, mesh_data, false)
		var apply_usec := Time.get_ticks_usec() - apply_started_usec
		last_apply_usec = maxi(last_apply_usec, apply_usec)
		if not applied:
			if not replacing:
				_queue_latest_revision(coord, true)
			continue
		last_face_count = int(mesh_data.get("face_count", 0))
		build_results_applied += 1
		applies += 1
		print(
			"THREADED_CHUNK_STREAM_COMPLETE coord=%s revision=%d cache_ms=%.3f mesh_ms=%.3f resource_ms=%.3f background_ms=%.3f apply_ms=%.3f latency_ms=%.3f"
			% [
				coord,
				revision,
				int(result.get("cache_usec", 0)) / 1000.0,
				int(result.get("mesh_usec", 0)) / 1000.0,
				int(result.get("resource_usec", 0)) / 1000.0,
				int(result.get("compute_usec", 0)) / 1000.0,
				apply_usec / 1000.0,
				(Time.get_ticks_usec() - int(apply_data.get("queued_at_usec", 0))) / 1000.0,
			]
		)
