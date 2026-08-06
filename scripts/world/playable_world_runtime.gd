extends Node3D

const WORLD_DATA := preload("res://scripts/world/playable_world_data.gd")
const WORLD_MESHER := preload("res://scripts/world/playable_world_mesher.gd")

const CHUNK_SIZE := 12
const RENDER_RADIUS := 3
const COLLISION_RADIUS := 1
const UNLOAD_RADIUS := 4
const BUILD_BUDGET_USEC := 5500
const EDIT_DEBOUNCE_MSEC := 75
const MESH_CACHE_PADDING := 2

var target: Node3D
var target_physics_enabled := false
var spawn_prepared := false
var center := Vector2i(2147483647, 2147483647)
var data = WORLD_DATA.new()
var material := StandardMaterial3D.new()
var water: MeshInstance3D

var loaded: Dictionary = {}
var build_queue: Array[Vector2i] = []
var build_queued: Dictionary = {}
var collision_add_queue: Array[Vector2i] = []
var collision_add_queued: Dictionary = {}
var collision_remove_queue: Array[Vector2i] = []
var collision_remove_queued: Dictionary = {}
var pending_rebuilds: Dictionary = {}
var rebuild_deadlines: Dictionary = {}

var last_build_usec := 0
var last_collision_usec := 0
var last_face_count := 0
var atomic_swaps := 0
var atomic_failures := 0
var coalesced_edits := 0


func configure(streaming_target: Node3D) -> void:
	target = streaming_target
	material.vertex_color_use_as_albedo = true
	material.roughness = 0.94
	material.metallic = 0.0
	material.cull_mode = BaseMaterial3D.CULL_BACK
	_create_water()
	if is_instance_valid(target):
		target_physics_enabled = target.is_physics_processing()
		target.set_physics_process(false)
		set_center(world_to_chunk(target.global_position))
	else:
		set_center(Vector2i.ZERO)


func tick(delta: float) -> void:
	_promote_rebuilds()
	if is_instance_valid(target):
		var next_center := world_to_chunk(target.global_position)
		if next_center != center:
			set_center(next_center)
		if is_instance_valid(water):
			water.position.x = target.global_position.x
			water.position.z = target.global_position.z
	_pump_builds()
	_refresh_collisions()
	_pump_collisions()
	_prepare_spawn()
	data.tick_save(delta)


func shutdown() -> void:
	if data.dirty:
		data.save_world()


func world_to_chunk(position: Vector3) -> Vector2i:
	return Vector2i(
		floori(position.x / float(CHUNK_SIZE)),
		floori(position.z / float(CHUNK_SIZE))
	)


func cell_to_chunk(cell: Vector3i) -> Vector2i:
	return Vector2i(
		floori(cell.x / float(CHUNK_SIZE)),
		floori(cell.z / float(CHUNK_SIZE))
	)


func set_center(next_center: Vector2i) -> void:
	center = next_center
	_prune_queue()
	for z in range(center.y - RENDER_RADIUS, center.y + RENDER_RADIUS + 1):
		for x in range(center.x - RENDER_RADIUS, center.x + RENDER_RADIUS + 1):
			var coord := Vector2i(x, z)
			if not loaded.has(coord) and not build_queued.has(coord):
				build_queue.append(coord)
				build_queued[coord] = true
	_sort_queue()
	_unload_far_chunks()


func get_chunk_root(coord: Vector2i) -> Node3D:
	var entry: Dictionary = loaded.get(coord, {})
	return entry.get("root") as Node3D


func get_chunk_entry(coord: Vector2i) -> Dictionary:
	return loaded.get(coord, {})


func clear_world() -> void:
	for entry_value: Variant in loaded.values():
		var entry: Dictionary = entry_value
		var root_node := entry.get("root") as Node3D
		if is_instance_valid(root_node):
			root_node.queue_free()
	loaded.clear()
	build_queue.clear()
	build_queued.clear()
	collision_add_queue.clear()
	collision_remove_queue.clear()
	collision_add_queued.clear()
	collision_remove_queued.clear()
	pending_rebuilds.clear()
	rebuild_deadlines.clear()


func get_block(cell: Vector3i) -> int:
	return data.get_block(cell)


