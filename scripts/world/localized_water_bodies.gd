extends Node3D

const WORLD_DATA := preload("res://scripts/world/playable_world_data.gd")

const CHUNK_SIZE := 12
const RENDER_RADIUS := 3
const WATER_SURFACE_OFFSET := 0.54

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
	# Water classification and local surface height use the exact generation
	# facade owned by the playable runtime. Stage 5 returns ocean/river info in
	# one query so mesh building does not resample each column twice.
	_data = runtime.data
	var global_plane := runtime.get_node_or_null("Water")
	if is_instance_valid(global_plane):
		global_plane.queue_free()

	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.albedo_color = Color(0.18, 0.48, 0.68, 0.82)
	_material.cull_mode = BaseMaterial3D.CULL_DISABLED
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
		return Vector2i(0, -1)
	# Legacy oracle fallback: only connected low terrain is water.
	if data.terrain_height(x, z) >= WORLD_DATA.SEA_LEVEL:
		return Vector2i(0, -1)
	var connected_neighbors := 0
	for offset in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
		if data.terrain_height(x + offset.x, z + offset.y) < WORLD_DATA.SEA_LEVEL:
			connected_neighbors += 1
	if connected_neighbors >= 2:
		return Vector2i(1, WORLD_DATA.SEA_LEVEL)
	return Vector2i(0, -1)


static func is_water_column(data, x: int, z: int) -> bool:
	return water_info(data, x, z).x != 0


static func build_water_mesh(data, coord: Vector2i, chunk_size: int) -> ArrayMesh:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	var origin_x := coord.x * chunk_size
	var origin_z := coord.y * chunk_size
	for local_z in range(chunk_size):
		for local_x in range(chunk_size):
			var world_x := origin_x + local_x
			var world_z := origin_z + local_z
			var info := water_info(data, world_x, world_z)
			if info.x == 0:
				continue
			var surface_y := float(info.y) + WATER_SURFACE_OFFSET
			var base := vertices.size()
			vertices.append_array(PackedVector3Array([
				Vector3(local_x, surface_y, local_z),
				Vector3(local_x, surface_y, local_z + 1),
				Vector3(local_x + 1, surface_y, local_z + 1),
				Vector3(local_x + 1, surface_y, local_z),
			]))
			for _index in range(4):
				normals.append(Vector3.UP)
			indices.append_array(PackedInt32Array([
				base, base + 1, base + 2,
				base, base + 2, base + 3,
			]))
	if vertices.is_empty():
		return null
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
