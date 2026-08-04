extends "res://scripts/world/chunk_manager.gd"

# Mobile-only port of the world and mining pipeline from wolferd-wolf/TEKNIK,
# branch rebuild/playable-world. Desktop keeps the existing ChunkManager so the
# rest of TEKNIK0.1 remains unchanged.
@export var force_playable_world_port: bool = false

const LEGACY_CHUNK_SIZE := 12
const LEGACY_WORLD_HEIGHT := 30
const LEGACY_RENDER_RADIUS := 3
const LEGACY_COLLISION_RADIUS := 1
const LEGACY_UNLOAD_RADIUS := 4
const LEGACY_BUILD_BUDGET_USEC := 5500
const LEGACY_COLLISION_ADDS_PER_FRAME := 1
const LEGACY_COLLISION_REMOVES_PER_FRAME := 2
const LEGACY_SEA_LEVEL := 7
const LEGACY_WORLD_SEED := 734921
const LEGACY_SAVE_PATH := "user://teknik_world_v1.json"
const LEGACY_HEIGHT_CACHE_WIDTH := LEGACY_CHUNK_SIZE + 2
const LEGACY_EDIT_REBUILD_DEBOUNCE_MSEC := 75

const LEGACY_FACE_DIRECTIONS: Array[Vector3i] = [
	Vector3i(0, 1, 0), Vector3i(0, -1, 0),
	Vector3i(1, 0, 0), Vector3i(-1, 0, 0),
	Vector3i(0, 0, 1), Vector3i(0, 0, -1),
]
const LEGACY_FACE_NORMALS: Array[Vector3] = [
	Vector3.UP, Vector3.DOWN, Vector3.RIGHT,
	Vector3.LEFT, Vector3.BACK, Vector3.FORWARD,
]
const LEGACY_FACE_VERTICES: Array = [
	[Vector3(0, 1, 0), Vector3(0, 1, 1), Vector3(1, 1, 1), Vector3(1, 1, 0)],
	[Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(1, 0, 1), Vector3(0, 0, 1)],
	[Vector3(1, 0, 0), Vector3(1, 1, 0), Vector3(1, 1, 1), Vector3(1, 0, 1)],
	[Vector3(0, 0, 0), Vector3(0, 0, 1), Vector3(0, 1, 1), Vector3(0, 1, 0)],
	[Vector3(0, 0, 1), Vector3(1, 0, 1), Vector3(1, 1, 1), Vector3(0, 1, 1)],
	[Vector3(0, 0, 0), Vector3(0, 1, 0), Vector3(1, 1, 0), Vector3(1, 0, 0)],
]

var _legacy_active := false
var _legacy_target: Node3D
var _legacy_target_physics_was_enabled := false
var _legacy_spawn_prepared := false
var _legacy_noise := FastNoiseLite.new()
var _legacy_biome_noise := FastNoiseLite.new()
var _legacy_material := StandardMaterial3D.new()
var _legacy_water: MeshInstance3D

var _legacy_loaded_chunks: Dictionary = {}
var _legacy_queued_chunks: Dictionary = {}
var _legacy_build_queue: Array[Vector2i] = []
var _legacy_collision_add_queue: Array[Vector2i] = []
var _legacy_collision_remove_queue: Array[Vector2i] = []
var _legacy_collision_add_queued: Dictionary = {}
var _legacy_collision_remove_queued: Dictionary = {}
var _legacy_block_overrides: Dictionary = {}
var _legacy_pending_rebuilds: Dictionary = {}
var _legacy_pending_rebuild_deadlines: Dictionary = {}

var _legacy_center := Vector2i(2147483647, 2147483647)
var _legacy_dirty_save := false
var _legacy_save_delay := 0.0
var _legacy_last_build_usec := 0
var _legacy_last_collision_usec := 0
var _legacy_last_face_count := 0
var _legacy_atomic_swap_count := 0
var _legacy_atomic_swap_failures := 0
var _legacy_edit_rebuild_requests := 0
var _legacy_coalesced_edit_requests := 0


func _ready() -> void:
	_legacy_active = (
		force_playable_world_port
		or OS.has_feature("mobile")
		or OS.has_feature("android")
	)
	if not _legacy_active:
		super._ready()
		return

	render_radius = LEGACY_RENDER_RADIUS
	_legacy_configure_noise()
	_legacy_configure_material()
	_legacy_load_world()
	_legacy_create_water()
	_legacy_target = get_node_or_null(streaming_target_path) as Node3D
	if is_instance_valid(_legacy_target):
		_legacy_target_physics_was_enabled = _legacy_target.is_physics_processing()
		_legacy_target.set_physics_process(false)
		_legacy_set_center(_legacy_world_to_chunk(_legacy_target.global_position))
	else:
		_legacy_set_center(Vector2i.ZERO)


