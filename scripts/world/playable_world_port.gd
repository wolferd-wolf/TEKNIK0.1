extends "res://scripts/world/chunk_manager.gd"

const PORT_RUNTIME := preload("res://scripts/world/playable_world_runtime.gd")

@export var force_playable_world_port: bool = false

var _port_active := false
var _runtime


func _ready() -> void:
	_port_active = force_playable_world_port or OS.has_feature("mobile") or OS.has_feature("android")
	if not _port_active:
		super._ready()
		return
	render_radius = 3
	_runtime = PORT_RUNTIME.new()
	_runtime.name = "PlayableWorldRuntime"
	add_child(_runtime)
	_runtime.configure(get_node_or_null(streaming_target_path) as Node3D)
	_runtime.material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_runtime.material.specular_mode = BaseMaterial3D.SPECULAR_DISABLED


func _process(delta: float) -> void:
	if not _port_active:
		super._process(delta)
		return
	_runtime.tick(delta)
	last_center_chunk = Vector3i(_runtime.center.x, 0, _runtime.center.y)


func _physics_process(delta: float) -> void:
	if not _port_active:
		super._physics_process(delta)


func _exit_tree() -> void:
	if not _port_active:
		super._exit_tree()
		return
	if _runtime != null:
		_runtime.shutdown()


func is_playable_world_port_active() -> bool:
	return _port_active


func refresh_streaming(world_position: Vector3) -> void:
	if not _port_active:
		super.refresh_streaming(world_position)
		return
	_runtime.set_center(_runtime.world_to_chunk(world_position))


func expected_chunk_count() -> int:
	if not _port_active:
		return super.expected_chunk_count()
	return 49


func chunk_count() -> int:
	if not _port_active:
		return super.chunk_count()
	return _runtime.loaded.size()


func has_chunk(chunk_coord: Vector3i) -> bool:
	if not _port_active:
		return super.has_chunk(chunk_coord)
	return _runtime.loaded.has(Vector2i(chunk_coord.x, chunk_coord.z))


func get_chunk(chunk_coord: Vector3i) -> Node3D:
	if not _port_active:
		return super.get_chunk(chunk_coord)
	return _runtime.get_chunk_root(Vector2i(chunk_coord.x, chunk_coord.z))


func clear_chunks() -> void:
	if not _port_active:
		super.clear_chunks()
		return
	_runtime.clear_world()
	chunks.clear()


func is_remesh_idle() -> bool:
	if not _port_active:
		return super.is_remesh_idle()
	return _runtime.remesh_idle()


func get_remesh_diagnostics() -> Dictionary:
	if not _port_active:
		return super.get_remesh_diagnostics()
	return _runtime.diagnostics()


func reset_remesh_diagnostics() -> bool:
	if not _port_active:
		return super.reset_remesh_diagnostics()
	return _runtime.reset_diagnostics()


func get_block_world(world_block_coord: Vector3i) -> int:
	if not _port_active:
		return super.get_block_world(world_block_coord)
	return _runtime.get_block(world_block_coord)


func set_block_world(world_block_coord: Vector3i, block_id: int) -> bool:
	if not _port_active:
		return super.set_block_world(world_block_coord, block_id)
	return _runtime.set_block(world_block_coord, block_id)


func mine_block_world(world_block_coord: Vector3i) -> bool:
	if not _port_active:
		return super.mine_block_world(world_block_coord)
	return _runtime.mine_block(world_block_coord)


func place_block_world(world_block_coord: Vector3i, block_id: int) -> bool:
	if not _port_active:
		return super.place_block_world(world_block_coord, block_id)
	return _runtime.place_block(world_block_coord, block_id)


func get_recovery_position(position: Vector3) -> Vector3:
	if not _port_active:
		return position
	return Vector3(
		position.x,
		_runtime.data.terrain_height(floori(position.x), floori(position.z)) + 3.0,
		position.z
	)


func get_playable_world_height(x: int, z: int) -> int:
	return _runtime.data.terrain_height(x, z)


func get_playable_world_chunk_entry(coord: Vector2i) -> Dictionary:
	return _runtime.get_chunk_entry(coord)


func is_playable_world_collision_ring_ready() -> bool:
	return _runtime.collision_ring_ready()
