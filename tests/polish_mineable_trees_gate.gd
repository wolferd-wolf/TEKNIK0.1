extends SceneTree

const WORLD_DATA := preload("res://scripts/world/playable_world_data.gd")
const WORLD_MESHER := preload("res://scripts/world/playable_world_mesher.gd")
const WORLD_RUNTIME := preload("res://scripts/world/playable_world_runtime.gd")


func _init() -> void:
	var data = WORLD_DATA.new()
	var tree_origin := _find_tree_origin(data)
	_require(tree_origin != Vector2i(2147483647, 2147483647), "No deterministic tree origin found")

	var surface: int = data.terrain_height(tree_origin.x, tree_origin.y)
	var trunk_bottom := Vector3i(tree_origin.x, surface + 1, tree_origin.y)
	var trunk_top := Vector3i(tree_origin.x, surface + WORLD_DATA.TREE_TRUNK_HEIGHT, tree_origin.y)
	var leaf_corner := Vector3i(tree_origin.x + 1, trunk_top.y + 1, tree_origin.y + 1)

	for y in range(trunk_bottom.y, trunk_top.y + 1):
		_require(data.get_block(Vector3i(tree_origin.x, y, tree_origin.y)) == WORLD_DATA.BLOCK_LOG, "Tree trunk is not solid log blocks")
	_require(data.get_block(leaf_corner) == WORLD_DATA.BLOCK_LEAVES, "Tree canopy is not generated as leaves")
	_require(data.get_block(Vector3i(tree_origin.x + 2, trunk_top.y, tree_origin.y)) == WORLD_DATA.BLOCK_AIR, "Tree canopy exceeds its intended radius")

	var chunk_coord := Vector2i(
		floori(float(tree_origin.x) / float(WORLD_RUNTIME.CHUNK_SIZE)),
		floori(float(tree_origin.y) / float(WORLD_RUNTIME.CHUNK_SIZE))
	)
	var heights := _height_cache(data, chunk_coord)
	var mesh_before: Dictionary = WORLD_MESHER.build(
		chunk_coord,
		heights,
		data.overrides,
		WORLD_RUNTIME.CHUNK_SIZE,
		WORLD_DATA.WORLD_HEIGHT,
		WORLD_DATA.SEA_LEVEL
	)
	_require(int(mesh_before.get("face_count", 0)) > 0, "Tree chunk mesher produced no faces")

	var runtime = WORLD_RUNTIME.new()
	runtime.data = data
	_require(runtime.mine_block(trunk_bottom), "Runtime mining rejected a generated log")
	_require(data.get_block(trunk_bottom) == WORLD_DATA.BLOCK_AIR, "Mined log did not become air")
	_require(data.overrides.has(data.cell_key(trunk_bottom)), "Mined log was not persisted as an override")
	_require(runtime.pending_rebuilds.has(chunk_coord), "Mining a log did not schedule its chunk for remesh")

	var mesh_after: Dictionary = WORLD_MESHER.build(
		chunk_coord,
		heights,
		data.overrides,
		WORLD_RUNTIME.CHUNK_SIZE,
		WORLD_DATA.WORLD_HEIGHT,
		WORLD_DATA.SEA_LEVEL
	)
	_require(int(mesh_after.get("face_count", 0)) != int(mesh_before.get("face_count", 0)), "Mining a log did not change the generated mesh")

	print("POLISH_MINEABLE_TREES_GATE_PASS origin=%s surface=%d before_faces=%d after_faces=%d" % [
		tree_origin,
		surface,
		int(mesh_before.get("face_count", 0)),
		int(mesh_after.get("face_count", 0)),
	])
	quit(0)


func _find_tree_origin(data) -> Vector2i:
	for z in range(-48, 49):
		for x in range(-48, 49):
			if data.is_tree_origin(x, z):
				return Vector2i(x, z)
	return Vector2i(2147483647, 2147483647)


func _height_cache(data, coord: Vector2i) -> PackedInt32Array:
	var width := WORLD_RUNTIME.CHUNK_SIZE + 2
	var heights := PackedInt32Array()
	heights.resize(width * width)
	var origin_x := coord.x * WORLD_RUNTIME.CHUNK_SIZE
	var origin_z := coord.y * WORLD_RUNTIME.CHUNK_SIZE
	for local_z in range(-1, WORLD_RUNTIME.CHUNK_SIZE + 1):
		for local_x in range(-1, WORLD_RUNTIME.CHUNK_SIZE + 1):
			var index := (local_z + 1) * width + local_x + 1
			heights[index] = data.terrain_height(origin_x + local_x, origin_z + local_z)
	return heights


func _require(condition: bool, message: String) -> void:
	if condition:
		return
	push_error(message)
	quit(1)