func _process(delta: float) -> void:
	if not _legacy_active:
		super._process(delta)
		return

	_legacy_promote_due_rebuilds()
	if is_instance_valid(_legacy_target):
		var target_chunk := _legacy_world_to_chunk(_legacy_target.global_position)
		if target_chunk != _legacy_center:
			_legacy_set_center(target_chunk)
		if is_instance_valid(_legacy_water):
			_legacy_water.position.x = _legacy_target.global_position.x
			_legacy_water.position.z = _legacy_target.global_position.z

	_legacy_pump_build_queue()
	_legacy_refresh_collision_queues()
	_legacy_pump_collision_queues()
	_legacy_try_prepare_spawn()

	if _legacy_dirty_save:
		_legacy_save_delay -= delta
		if _legacy_save_delay <= 0.0:
			_legacy_save_world()


func _physics_process(delta: float) -> void:
	if not _legacy_active:
		super._physics_process(delta)


func _exit_tree() -> void:
	if not _legacy_active:
		super._exit_tree()
		return
	if _legacy_dirty_save:
		_legacy_save_world()


func is_playable_world_port_active() -> bool:
	return _legacy_active


func refresh_streaming(world_position: Vector3) -> void:
	if not _legacy_active:
		super.refresh_streaming(world_position)
		return
	_legacy_set_center(_legacy_world_to_chunk(world_position))


func expected_chunk_count() -> int:
	if not _legacy_active:
		return super.expected_chunk_count()
	var width := LEGACY_RENDER_RADIUS * 2 + 1
	return width * width


func chunk_count() -> int:
	if not _legacy_active:
		return super.chunk_count()
	return _legacy_loaded_chunks.size()


func has_chunk(chunk_coord: Vector3i) -> bool:
	if not _legacy_active:
		return super.has_chunk(chunk_coord)
	return _legacy_loaded_chunks.has(Vector2i(chunk_coord.x, chunk_coord.z))


func get_chunk(chunk_coord: Vector3i) -> Node3D:
	if not _legacy_active:
		return super.get_chunk(chunk_coord)
	var entry: Dictionary = _legacy_loaded_chunks.get(
		Vector2i(chunk_coord.x, chunk_coord.z),
		{}
	)
	return entry.get("root") as Node3D


func clear_chunks() -> void:
	if not _legacy_active:
		super.clear_chunks()
		return
	for entry_value in _legacy_loaded_chunks.values():
		var entry: Dictionary = entry_value
		var root_node := entry.get("root") as Node3D
		if is_instance_valid(root_node):
			root_node.queue_free()
	_legacy_loaded_chunks.clear()
	_legacy_build_queue.clear()
	_legacy_queued_chunks.clear()
	_legacy_collision_add_queue.clear()
	_legacy_collision_remove_queue.clear()
	_legacy_collision_add_queued.clear()
	_legacy_collision_remove_queued.clear()
	_legacy_pending_rebuilds.clear()
	_legacy_pending_rebuild_deadlines.clear()
	chunks.clear()


func is_remesh_idle() -> bool:
	if not _legacy_active:
		return super.is_remesh_idle()
	return (
		_legacy_build_queue.is_empty()
		and _legacy_pending_rebuilds.is_empty()
		and _legacy_pending_rebuild_deadlines.is_empty()
		and _legacy_collision_add_queue.is_empty()
		and _legacy_collision_remove_queue.is_empty()
	)


func get_remesh_diagnostics() -> Dictionary:
	if not _legacy_active:
		return super.get_remesh_diagnostics()
	return {
		"tasks_started": _legacy_atomic_swap_count + _legacy_loaded_chunks.size(),
		"results_applied": _legacy_atomic_swap_count + _legacy_loaded_chunks.size(),
		"stale_results_discarded": 0,
		"coalesced_requests": _legacy_coalesced_edit_requests,
		"active_tasks": 0,
		"pending_applies": _legacy_build_queue.size() + _legacy_pending_rebuilds.size(),
		"max_queue_ms": _legacy_last_build_usec / 1000.0,
		"max_apply_ms": _legacy_last_collision_usec / 1000.0,
		"max_background_compute_ms": 0.0,
		"max_pump_ms": _legacy_last_build_usec / 1000.0,
		"atomic_swaps": _legacy_atomic_swap_count,
		"atomic_swap_failures": _legacy_atomic_swap_failures,
	}