func mine_block(cell: Vector3i) -> bool:
	if cell.y <= 0 or data.get_block(cell) == WORLD_DATA.BLOCK_AIR:
		return false
	return set_block(cell, WORLD_DATA.BLOCK_AIR)


func place_block(cell: Vector3i, block_id: int) -> bool:
	if block_id < WORLD_DATA.BLOCK_GRASS or block_id > WORLD_DATA.BLOCK_SAND:
		return false
	if data.get_block(cell) != WORLD_DATA.BLOCK_AIR:
		return false
	return set_block(cell, block_id)


func set_block(cell: Vector3i, block_id: int) -> bool:
	if not data.set_block(cell, block_id):
		return false
	_schedule_affected_rebuilds(cell)
	return true


func collision_ring_ready() -> bool:
	for z in range(-COLLISION_RADIUS, COLLISION_RADIUS + 1):
		for x in range(-COLLISION_RADIUS, COLLISION_RADIUS + 1):
			var coord := Vector2i(center.x + x, center.y + z)
			if not loaded.has(coord):
				return false
			var entry: Dictionary = loaded[coord]
			if not is_instance_valid(entry.get("collision")):
				return false
	return true


func remesh_idle() -> bool:
	return build_queue.is_empty() and pending_rebuilds.is_empty()


func diagnostics() -> Dictionary:
	return {
		"tasks_started": loaded.size() + atomic_swaps,
		"results_applied": loaded.size() + atomic_swaps,
		"stale_results_discarded": 0,
		"coalesced_requests": coalesced_edits,
		"active_tasks": 0,
		"pending_applies": build_queue.size() + pending_rebuilds.size(),
		"max_queue_ms": last_build_usec / 1000.0,
		"max_apply_ms": last_collision_usec / 1000.0,
		"max_background_compute_ms": 0.0,
		"max_pump_ms": last_build_usec / 1000.0,
		"atomic_swaps": atomic_swaps,
		"atomic_swap_failures": atomic_failures,
	}


func reset_diagnostics() -> bool:
	if not remesh_idle():
		return false
	last_build_usec = 0
	last_collision_usec = 0
	atomic_swaps = 0
	atomic_failures = 0
	coalesced_edits = 0
	return true


func _prune_queue() -> void:
	var kept: Array[Vector2i] = []
	build_queued.clear()
	for coord: Vector2i in build_queue:
		if distance(coord, center) <= RENDER_RADIUS:
			kept.append(coord)
			build_queued[coord] = true
	build_queue = kept


func _sort_queue() -> void:
	build_queue.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		var a_collision := needs_collision(a)
		var b_collision := needs_collision(b)
		if a_collision != b_collision:
			return a_collision
		return (a - center).length_squared() < (b - center).length_squared()
	)


func _pump_builds() -> void:
	if build_queue.is_empty():
		return
	var frame_start := Time.get_ticks_usec()
	while not build_queue.is_empty():
		var coord: Vector2i = build_queue.pop_front()
		build_queued.erase(coord)
		var replacing := pending_rebuilds.has(coord)
		if loaded.has(coord) and not replacing:
			continue
		if distance(coord, center) > RENDER_RADIUS:
			pending_rebuilds.erase(coord)
			continue
		var build_start := Time.get_ticks_usec()
		var column_caches := _build_column_caches(coord)
		var heights: PackedInt32Array = column_caches.get("heights", PackedInt32Array())
		var biomes: PackedByteArray = column_caches.get("biomes", PackedByteArray())
		var mesh_data: Dictionary = WORLD_MESHER.build(
			coord,
			heights,
			data.overrides,
			CHUNK_SIZE,
			WORLD_DATA.WORLD_HEIGHT,
			WORLD_DATA.SEA_LEVEL,
			biomes
		)
		if replacing:
			if _swap_chunk(coord, mesh_data):
				pending_rebuilds.erase(coord)
			else:
				atomic_failures += 1
				rebuild_deadlines[coord] = Time.get_ticks_msec() + EDIT_DEBOUNCE_MSEC
		else:
			_commit_chunk(coord, mesh_data, false)
		last_build_usec = Time.get_ticks_usec() - build_start
		last_face_count = int(mesh_data.get("face_count", 0))
		if Time.get_ticks_usec() - frame_start >= BUILD_BUDGET_USEC:
			break


