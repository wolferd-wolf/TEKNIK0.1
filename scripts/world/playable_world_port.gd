extends Node3D
class_name ChunkManager

const PORT_RUNTIME := preload("res://scripts/world/playable_world_runtime.gd")
const CHUNK_SIZE := 12
const PLAYABLE_RENDER_RADIUS := 3

@export var streaming_target_path: NodePath
@export_range(1, 8, 1) var render_radius: int = PLAYABLE_RENDER_RADIUS

var chunks: Dictionary = {}
var last_center_chunk: Vector3i = Vector3i(2147483647, 0, 2147483647)
var _runtime


func _ready() -> void:
	_runtime = PORT_RUNTIME.new()
	_runtime.name = "PlayableWorldRuntime"
	add_child(_runtime)
	_runtime.configure(get_node_or_null(streaming_target_path) as Node3D)
	_runtime.material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_runtime.material.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	chunks = _runtime.loaded
	_update_center_compatibility()


func _process(delta: float) -> void:
	if _runtime == null:
		return
	_runtime.tick(delta)
	chunks = _runtime.loaded
	_update_center_compatibility()


func _exit_tree() -> void:
	if _runtime != null:
		_runtime.shutdown()


func _update_center_compatibility() -> void:
	if _runtime == null:
		return
	last_center_chunk = Vector3i(_runtime.center.x, 0, _runtime.center.y)


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
	return _runtime.data.terrain_height(x, z)


func get_playable_world_chunk_entry(coord: Vector2i) -> Dictionary:
	if _runtime == null:
		return {}
	return _runtime.get_chunk_entry(coord)


func is_playable_world_collision_ring_ready() -> bool:
	return _runtime != null and _runtime.collision_ring_ready()