func reset_remesh_diagnostics() -> bool:
	if not _legacy_active:
		return super.reset_remesh_diagnostics()
	if not is_remesh_idle():
		return false
	_legacy_last_build_usec = 0
	_legacy_last_collision_usec = 0
	_legacy_atomic_swap_count = 0
	_legacy_atomic_swap_failures = 0
	_legacy_edit_rebuild_requests = 0
	_legacy_coalesced_edit_requests = 0
	return true


func get_block_world(world_block_coord: Vector3i) -> int:
	if not _legacy_active:
		return super.get_block_world(world_block_coord)
	return _legacy_get_block(world_block_coord)


func set_block_world(world_block_coord: Vector3i, block_id: int) -> bool:
	if not _legacy_active:
		return super.set_block_world(world_block_coord, block_id)
	if world_block_coord.y < 0 or world_block_coord.y >= LEGACY_WORLD_HEIGHT:
		return false
	var previous_block := _legacy_get_block(world_block_coord)
	if previous_block == block_id:
		return false
	_legacy_block_overrides[_legacy_cell_key(world_block_coord)] = block_id
	_legacy_dirty_save = true
	_legacy_save_delay = 1.5
	_legacy_schedule_affected_rebuilds(world_block_coord)
	return true


func mine_block_world(world_block_coord: Vector3i) -> bool:
	if not _legacy_active:
		return super.mine_block_world(world_block_coord)
	if world_block_coord.y <= 0:
		return false
	if _legacy_get_block(world_block_coord) == BLOCK_AIR:
		return false
	return set_block_world(world_block_coord, BLOCK_AIR)


func place_block_world(world_block_coord: Vector3i, block_id: int) -> bool:
	if not _legacy_active:
		return super.place_block_world(world_block_coord, block_id)
	if block_id < MIN_PLACEABLE_BLOCK or block_id > MAX_PLACEABLE_BLOCK:
		return false
	if _legacy_get_block(world_block_coord) != BLOCK_AIR:
		return false
	return set_block_world(world_block_coord, block_id)


func get_recovery_position(position: Vector3) -> Vector3:
	if not _legacy_active:
		return position
	var height := _legacy_terrain_height(floori(position.x), floori(position.z))
	return Vector3(position.x, height + 3.0, position.z)


func get_status_text() -> String:
	if not _legacy_active:
		return "TEKNIK0.1 chunk manager"
	return (
		"chunks %d  mesh-q %d\nmesh %.2f ms  faces %d\n"
		+ "collision %.2f ms  q %d/%d\nedit-swaps %d  coalesced %d"
	) % [
		_legacy_loaded_chunks.size(),
		_legacy_build_queue.size(),
		_legacy_last_build_usec / 1000.0,
		_legacy_last_face_count,
		_legacy_last_collision_usec / 1000.0,
		_legacy_collision_add_queue.size(),
		_legacy_collision_remove_queue.size(),
		_legacy_atomic_swap_count,
		_legacy_coalesced_edit_requests,
	]


func _legacy_configure_noise() -> void:
	_legacy_noise.seed = LEGACY_WORLD_SEED
	_legacy_noise.frequency = 0.011
	_legacy_noise.fractal_octaves = 4
	_legacy_noise.fractal_gain = 0.48
	_legacy_noise.fractal_lacunarity = 2.05

	_legacy_biome_noise.seed = LEGACY_WORLD_SEED ^ 0x5f3759df
	_legacy_biome_noise.frequency = 0.0035
	_legacy_biome_noise.fractal_octaves = 2


func _legacy_configure_material() -> void:
	_legacy_material.albedo_texture = null
	_legacy_material.vertex_color_use_as_albedo = true
	_legacy_material.roughness = 0.94
	_legacy_material.metallic = 0.0
	_legacy_material.cull_mode = BaseMaterial3D.CULL_DISABLED


func _legacy_world_to_chunk(position: Vector3) -> Vector2i:
	return Vector2i(
		floori(position.x / float(LEGACY_CHUNK_SIZE)),
		floori(position.z / float(LEGACY_CHUNK_SIZE))
	)


func _legacy_cell_to_chunk(cell: Vector3i) -> Vector2i:
	return Vector2i(
		floori(cell.x / float(LEGACY_CHUNK_SIZE)),
		floori(cell.z / float(LEGACY_CHUNK_SIZE))
	)