func _build_column_caches(coord: Vector2i) -> Dictionary:
	var width := CHUNK_SIZE + MESH_CACHE_PADDING * 2
	var heights := PackedInt32Array()
	var biomes := PackedByteArray()
	heights.resize(width * width)
	biomes.resize(width * width)
	var origin_x := coord.x * CHUNK_SIZE
	var origin_z := coord.y * CHUNK_SIZE
	for local_z in range(-MESH_CACHE_PADDING, CHUNK_SIZE + MESH_CACHE_PADDING):
		for local_x in range(-MESH_CACHE_PADDING, CHUNK_SIZE + MESH_CACHE_PADDING):
			var index := (local_z + MESH_CACHE_PADDING) * width + local_x + MESH_CACHE_PADDING
			var world_x := origin_x + local_x
			var world_z := origin_z + local_z
			var samples: Vector4 = data.sample_column_noise(world_x, world_z)
			heights[index] = data.terrain_height_from_samples(samples)
			biomes[index] = data.blended_biome_from_samples(samples, world_x, world_z)
	return {"heights": heights, "biomes": biomes}


func _build_height_cache(coord: Vector2i) -> PackedInt32Array:
	var caches := _build_column_caches(coord)
	return caches.get("heights", PackedInt32Array())


func _build_biome_cache(coord: Vector2i) -> PackedByteArray:
	var caches := _build_column_caches(coord)
	return caches.get("biomes", PackedByteArray())


func _commit_chunk(coord: Vector2i, mesh_data: Dictionary, with_collision: bool) -> bool:
	var entry := _create_entry(coord, mesh_data, with_collision)
	if entry.is_empty():
		return false
	var root_node := entry.get("root") as Node3D
	add_child(root_node)
	loaded[coord] = entry
	return true


func _swap_chunk(coord: Vector2i, mesh_data: Dictionary) -> bool:
	var replacement := _create_entry(coord, mesh_data, needs_collision(coord))
	if replacement.is_empty():
		return false
	var previous: Dictionary = loaded.get(coord, {})
	var old_root := previous.get("root") as Node3D
	var new_root := replacement.get("root") as Node3D
	add_child(new_root)
	loaded[coord] = replacement
	collision_add_queue.erase(coord)
	collision_remove_queue.erase(coord)
	collision_add_queued.erase(coord)
	collision_remove_queued.erase(coord)
	if is_instance_valid(old_root):
		old_root.queue_free()
	atomic_swaps += 1
	return true


func _create_entry(coord: Vector2i, mesh_data: Dictionary, with_collision: bool) -> Dictionary:
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
	mesh.surface_set_material(0, material)
	var root_node := Node3D.new()
	root_node.name = "Chunk_%d_%d" % [coord.x, coord.y]
	root_node.position = Vector3(coord.x * CHUNK_SIZE, 0, coord.y * CHUNK_SIZE)
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "TerrainMesh"
	mesh_instance.mesh = mesh
	root_node.add_child(mesh_instance)
	var collision: StaticBody3D
	if with_collision:
		collision = _create_collision(mesh)
		if collision == null:
			return {}
		root_node.add_child(collision)
	return {"root": root_node, "mesh": mesh, "collision": collision}


func _create_collision(mesh: ArrayMesh) -> StaticBody3D:
	var shape: Shape3D = mesh.create_trimesh_shape()
	if shape == null:
		return null
	if shape is ConcavePolygonShape3D:
		shape.backface_collision = true
	var body := StaticBody3D.new()
	body.name = "TerrainCollision"
	body.collision_layer = 1
	body.collision_mask = 1
	var shape_node := CollisionShape3D.new()
	shape_node.shape = shape
	body.add_child(shape_node)
	return body


func _refresh_collisions() -> void:
	for coord_value: Variant in loaded.keys():
		var coord: Vector2i = coord_value
		var entry: Dictionary = loaded[coord]
		var has_collision := is_instance_valid(entry.get("collision"))
		if needs_collision(coord):
			if not has_collision and not collision_add_queued.has(coord):
				collision_add_queue.append(coord)
				collision_add_queued[coord] = true
		elif has_collision and not collision_remove_queued.has(coord):
			collision_remove_queue.append(coord)
			collision_remove_queued[coord] = true
	collision_add_queue.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return (a - center).length_squared() < (b - center).length_squared()
	)


