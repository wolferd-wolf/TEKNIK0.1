extends Node3D

const WORLD_DATA := preload("res://scripts/world/playable_world_data.gd")

const CHUNK_SIZE := 12
const RENDER_RADIUS := 3
const WATER_NONE := 0
const WATER_TOP_COLOR := Color(0.18, 0.50, 0.72, 0.86)
const WATER_SIDE_COLOR := Color(0.12, 0.36, 0.56, 0.86)

@export var streaming_target_path := NodePath("../../Player")

var _active := false
var _center := Vector2i(2147483647, 2147483647)
var _data = WORLD_DATA.new()
var _material := StandardMaterial3D.new()
var _chunks: Dictionary = {}


func _ready() -> void:
	call_deferred("_activate_for_mobile_world")


func _process(_delta: float) -> void:
	if not _active:
		return
	var target := get_node_or_null(streaming_target_path) as Node3D
	if not is_instance_valid(target):
		return
	var next_center := Vector2i(
		floori(target.global_position.x / float(CHUNK_SIZE)),
		floori(target.global_position.z / float(CHUNK_SIZE))
	)
	if next_center != _center:
		_set_center(next_center)


func _activate_for_mobile_world() -> void:
	var chunk_manager := get_parent()
	if chunk_manager == null or not chunk_manager.has_method("is_playable_world_port_active"):
		set_process(false)
		return
	if not bool(chunk_manager.call("is_playable_world_port_active")):
		set_process(false)
		return

	var runtime := chunk_manager.get_node_or_null("PlayableWorldRuntime")
	if runtime == null:
		call_deferred("_activate_for_mobile_world")
		return
	# Water classification, floor height and local surface height use the exact
	# shipping generation facade owned by the playable runtime. The renderer is
	# visual-only: water remains non-solid and does not alter terrain topology.
	_data = runtime.data
	var global_plane := runtime.get_node_or_null("Water")
	if is_instance_valid(global_plane):
		global_plane.queue_free()

	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.vertex_color_use_as_albedo = true
	_material.albedo_color = Color.WHITE
	_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_material.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	_active = true

	var target := get_node_or_null(streaming_target_path) as Node3D
	if is_instance_valid(target):
		_set_center(Vector2i(
			floori(target.global_position.x / float(CHUNK_SIZE)),
			floori(target.global_position.z / float(CHUNK_SIZE))
		))


func _set_center(next_center: Vector2i) -> void:
	_center = next_center
	for z in range(_center.y - RENDER_RADIUS, _center.y + RENDER_RADIUS + 1):
		for x in range(_center.x - RENDER_RADIUS, _center.x + RENDER_RADIUS + 1):
			var coord := Vector2i(x, z)
			if not _chunks.has(coord):
				_create_chunk(coord)
	for coord_value: Variant in _chunks.keys():
		var coord: Vector2i = coord_value
		if maxi(absi(coord.x - _center.x), absi(coord.y - _center.y)) <= RENDER_RADIUS + 1:
			continue
		var mesh_instance := _chunks[coord] as MeshInstance3D
		if is_instance_valid(mesh_instance):
			mesh_instance.queue_free()
		_chunks.erase(coord)


func _create_chunk(coord: Vector2i) -> void:
	var mesh := build_water_mesh(_data, coord, CHUNK_SIZE)
	if mesh == null:
		_chunks[coord] = null
		return
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "Water_%d_%d" % [coord.x, coord.y]
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mesh_instance.position = Vector3(coord.x * CHUNK_SIZE, 0.0, coord.y * CHUNK_SIZE)
	mesh_instance.mesh = mesh
	mesh.surface_set_material(0, _material)
	add_child(mesh_instance)
	_chunks[coord] = mesh_instance


static func water_info(data, x: int, z: int) -> Vector2i:
	if data.has_method("water_info_at"):
		return data.water_info_at(x, z)
	# Stage 4 exposes explicit ocean topology but has one global sea level.
	if data.has_method("is_ocean_column"):
		if bool(data.is_ocean_column(x, z)):
			return Vector2i(1, WORLD_DATA.SEA_LEVEL)
		return Vector2i(WATER_NONE, -1)
	# Legacy oracle fallback: only connected low terrain is water.
	if data.terrain_height(x, z) >= WORLD_DATA.SEA_LEVEL:
		return Vector2i(WATER_NONE, -1)
	var connected_neighbors := 0
	for offset in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
		if data.terrain_height(x + offset.x, z + offset.y) < WORLD_DATA.SEA_LEVEL:
			connected_neighbors += 1
	if connected_neighbors >= 2:
		return Vector2i(1, WORLD_DATA.SEA_LEVEL)
	return Vector2i(WATER_NONE, -1)


static func is_water_column(data, x: int, z: int) -> bool:
	return water_info(data, x, z).x != WATER_NONE