func _legacy_set_center(center: Vector2i) -> void:
	if center == _legacy_center and not _legacy_build_queue.is_empty():
		return
	_legacy_center = center
	last_center_chunk = Vector3i(center.x, 0, center.y)
	_legacy_prune_build_queue()

	for z in range(center.y - LEGACY_RENDER_RADIUS, center.y + LEGACY_RENDER_RADIUS + 1):
		for x in range(center.x - LEGACY_RENDER_RADIUS, center.x + LEGACY_RENDER_RADIUS + 1):
			var coord := Vector2i(x, z)
			if (
				not _legacy_loaded_chunks.has(coord)
				and not _legacy_queued_chunks.has(coord)
			):
				_legacy_build_queue.append(coord)
				_legacy_queued_chunks[coord] = true

	_legacy_sort_build_queue()
	_legacy_unload_far_chunks()


func _legacy_prune_build_queue() -> void:
	var filtered: Array[Vector2i] = []
	_legacy_queued_chunks.clear()
	for coord in _legacy_build_queue:
		if (
			maxi(
				absi(coord.x - _legacy_center.x),
				absi(coord.y - _legacy_center.y)
			)
			<= LEGACY_RENDER_RADIUS
		):
			filtered.append(coord)
			_legacy_queued_chunks[coord] = true
	_legacy_build_queue = filtered


func _legacy_sort_build_queue() -> void:
	_legacy_build_queue.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		var a_collision := _legacy_needs_collision(a)
		var b_collision := _legacy_needs_collision(b)
		if a_collision != b_collision:
			return a_collision
		return (
			_legacy_chunk_distance_squared(a, _legacy_center)
			< _legacy_chunk_distance_squared(b, _legacy_center)
		)
	)


func _legacy_pump_build_queue() -> void:
	if _legacy_build_queue.is_empty():
		return

	var frame_start := Time.get_ticks_usec()
	while not _legacy_build_queue.is_empty():
		var coord: Vector2i = _legacy_build_queue.pop_front()
		_legacy_queued_chunks.erase(coord)

		var replacing := _legacy_pending_rebuilds.has(coord)
		if _legacy_loaded_chunks.has(coord) and not replacing:
			continue
		if (
			maxi(
				absi(coord.x - _legacy_center.x),
				absi(coord.y - _legacy_center.y)
			)
			> LEGACY_RENDER_RADIUS
		):
			_legacy_pending_rebuilds.erase(coord)
			_legacy_pending_rebuild_deadlines.erase(coord)
			continue

		var build_start := Time.get_ticks_usec()
		var data := _legacy_build_chunk_mesh(coord)
		if replacing:
			if _legacy_commit_atomic_replacement(coord, data):
				_legacy_pending_rebuilds.erase(coord)
				_legacy_pending_rebuild_deadlines.erase(coord)
			else:
				_legacy_atomic_swap_failures += 1
				_legacy_pending_rebuild_deadlines[coord] = (
					Time.get_ticks_msec() + LEGACY_EDIT_REBUILD_DEBOUNCE_MSEC
				)
		else:
			_legacy_commit_chunk(coord, data)

		_legacy_last_build_usec = Time.get_ticks_usec() - build_start
		_legacy_last_face_count = int(data.get("face_count", 0))
		if Time.get_ticks_usec() - frame_start >= LEGACY_BUILD_BUDGET_USEC:
			break


func _legacy_build_chunk_mesh(coord: Vector2i) -> Dictionary:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	var face_count := 0
	var origin := Vector3i(
		coord.x * LEGACY_CHUNK_SIZE,
		0,
		coord.y * LEGACY_CHUNK_SIZE
	)
	var height_cache := _legacy_build_height_cache(origin)

	for local_z in range(LEGACY_CHUNK_SIZE):
		for local_x in range(LEGACY_CHUNK_SIZE):
			var global_x := origin.x + local_x
			var global_z := origin.z + local_z
			for y in range(LEGACY_WORLD_HEIGHT):
				var cell := Vector3i(global_x, y, global_z)
				var block := _legacy_get_block_cached(cell, origin, height_cache)
				if block == BLOCK_AIR:
					continue

				for face_index in range(6):
					var neighbor := cell + LEGACY_FACE_DIRECTIONS[face_index]
					if (
						_legacy_get_block_cached(neighbor, origin, height_cache)
						!= BLOCK_AIR
					):
						continue

					var base_index := vertices.size()
					var shade := _legacy_face_shade(face_index)
					var color := _legacy_block_color(block, cell, shade)
					var local_cell := Vector3(local_x, y, local_z)
					var face_vertices: Array = LEGACY_FACE_VERTICES[face_index]

					for vertex_value in face_vertices:
						vertices.append(local_cell + Vector3(vertex_value))
						normals.append(LEGACY_FACE_NORMALS[face_index])
						colors.append(color)

					indices.append_array(PackedInt32Array([
						base_index, base_index + 1, base_index + 2,
						base_index, base_index + 2, base_index + 3,
					]))
					face_count += 1

	return {
		"vertices": vertices,
		"normals": normals,
		"colors": colors,
		"indices": indices,
		"face_count": face_count,
	}


