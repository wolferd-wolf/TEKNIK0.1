extends Node3D

const PORT_RUNTIME := preload("res://scripts/world/playable_world_runtime.gd")

@export var streaming_target_path: NodePath
@export var force_playable_world_port: bool = true
@export var render_radius: int = 3

var chunks: Dictionary = {}
var last_center_chunk := Vector3i.ZERO
var _runtime


func _ready() -> void:
	_runtime = PORT_RUNTIME.new()
	_runtime.name = "PlayableWorldRuntime"
	add_child(_runtime)
	_runtime.configure(get_node_or_null(streaming_target_path) as Node3D)
	chunks = _runtime.loaded


func _process(delta: float) -> void:
	if _runtime == null:
		return
	_runtime.tick(delta)
	last_center_chunk = Vector3i(_runtime.center.x, 0, _runtime.center.y)


func _exit_tree() -> void:
	if _runtime != null:
		_runtime.shutdown()


func is_playable_world_port_active() -> bool:
	return true


func refresh_streaming(world_position: Vector3) -> void:
	if _runtime != null:
		_runtime.set_center(_runtime.world_to_chunk(world_position))


func expected_chunk_count() -> int:
	return 49


func chunk_count() -> int:
	return 0 if _runtime == null else _runtime.loaded.size()


func has_chunk(chunk_coord: Vector3i) -> bool:
	return _runtime != null and _runtime.loaded.has(Vector2i(chunk_coord.x, chunk_coord.z))


func get_chunk(chunk_coord: Vector3i) -> Node3D:
	if _runtime == null:
		return null
	return _runtime.get_chunk_root(Vector2i(chunk_coord.x, chunk_coord.z))


func clear_chunks() -> void:
	if _runtime != null:
		_runtime.clear_world()
	chunks.clear()


func is_remesh_idle() -> bool:
	return _runtime == null or _runtime.remesh_idle()


func get_remesh_diagnostics() -> Dictionary:
	return {} if _runtime == null else _runtime.diagnostics()


func reset_remesh_diagnostics() -> bool:
	return _runtime != null and _runtime.reset_diagnostics()


func get_block_world(world_block_coord: Vector3i) -> int:
	return 0 if _runtime == null else _runtime.get_block(world_block_coord)


func set_block_world(world_block_coord: Vector3i, block_id: int) -> bool:
	return _runtime != null and _runtime.set_block(world_block_coord, block_id)


func mine_block_world(world_block_coord: Vector3i) -> bool:
	return _runtime != null and _runtime.mine_block(world_block_coord)


func place_block_world(world_block_coord: Vector3i, block_id: int) -> bool:
	return _runtime != null and _runtime.place_block(world_block_coord, block_id)


func get_recovery_position(position: Vector3) -> Vector3:
	if _runtime == null:
		return position
	return Vector3(position.x, _runtime.data.terrain_height(floori(position.x), floori(position.z)) + 3.0, position.z)


func get_playable_world_height(x: int, z: int) -> int:
	return 0 if _runtime == null else _runtime.data.terrain_height(x, z)


func get_playable_world_chunk_entry(coord: Vector2i) -> Dictionary:
	return {} if _runtime == null else _runtime.get_chunk_entry(coord)


func is_playable_world_collision_ring_ready() -> bool:
	return _runtime != null and _runtime.collision_ring_ready()