static func build_water_mesh(data, coord: Vector2i, chunk_size: int) -> ArrayMesh:
	# Cache a one-column border so chunk-edge water faces can be culled against
	# the real neighboring terrain/water state. Interior water voxels never emit
	# faces; only the top and exposed block-aligned sides are generated.
	var cache_width := chunk_size + 2
	var cache_count := cache_width * cache_width
	var terrain_heights := PackedInt32Array()
	var water_types := PackedByteArray()
	var water_surfaces := PackedInt32Array()
	terrain_heights.resize(cache_count)
	water_types.resize(cache_count)
	water_surfaces.resize(cache_count)

	var origin_x := coord.x * chunk_size
	var origin_z := coord.y * chunk_size
	for cache_z in range(cache_width):
		var world_z := origin_z + cache_z - 1
		var row := cache_z * cache_width
		for cache_x in range(cache_width):
			var world_x := origin_x + cache_x - 1
			var index := row + cache_x
			terrain_heights[index] = int(data.terrain_height(world_x, world_z))
			var info := water_info(data, world_x, world_z)
			water_types[index] = clampi(info.x, 0, 255)
			water_surfaces[index] = info.y

	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()

	for local_z in range(chunk_size):
		var cache_z := local_z + 1
		for local_x in range(chunk_size):
			var cache_x := local_x + 1
			var index := cache_z * cache_width + cache_x
			if int(water_types[index]) == WATER_NONE:
				continue
			var floor_y := int(terrain_heights[index])
			var surface_y := int(water_surfaces[index])
			if surface_y <= floor_y:
				continue

			# A water column is a stack of full voxel blocks. The top face sits on
			# the integer block boundary above the highest water voxel.
			var top_y := float(surface_y + 1)
			_append_quad(
				vertices,
				normals,
				colors,
				indices,
				Vector3(local_x, top_y, local_z),
				Vector3(local_x, top_y, local_z + 1),
				Vector3(local_x + 1, top_y, local_z + 1),
				Vector3(local_x + 1, top_y, local_z),
				Vector3.UP,
				WATER_TOP_COLOR
			)

			# Exposed sides are emitted one block high so shorelines and stepped
			# water levels read as voxel geometry instead of a paper-thin sheet.
			_append_exposed_side_stack(
				vertices, normals, colors, indices,
				local_x, local_z, floor_y, surface_y,
				terrain_heights, water_types, water_surfaces,
				cache_width, cache_x + 1, cache_z, Vector3.RIGHT
			)
			_append_exposed_side_stack(
				vertices, normals, colors, indices,
				local_x, local_z, floor_y, surface_y,
				terrain_heights, water_types, water_surfaces,
				cache_width, cache_x - 1, cache_z, Vector3.LEFT
			)
			_append_exposed_side_stack(
				vertices, normals, colors, indices,
				local_x, local_z, floor_y, surface_y,
				terrain_heights, water_types, water_surfaces,
				cache_width, cache_x, cache_z + 1, Vector3.BACK
			)
			_append_exposed_side_stack(
				vertices, normals, colors, indices,
				local_x, local_z, floor_y, surface_y,
				terrain_heights, water_types, water_surfaces,
				cache_width, cache_x, cache_z - 1, Vector3.FORWARD
			)

	if vertices.is_empty():
		return null
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


static func _append_exposed_side_stack(
	vertices: PackedVector3Array,
	normals: PackedVector3Array,
	colors: PackedColorArray,
	indices: PackedInt32Array,
	local_x: int,
	local_z: int,
	floor_y: int,
	surface_y: int,
	terrain_heights: PackedInt32Array,
	water_types: PackedByteArray,
	water_surfaces: PackedInt32Array,
	cache_width: int,
	neighbor_cache_x: int,
	neighbor_cache_z: int,
	normal: Vector3
) -> void:
	var neighbor_index := neighbor_cache_z * cache_width + neighbor_cache_x
	var neighbor_floor := int(terrain_heights[neighbor_index])
	var neighbor_water_type := int(water_types[neighbor_index])
	var neighbor_surface := int(water_surfaces[neighbor_index])
	for block_y in range(floor_y + 1, surface_y + 1):
		if _column_occupies_y(neighbor_floor, neighbor_water_type, neighbor_surface, block_y):
			continue
		var bottom := float(block_y)
		var top := float(block_y + 1)
		if normal == Vector3.RIGHT:
			_append_quad(
				vertices, normals, colors, indices,
				Vector3(local_x + 1, bottom, local_z),
				Vector3(local_x + 1, top, local_z),
				Vector3(local_x + 1, top, local_z + 1),
				Vector3(local_x + 1, bottom, local_z + 1),
				normal, WATER_SIDE_COLOR
			)
		elif normal == Vector3.LEFT:
			_append_quad(
				vertices, normals, colors, indices,
				Vector3(local_x, bottom, local_z),
				Vector3(local_x, bottom, local_z + 1),
				Vector3(local_x, top, local_z + 1),
				Vector3(local_x, top, local_z),
				normal, WATER_SIDE_COLOR
			)
		elif normal == Vector3.BACK:
			_append_quad(
				vertices, normals, colors, indices,
				Vector3(local_x, bottom, local_z + 1),
				Vector3(local_x + 1, bottom, local_z + 1),
				Vector3(local_x + 1, top, local_z + 1),
				Vector3(local_x, top, local_z + 1),
				normal, WATER_SIDE_COLOR
			)
		else:
			_append_quad(
				vertices, normals, colors, indices,
				Vector3(local_x, bottom, local_z),
				Vector3(local_x, top, local_z),
				Vector3(local_x + 1, top, local_z),
				Vector3(local_x + 1, bottom, local_z),
				normal, WATER_SIDE_COLOR
			)


static func _column_occupies_y(
	terrain_height: int,
	water_type: int,
	water_surface: int,
	y: int
) -> bool:
	if y <= terrain_height:
		return true
	return water_type != WATER_NONE and y <= water_surface


static func _append_quad(
	vertices: PackedVector3Array,
	normals: PackedVector3Array,
	colors: PackedColorArray,
	indices: PackedInt32Array,
	v0: Vector3,
	v1: Vector3,
	v2: Vector3,
	v3: Vector3,
	normal: Vector3,
	color: Color
) -> void:
	var base := vertices.size()
	vertices.append(v0)
	vertices.append(v1)
	vertices.append(v2)
	vertices.append(v3)
	for _index in range(4):
		normals.append(normal)
		colors.append(color)
	indices.append(base)
	indices.append(base + 1)
	indices.append(base + 2)
	indices.append(base)
	indices.append(base + 2)
	indices.append(base + 3)
