extends Node3D
class_name ChunkManager

const PORT_RUNTIME := preload("res://scripts/world/playable_world_generation_runtime.gd")
const SHIPPING_DATA := preload("res://scripts/world/playable_world_stage13_data.gd")
const CHUNK_SIZE := 12
const PLAYABLE_RENDER_RADIUS := 3

@export var streaming_target_path: NodePath
@export_range(1, 8, 1) var render_radius: int = PLAYABLE_RENDER_RADIUS

var chunks: Dictionary = {}
var last_center_chunk: Vector3i = Vector3i(2147483647, 0, 2147483647)
var _runtime
var _blank_world_diag_layer: CanvasLayer
var _blank_world_diag_label: Label


func _ready() -> void:
	_runtime = PORT_RUNTIME.new()
	_runtime.name = "PlayableWorldRuntime"
	add_child(_runtime)
	_runtime.configure(get_node_or_null(streaming_target_path) as Node3D)
	_runtime.material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_runtime.material.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	chunks = _runtime.loaded
	_update_center_compatibility()
	_install_blank_world_diagnostic()
	_update_blank_world_diagnostic()


func _process(delta: float) -> void:
	if _runtime == null:
		return
	_runtime.tick(delta)
	chunks = _runtime.loaded
	_update_center_compatibility()
	_update_blank_world_diagnostic()


func _exit_tree() -> void:
	if _runtime != null:
		_runtime.shutdown()


func _update_center_compatibility() -> void:
	if _runtime == null:
		return
	last_center_chunk = Vector3i(_runtime.center.x, 0, _runtime.center.y)


func _install_blank_world_diagnostic() -> void:
	_blank_world_diag_layer = CanvasLayer.new()
	_blank_world_diag_layer.name = "BlankWorldDiagnostic"
	_blank_world_diag_layer.layer = 100
	add_child(_blank_world_diag_layer)
	_blank_world_diag_label = Label.new()
	_blank_world_diag_label.name = "DiagnosticLabel"
	_blank_world_diag_label.position = Vector2(285.0, 35.0)
	_blank_world_diag_label.add_theme_font_size_override("font_size", 18)
	_blank_world_diag_label.add_theme_color_override("font_color", Color.WHITE)
	_blank_world_diag_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_blank_world_diag_label.add_theme_constant_override("outline_size", 4)
	_blank_world_diag_layer.add_child(_blank_world_diag_label)


func _update_blank_world_diagnostic() -> void:
	if _runtime == null or not is_instance_valid(_blank_world_diag_label):
		return
	var spawn_x := int(CHUNK_SIZE * 0.5)
	var spawn_z := int(CHUNK_SIZE * 0.5)
	var main_height := _runtime.data.terrain_height(spawn_x, spawn_z)
	var main_biome := _runtime.data.biome_at(spawn_x, spawn_z)
	var main_block_zero := _runtime.data.get_block(Vector3i(spawn_x, 0, spawn_z))
	var diag: Dictionary = _runtime.diagnostics()
	var center_entry: Dictionary = _runtime.get_chunk_entry(_runtime.center)
	var center_mesh := center_entry.get("mesh") as ArrayMesh
	var surface_count := 0
	var vertex_count := 0
	if is_instance_valid(center_mesh):
		surface_count = center_mesh.get_surface_count()
		if surface_count > 0:
			var arrays := center_mesh.surface_get_arrays(0)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			vertex_count = vertices.size()
	_blank_world_diag_label.text = (
		"BLANK-WORLD DIAGNOSTIC\n"
		+ "main spawn height=%d biome=%d block_y0=%d overrides=%d\n"
		% [main_height, main_biome, main_block_zero, _runtime.data.overrides.size()]
		+ "center=%s loaded=%d collision_ring=%s spawn_prepared=%s\n"
		% [
			str(_runtime.center),
			_runtime.loaded.size(),
			str(_runtime.collision_ring_ready()),
			str(_runtime.spawn_prepared),
		]
		+ "tasks=%d applied=%d stale_or_empty=%d active=%d pending=%d\n"
		% [
			int(diag.get("tasks_started", 0)),
			int(diag.get("results_applied", 0)),
			int(diag.get("stale_results_discarded", 0)),
			int(diag.get("active_tasks", 0)),
			int(diag.get("pending_applies", 0)),
		]
		+ "center mesh surfaces=%d vertices=%d bg_max_ms=%.1f"
		% [surface_count, vertex_count, float(diag.get("max_background_compute_ms", 0.0))]
	)


func is_playable_world_port_active() -> bool:
	return true


func get_playable_world_runtime():
	return _runtime