func _legacy_build_height_cache(origin: Vector3i) -> PackedInt32Array:
	var heights := PackedInt32Array()
	heights.resize(LEGACY_HEIGHT_CACHE_WIDTH * LEGACY_HEIGHT_CACHE_WIDTH)
	for local_z in range(-1, LEGACY_CHUNK_SIZE + 1):
		for local_x in range(-1, LEGACY_CHUNK_SIZE + 1):
			var index := (
				(local_z + 1) * LEGACY_HEIGHT_CACHE_WIDTH
				+ local_x + 1
			)
			heights[index] = _legacy_terrain_height(
				origin.x + local_x,
				origin.z + local_z
			)
	return heights


func _legacy_get_block_cached(
	cell: Vector3i,
	origin: Vector3i,
	heights: PackedInt32Array
) -> int:
	if cell.y < 0:
		return BLOCK_STONE
	if cell.y >= LEGACY_WORLD_HEIGHT:
		return BLOCK_AIR

	var key := _legacy_cell_key(cell)
	if _legacy_block_overrides.has(key):
		return int(_legacy_block_overrides[key])

	var cache_x := cell.x - origin.x + 1
	var cache_z := cell.z - origin.z + 1
	var height: int
	if (
		cache_x >= 0
		and cache_x < LEGACY_HEIGHT_CACHE_WIDTH
		and cache_z >= 0
		and cache_z < LEGACY_HEIGHT_CACHE_WIDTH
	):
		height = heights[cache_z * LEGACY_HEIGHT_CACHE_WIDTH + cache_x]
	else:
		height = _legacy_terrain_height(cell.x, cell.z)
	return _legacy_generated_block(cell.y, height)


func _legacy_commit_chunk(coord: Vector2i, data: Dictionary) -> void:
	var entry := _legacy_create_chunk_entry(coord, data, false)
	if entry.is_empty():
		return
	var root_node := entry.get("root") as Node3D
	add_child(root_node)
	_legacy_loaded_chunks[coord] = entry
	chunks[Vector3i(coord.x, 0, coord.y)] = root_node


func _legacy_commit_atomic_replacement(
	coord: Vector2i,
	data: Dictionary
) -> bool:
	if not _legacy_loaded_chunks.has(coord):
		_legacy_commit_chunk(coord, data)
		_legacy_atomic_swap_count += 1
		return true

	var old_entry: Dictionary = _legacy_loaded_chunks[coord]
	var old_root := old_entry.get("root") as Node3D
	var replacement := _legacy_create_chunk_entry(
		coord,
		data,
		_legacy_needs_collision(coord)
	)
	if replacement.is_empty():
		return false

	var new_root := replacement.get("root") as Node3D
	add_child(new_root)
	_legacy_loaded_chunks[coord] = replacement
	chunks[Vector3i(coord.x, 0, coord.y)] = new_root

	_legacy_collision_add_queue.erase(coord)
	_legacy_collision_remove_queue.erase(coord)
	_legacy_collision_add_queued.erase(coord)
	_legacy_collision_remove_queued.erase(coord)

	if is_instance_valid(old_root):
		old_root.queue_free()
	_legacy_atomic_swap_count += 1
	return true


func _legacy_create_chunk_entry(
	coord: Vector2i,
	data: Dictionary,
	create_collision: bool
) -> Dictionary:
	var chunk_root := Node3D.new()
	chunk_root.name = "Chunk_%d_%d" % [coord.x, coord.y]
	chunk_root.position = Vector3(
		coord.x * LEGACY_CHUNK_SIZE,
		0,
		coord.y * LEGACY_CHUNK_SIZE
	)
	chunk_root.set_meta("chunk_coord", coord)

	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = data.get("vertices", PackedVector3Array())
	arrays[Mesh.ARRAY_NORMAL] = data.get("normals", PackedVector3Array())
	arrays[Mesh.ARRAY_COLOR] = data.get("colors", PackedColorArray())
	arrays[Mesh.ARRAY_INDEX] = data.get("indices", PackedInt32Array())

	var mesh := ArrayMesh.new()
	var vertices: PackedVector3Array = data.get(
		"vertices",
		PackedVector3Array()
	)
	var mesh_instance: MeshInstance3D
	if not vertices.is_empty():
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		mesh.surface_set_material(0, _legacy_material)
		mesh_instance = MeshInstance3D.new()
		mesh_instance.name = "TerrainMesh"
		mesh_instance.mesh = mesh
		mesh_instance.cast_shadow = (
			GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		)
		chunk_root.add_child(mesh_instance)

	var collision: StaticBody3D
	if create_collision and mesh.get_surface_count() > 0:
		collision = _legacy_create_collision(mesh)
		if collision == null:
			return {}
		chunk_root.add_child(collision)

	return {
		"root": chunk_root,
		"mesh": mesh,
		"mesh_instance": mesh_instance,
		"collision": collision,
	}


