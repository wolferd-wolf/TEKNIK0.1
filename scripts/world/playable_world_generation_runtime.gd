extends "res://scripts/world/playable_world_stage11_generation_runtime.gd"

const SHIPPING_DATA := preload("res://scripts/world/playable_world_carpathian_data.gd")
const SHIPPING_GENERATION_CACHE := preload("res://scripts/world/playable_world_carpathian_generation_cache_fast.gd")
const SHIPPING_STAGE12_CACHE := preload("res://scripts/world/playable_world_stage12_cache_fast.gd")
const SHIPPING_STAGE12_MESHER := preload("res://scripts/world/playable_world_stage12_mesher.gd")
const FROZEN_STAGE11_RUNTIME := preload("res://scripts/world/playable_world_stage11_generation_runtime.gd")
const STAGE12_STAGE2_RUNTIME_BASE := preload("res://scripts/world/playable_world_stage2_generation_runtime.gd")

const COLLISION_FACES_KEY := "_collision_faces"

var _stream_apply_happened_this_frame := false

# Public shipping runtime. With no native extension this is the accepted Stage
# 13 generator. When TeknikCarpathianSampler is present, only the base terrain
# height source changes; the accepted water, biome, expression and meshing paths
# stay in place.
#
# The render mesh remains an engine resource created on the main thread. Worker
# tasks only prepare plain collision triangle data. That avoids renderer access
# from WorkerThreadPool while letting collision creation skip Mesh readback.

func _init() -> void:
	data = SHIPPING_DATA.new()


func _build_column_caches(coord: Vector2i) -> Dictionary:
	return SHIPPING_GENERATION_CACHE.build(coord, data)


static func _collision_faces_from_mesh_data(mesh_data: Dictionary) -> PackedVector3Array:
	var vertices: PackedVector3Array = mesh_data.get("vertices", PackedVector3Array())
	var indices: PackedInt32Array = mesh_data.get("indices", PackedInt32Array())
	if vertices.is_empty() or indices.is_empty() or indices.size() % 3 != 0:
		return PackedVector3Array()
	var faces := PackedVector3Array()
	faces.resize(indices.size())
	for index_position in range(indices.size()):
		var vertex_index := int(indices[index_position])
		if vertex_index < 0 or vertex_index >= vertices.size():
			return PackedVector3Array()
		faces[index_position] = vertices[vertex_index]
	return faces


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
	var collision_data_started_usec := Time.get_ticks_usec()
	mesh_data[COLLISION_FACES_KEY] = _collision_faces_from_mesh_data(mesh_data)
	var collision_data_usec := Time.get_ticks_usec() - collision_data_started_usec
	var result := {
		"coord": coord,
		"revision": revision,
		"mesh_data": mesh_data,
		"cache_usec": cache_usec,
		"mesh_usec": mesh_usec,
		"collision_data_usec": collision_data_usec,
		"mesh_height": mesh_height,
		"compute_usec": Time.get_ticks_usec() - started_usec,
	}
	result_mutex.lock()
	result_sink[result_key] = result
	result_mutex.unlock()


func _pump_builds() -> void:
	var pump_start := Time.get_ticks_usec()
	_collect_completed_build_tasks()
	_stream_apply_happened_this_frame = false
	var applied_before := build_results_applied
	# If a nearby chunk is waiting for collision, give that collision the frame
	# instead of stacking it with another render-resource upload. This alternates
	# the two expensive main-thread phases while the collision ring catches up.
	var apply_budget := 0 if not collision_add_queue.is_empty() else MAX_BUILD_APPLIES_PER_FRAME
	_apply_completed_builds(apply_budget)
	_stream_apply_happened_this_frame = build_results_applied > applied_before
	_dispatch_build_tasks()
	max_pump_usec = maxi(max_pump_usec, Time.get_ticks_usec() - pump_start)


func _create_entry(coord: Vector2i, mesh_data: Dictionary, with_collision: bool) -> Dictionary:
	# Let the frozen base path create only the render resource. Collision uses the
	# worker-prepared triangle stream below, avoiding ArrayMesh.create_trimesh_shape().
	var entry: Dictionary = super._create_entry(coord, mesh_data, false)
	if entry.is_empty():
		return {}
	var collision_faces: PackedVector3Array = mesh_data.get(
		COLLISION_FACES_KEY,
		PackedVector3Array()
	)
	entry["collision_faces"] = collision_faces
	if with_collision:
		var collision := _create_collision_from_faces(collision_faces)
		if collision == null:
			var root_to_free := entry.get("root") as Node3D
			if is_instance_valid(root_to_free):
				root_to_free.free()
			return {}
		var root_node := entry.get("root") as Node3D
		root_node.add_child(collision)
		entry["collision"] = collision
	return entry


func _create_collision_from_faces(faces: PackedVector3Array) -> StaticBody3D:
	if faces.is_empty() or faces.size() % 3 != 0:
		return null
	var shape := ConcavePolygonShape3D.new()
	shape.backface_collision = true
	shape.set_faces(faces)
	var body := StaticBody3D.new()
	body.name = "TerrainCollision"
	body.collision_layer = 1
	body.collision_mask = 1
	var shape_node := CollisionShape3D.new()
	shape_node.shape = shape
	body.add_child(shape_node)
	return body


func _pump_collisions() -> void:
	# Never pay render-resource apply and concave collision construction in the
	# same frame. The queued nearby collision is handled on the following frame,
	# and _pump_builds() then withholds another visual apply until it is attached.
	if not _stream_apply_happened_this_frame and not collision_add_queue.is_empty():
		var coord: Vector2i = collision_add_queue.pop_front()
		collision_add_queued.erase(coord)
		if loaded.has(coord) and needs_collision(coord):
			var start := Time.get_ticks_usec()
			var entry: Dictionary = loaded[coord]
			var faces: PackedVector3Array = entry.get("collision_faces", PackedVector3Array())
			var collision := _create_collision_from_faces(faces)
			if collision != null:
				var root_node := entry.get("root") as Node3D
				root_node.add_child(collision)
				entry["collision"] = collision
				loaded[coord] = entry
			last_collision_usec = maxi(last_collision_usec, Time.get_ticks_usec() - start)
	for _index in range(2):
		if collision_remove_queue.is_empty():
			break
		var coord: Vector2i = collision_remove_queue.pop_front()
		collision_remove_queued.erase(coord)
		if not loaded.has(coord) or needs_collision(coord):
			continue
		var entry: Dictionary = loaded[coord]
		var collision := entry.get("collision") as StaticBody3D
		if is_instance_valid(collision):
			collision.queue_free()
		entry["collision"] = null
		loaded[coord] = entry