func refresh_streaming(world_position: Vector3) -> void:
	if _runtime == null:
		return
	_runtime.set_center(_runtime.world_to_chunk(world_position))
	_update_center_compatibility()


static func world_to_chunk_coord(world_position: Vector3) -> Vector3i:
	return Vector3i(
		floori(world_position.x / float(CHUNK_SIZE)),
		0,
		floori(world_position.z / float(CHUNK_SIZE))
	)


func expected_chunk_count() -> int:
	return (PLAYABLE_RENDER_RADIUS * 2 + 1) * (PLAYABLE_RENDER_RADIUS * 2 + 1)


func chunk_count() -> int:
	if _runtime == null:
		return 0
	return _runtime.loaded.size()


func has_chunk(chunk_coord: Vector3i) -> bool:
	if _runtime == null:
		return false
	return _runtime.loaded.has(Vector2i(chunk_coord.x, chunk_coord.z))


func get_chunk(chunk_coord: Vector3i) -> Node3D:
	if _runtime == null:
		return null
	return _runtime.get_chunk_root(Vector2i(chunk_coord.x, chunk_coord.z))


func clear_chunks() -> void:
	if _runtime == null:
		return
	_runtime.clear_world()
	chunks = _runtime.loaded


func is_remesh_idle() -> bool:
	return _runtime != null and _runtime.remesh_idle()


func get_remesh_diagnostics() -> Dictionary:
	if _runtime == null:
		return {}
	return _runtime.diagnostics()


func reset_remesh_diagnostics() -> bool:
	return _runtime != null and _runtime.reset_diagnostics()


func get_block_world(world_block_coord: Vector3i) -> int:
	if _runtime == null:
		return 0
	return _runtime.get_block(world_block_coord)


func is_block_world_available(world_block_coord: Vector3i) -> bool:
	if _runtime == null:
		return false
	return _runtime.loaded.has(_runtime.cell_to_chunk(world_block_coord))


func set_block_world(world_block_coord: Vector3i, block_id: int) -> bool:
	if not is_block_world_available(world_block_coord):
		return false
	return _runtime.set_block(world_block_coord, block_id)


func mine_block_world(world_block_coord: Vector3i) -> bool:
	if not is_block_world_available(world_block_coord):
		return false
	return _runtime.mine_block(world_block_coord)


func place_block_world(world_block_coord: Vector3i, block_id: int) -> bool:
	if not is_block_world_available(world_block_coord):
		return false
	return _runtime.place_block(world_block_coord, block_id)


func get_recovery_position(position: Vector3) -> Vector3:
	if _runtime == null:
		return position
	return Vector3(
		position.x,
		_runtime.data.terrain_height(floori(position.x), floori(position.z)) + 3.0,
		position.z
	)


func get_playable_world_height(x: int, z: int) -> int:
	if _runtime == null:
		return 0
	return int(_runtime.data.terrain_height(x, z))


func get_playable_world_biome(x: int, z: int) -> int:
	if _runtime == null or not _runtime.data.has_method("biome_at"):
		return 0
	return int(_runtime.data.biome_at(x, z))


func get_playable_world_biome_name(x: int, z: int) -> String:
	if _runtime == null:
		return "unknown"
	var biome := get_playable_world_biome(x, z)
	if _runtime.data.has_method("biome_name"):
		return String(_runtime.data.biome_name(biome))
	return "unknown"


func get_playable_world_water_info(x: int, z: int) -> Vector2i:
	if _runtime == null or not _runtime.data.has_method("water_info_at"):
		return Vector2i(0, -1)
	return _runtime.data.water_info_at(x, z)


func get_playable_world_water_type(x: int, z: int) -> int:
	return get_playable_world_water_info(x, z).x


func get_playable_world_water_surface_height(x: int, z: int) -> int:
	return get_playable_world_water_info(x, z).y


func get_playable_world_water_name(x: int, z: int) -> String:
	match get_playable_world_water_type(x, z):
		1:
			return "ocean"
		2:
			return "river"
		3:
			return "lake"
		4:
			return "pond"
		_:
			return "none"


func get_playable_world_sea_level() -> int:
	return int(SHIPPING_DATA.SEA_LEVEL)


func get_playable_world_height_limit() -> int:
	return int(SHIPPING_DATA.OVERHAUL_WORLD_HEIGHT)


func get_playable_world_chunk_entry(coord: Vector2i) -> Dictionary:
	if _runtime == null:
		return {}
	return _runtime.get_chunk_entry(coord)


func is_playable_world_collision_ring_ready() -> bool:
	return _runtime != null and _runtime.collision_ring_ready()