func _legacy_create_collision(mesh: ArrayMesh) -> StaticBody3D:
	if mesh.get_surface_count() == 0:
		return null
	var collision_shape := mesh.create_trimesh_shape()
	if collision_shape == null:
		return null
	if collision_shape is ConcavePolygonShape3D:
		collision_shape.backface_collision = true

	var static_body := StaticBody3D.new()
	static_body.name = "TerrainCollision"
	static_body.collision_layer = 1
	static_body.collision_mask = 1
	var shape_node := CollisionShape3D.new()
	shape_node.name = "CollisionShape3D"
	shape_node.shape = collision_shape
	static_body.add_child(shape_node)
	return static_body


func _legacy_refresh_collision_queues() -> void:
	for coord_value in _legacy_loaded_chunks.keys():
		var coord: Vector2i = coord_value
		var entry: Dictionary = _legacy_loaded_chunks[coord]
		var has_collision := is_instance_valid(entry.get("collision"))
		if _legacy_needs_collision(coord):
			if (
				not has_collision
				and not _legacy_collision_add_queued.has(coord)
			):
				_legacy_collision_add_queue.append(coord)
				_legacy_collision_add_queued[coord] = true
		elif (
			has_collision
			and not _legacy_collision_remove_queued.has(coord)
		):
			_legacy_collision_remove_queue.append(coord)
			_legacy_collision_remove_queued[coord] = true

	_legacy_collision_add_queue.sort_custom(
		func(a: Vector2i, b: Vector2i) -> bool:
			return (
				_legacy_chunk_distance_squared(a, _legacy_center)
				< _legacy_chunk_distance_squared(b, _legacy_center)
			)
	)


func _legacy_pump_collision_queues() -> void:
	for _index in range(LEGACY_COLLISION_ADDS_PER_FRAME):
		if _legacy_collision_add_queue.is_empty():
			break
		var coord: Vector2i = _legacy_collision_add_queue.pop_front()
		_legacy_collision_add_queued.erase(coord)
		if (
			_legacy_loaded_chunks.has(coord)
			and _legacy_needs_collision(coord)
		):
			var collision_start := Time.get_ticks_usec()
			_legacy_ensure_collision(coord)
			_legacy_last_collision_usec = (
				Time.get_ticks_usec() - collision_start
			)

	for _index in range(LEGACY_COLLISION_REMOVES_PER_FRAME):
		if _legacy_collision_remove_queue.is_empty():
			break
		var coord: Vector2i = _legacy_collision_remove_queue.pop_front()
		_legacy_collision_remove_queued.erase(coord)
		if (
			not _legacy_loaded_chunks.has(coord)
			or _legacy_needs_collision(coord)
		):
			continue
		var entry: Dictionary = _legacy_loaded_chunks[coord]
		var collision := entry.get("collision") as StaticBody3D
		if is_instance_valid(collision):
			collision.queue_free()
			entry["collision"] = null
			_legacy_loaded_chunks[coord] = entry


func _legacy_ensure_collision(coord: Vector2i) -> void:
	if not _legacy_loaded_chunks.has(coord):
		return
	var entry: Dictionary = _legacy_loaded_chunks[coord]
	if is_instance_valid(entry.get("collision")):
		return
	var mesh := entry.get("mesh") as ArrayMesh
	if mesh == null or mesh.get_surface_count() == 0:
		return

	var collision := _legacy_create_collision(mesh)
	if collision == null:
		return
	var root_node := entry.get("root") as Node3D
	root_node.add_child(collision)
	entry["collision"] = collision
	_legacy_loaded_chunks[coord] = entry


func _legacy_try_prepare_spawn() -> void:
	if _legacy_spawn_prepared or not _legacy_spawn_ring_ready():
		return
	_legacy_spawn_prepared = true
	if not is_instance_valid(_legacy_target):
		return

	var spawn_x := int(LEGACY_CHUNK_SIZE * 0.5)
	var spawn_z := int(LEGACY_CHUNK_SIZE * 0.5)
	var spawn_y := float(_legacy_terrain_height(spawn_x, spawn_z)) + 2.2
	_legacy_target.global_position = Vector3(
		spawn_x + 0.5,
		spawn_y,
		spawn_z + 0.5
	)
	if _legacy_target_physics_was_enabled:
		_legacy_target.set_physics_process(true)