func _pump_collisions() -> void:
	if not collision_add_queue.is_empty():
		var coord: Vector2i = collision_add_queue.pop_front()
		collision_add_queued.erase(coord)
		if loaded.has(coord) and needs_collision(coord):
			var start := Time.get_ticks_usec()
			var entry: Dictionary = loaded[coord]
			var mesh := entry.get("mesh") as ArrayMesh
			var collision := _create_collision(mesh)
			if collision != null:
				var root_node := entry.get("root") as Node3D
				root_node.add_child(collision)
				entry["collision"] = collision
				loaded[coord] = entry
			last_collision_usec = Time.get_ticks_usec() - start
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


func _prepare_spawn() -> void:
	if spawn_prepared or not collision_ring_ready():
		return
	spawn_prepared = true
	if not is_instance_valid(target):
		return
	var spawn_x := int(CHUNK_SIZE * 0.5)
	var spawn_z := int(CHUNK_SIZE * 0.5)
	target.global_position = Vector3(
		spawn_x + 0.5,
		data.terrain_height(spawn_x, spawn_z) + 2.2,
		spawn_z + 0.5
	)
	if target_physics_enabled:
		target.set_physics_process(true)


func needs_collision(coord: Vector2i) -> bool:
	return distance(coord, center) <= COLLISION_RADIUS


func distance(a: Vector2i, b: Vector2i) -> int:
	return maxi(absi(a.x - b.x), absi(a.y - b.y))


func _unload_far_chunks() -> void:
	for coord_value: Variant in loaded.keys():
		var coord: Vector2i = coord_value
		if distance(coord, center) <= UNLOAD_RADIUS:
			continue
		var entry: Dictionary = loaded[coord]
		var root_node := entry.get("root") as Node3D
		if is_instance_valid(root_node):
			root_node.queue_free()
		loaded.erase(coord)


func _schedule_affected_rebuilds(cell: Vector3i) -> void:
	var chunk_coord := cell_to_chunk(cell)
	var chunk_x_values: Array[int] = [chunk_coord.x]
	var chunk_z_values: Array[int] = [chunk_coord.y]
	var local_x := posmod(cell.x, CHUNK_SIZE)
	var local_z := posmod(cell.z, CHUNK_SIZE)
	if local_x == 0:
		chunk_x_values.append(chunk_coord.x - 1)
	elif local_x == CHUNK_SIZE - 1:
		chunk_x_values.append(chunk_coord.x + 1)
	if local_z == 0:
		chunk_z_values.append(chunk_coord.y - 1)
	elif local_z == CHUNK_SIZE - 1:
		chunk_z_values.append(chunk_coord.y + 1)
	for chunk_z in chunk_z_values:
		for chunk_x in chunk_x_values:
			var coord := Vector2i(chunk_x, chunk_z)
			if not loaded.has(coord):
				continue
			if pending_rebuilds.has(coord):
				coalesced_edits += 1
			pending_rebuilds[coord] = true
			rebuild_deadlines[coord] = Time.get_ticks_msec() + EDIT_DEBOUNCE_MSEC


func _promote_rebuilds() -> void:
	var now := Time.get_ticks_msec()
	for coord_value: Variant in rebuild_deadlines.keys():
		var coord: Vector2i = coord_value
		if int(rebuild_deadlines[coord]) > now:
			continue
		rebuild_deadlines.erase(coord)
		if loaded.has(coord) and not build_queued.has(coord):
			build_queue.push_front(coord)
			build_queued[coord] = true


func _create_water() -> void:
	water = MeshInstance3D.new()
	water.name = "Water"
	water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var plane := PlaneMesh.new()
	plane.size = Vector2(512.0, 512.0)
	var water_material := StandardMaterial3D.new()
	water_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	water_material.albedo_color = Color(0.18, 0.48, 0.68, 1.0)
	plane.material = water_material
	water.mesh = plane
	water.position.y = WORLD_DATA.SEA_LEVEL + 0.54
	add_child(water)