func _legacy_spawn_ring_ready() -> bool:
	for z in range(
		-LEGACY_COLLISION_RADIUS,
		LEGACY_COLLISION_RADIUS + 1
	):
		for x in range(
			-LEGACY_COLLISION_RADIUS,
			LEGACY_COLLISION_RADIUS + 1
		):
			var coord := Vector2i(x, z)
			if not _legacy_loaded_chunks.has(coord):
				return false
			var entry: Dictionary = _legacy_loaded_chunks[coord]
			if not is_instance_valid(entry.get("collision")):
				return false
	return true


func _legacy_unload_far_chunks() -> void:
	for coord_value in _legacy_loaded_chunks.keys():
		var coord: Vector2i = coord_value
		if (
			maxi(
				absi(coord.x - _legacy_center.x),
				absi(coord.y - _legacy_center.y)
			)
			<= LEGACY_UNLOAD_RADIUS
		):
			continue
		var entry: Dictionary = _legacy_loaded_chunks[coord]
		var root_node := entry.get("root") as Node3D
		if is_instance_valid(root_node):
			root_node.queue_free()
		_legacy_loaded_chunks.erase(coord)
		chunks.erase(Vector3i(coord.x, 0, coord.y))
		_legacy_pending_rebuilds.erase(coord)
		_legacy_pending_rebuild_deadlines.erase(coord)


func _legacy_needs_collision(coord: Vector2i) -> bool:
	return (
		maxi(
			absi(coord.x - _legacy_center.x),
			absi(coord.y - _legacy_center.y)
		)
		<= LEGACY_COLLISION_RADIUS
	)


func _legacy_chunk_distance_squared(a: Vector2i, b: Vector2i) -> int:
	var delta := a - b
	return delta.x * delta.x + delta.y * delta.y


func _legacy_terrain_height(x: int, z: int) -> int:
	var continental := _legacy_noise.get_noise_2d(float(x), float(z))
	var region := _legacy_biome_noise.get_noise_2d(float(x), float(z))
	var height := 10.0 + continental * 6.4 + region * 3.0
	return clampi(roundi(height), 3, LEGACY_WORLD_HEIGHT - 3)


func _legacy_get_block(cell: Vector3i) -> int:
	if cell.y < 0:
		return BLOCK_STONE
	if cell.y >= LEGACY_WORLD_HEIGHT:
		return BLOCK_AIR
	var key := _legacy_cell_key(cell)
	if _legacy_block_overrides.has(key):
		return int(_legacy_block_overrides[key])
	return _legacy_generated_block(
		cell.y,
		_legacy_terrain_height(cell.x, cell.z)
	)


func _legacy_generated_block(y: int, height: int) -> int:
	if y > height:
		return BLOCK_AIR
	if y == height:
		return (
			BLOCK_SAND
			if height <= LEGACY_SEA_LEVEL + 1
			else BLOCK_GRASS
		)
	if y >= height - 3:
		return (
			BLOCK_SAND
			if height <= LEGACY_SEA_LEVEL + 1
			else BLOCK_DIRT
		)
	return BLOCK_STONE


func _legacy_schedule_affected_rebuilds(cell: Vector3i) -> void:
	var affected: Array[Vector2i] = [_legacy_cell_to_chunk(cell)]
	var local_x := posmod(cell.x, LEGACY_CHUNK_SIZE)
	var local_z := posmod(cell.z, LEGACY_CHUNK_SIZE)
	if local_x == 0:
		affected.append(_legacy_cell_to_chunk(cell + Vector3i.LEFT))
	elif local_x == LEGACY_CHUNK_SIZE - 1:
		affected.append(_legacy_cell_to_chunk(cell + Vector3i.RIGHT))
	if local_z == 0:
		affected.append(_legacy_cell_to_chunk(cell + Vector3i(0, 0, -1)))
	elif local_z == LEGACY_CHUNK_SIZE - 1:
		affected.append(_legacy_cell_to_chunk(cell + Vector3i(0, 0, 1)))

	for coord in affected:
		_legacy_schedule_rebuild(coord)


func _legacy_schedule_rebuild(coord: Vector2i) -> void:
	if not _legacy_loaded_chunks.has(coord):
		if (
			maxi(
				absi(coord.x - _legacy_center.x),
				absi(coord.y - _legacy_center.y)
			)
			<= LEGACY_RENDER_RADIUS
			and not _legacy_queued_chunks.has(coord)
		):
			_legacy_build_queue.push_front(coord)
			_legacy_queued_chunks[coord] = true
		return

	_legacy_edit_rebuild_requests += 1
	if _legacy_pending_rebuilds.has(coord):
		_legacy_coalesced_edit_requests += 1
	_legacy_pending_rebuilds[coord] = true
	_legacy_pending_rebuild_deadlines[coord] = (
		Time.get_ticks_msec() + LEGACY_EDIT_REBUILD_DEBOUNCE_MSEC
	)


func _legacy_promote_due_rebuilds() -> void:
	if _legacy_pending_rebuild_deadlines.is_empty():
		return
	var now_msec := Time.get_ticks_msec()
	for coord_value in _legacy_pending_rebuild_deadlines.keys():
		var coord: Vector2i = coord_value
		var deadline_msec := int(_legacy_pending_rebuild_deadlines[coord])
		if deadline_msec > now_msec:
			continue
		_legacy_pending_rebuild_deadlines.erase(coord)
		if not _legacy_loaded_chunks.has(coord):
			_legacy_pending_rebuilds.erase(coord)
			continue
		if (
			maxi(
				absi(coord.x - _legacy_center.x),
				absi(coord.y - _legacy_center.y)
			)
			> LEGACY_RENDER_RADIUS
		):
			_legacy_pending_rebuilds.erase(coord)
			continue
		if not _legacy_queued_chunks.has(coord):
			_legacy_build_queue.push_front(coord)
			_legacy_queued_chunks[coord] = true


func _legacy_block_color(
	block: int,
	cell: Vector3i,
	shade: float
) -> Color:
	var base_color: Color
	match block:
		BLOCK_GRASS:
			base_color = (
				Color(0.34, 0.68, 0.25)
				if shade >= 0.98
				else Color(0.38, 0.48, 0.23)
			)
		BLOCK_DIRT:
			base_color = Color(0.50, 0.34, 0.20)
		BLOCK_STONE:
			base_color = Color(0.56, 0.58, 0.60)
		BLOCK_SAND:
			base_color = Color(0.82, 0.75, 0.54)
		_:
			base_color = Color.WHITE

	var hash_value := absi(
		(cell.x * 73856093)
		^ (cell.y * 83492791)
		^ (cell.z * 19349663)
	)
	var variation := 0.97 + float(hash_value % 7) * 0.01
	var factor := shade * variation
	return Color(
		clampf(base_color.r * factor, 0.0, 1.0),
		clampf(base_color.g * factor, 0.0, 1.0),
		clampf(base_color.b * factor, 0.0, 1.0),
		1.0
	)


func _legacy_face_shade(face_index: int) -> float:
	match face_index:
		0:
			return 1.0
		1:
			return 0.78
		2, 3:
			return 0.92
		_:
			return 0.86


func _legacy_cell_key(cell: Vector3i) -> String:
	return "%d,%d,%d" % [cell.x, cell.y, cell.z]


func _legacy_create_water() -> void:
	_legacy_water = MeshInstance3D.new()
	_legacy_water.name = "Water"
	_legacy_water.cast_shadow = (
		GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	)

	var plane := PlaneMesh.new()
	plane.size = Vector2(512.0, 512.0)
	_legacy_water.mesh = plane
	_legacy_water.position = Vector3(
		0.0,
		LEGACY_SEA_LEVEL + 0.54,
		0.0
	)

	var water_material := StandardMaterial3D.new()
	water_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	water_material.albedo_color = Color(0.18, 0.48, 0.68, 1.0)
	water_material.roughness = 1.0
	water_material.metallic = 0.0
	water_material.cull_mode = BaseMaterial3D.CULL_BACK
	plane.material = water_material
	add_child(_legacy_water)


func _legacy_save_world() -> void:
	var file := FileAccess.open(LEGACY_SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_warning("Unable to save imported TEKNIK world edits")
		return
	file.store_string(JSON.stringify({
		"version": 1,
		"seed": LEGACY_WORLD_SEED,
		"overrides": _legacy_block_overrides,
	}))
	_legacy_dirty_save = false


func _legacy_load_world() -> void:
	if not FileAccess.file_exists(LEGACY_SAVE_PATH):
		return
	var file := FileAccess.open(LEGACY_SAVE_PATH, FileAccess.READ)
	if file == null:
		return
	var parsed := JSON.parse_string(file.get_as_text())
	if (
		parsed is Dictionary
		and parsed.has("overrides")
		and parsed["overrides"] is Dictionary
	):
		_legacy_block_overrides = parsed["overrides"].duplicate(true)
