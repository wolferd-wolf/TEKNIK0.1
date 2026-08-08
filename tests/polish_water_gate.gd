extends SceneTree

const WATER_BODIES := preload("res://scripts/world/localized_water_bodies.gd")

class FakeTerrain:
	extends RefCounted
	var heights: Dictionary = {}
	var default_height := 9

	func terrain_height(x: int, z: int) -> int:
		return int(heights.get(Vector2i(x, z), default_height))


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var fake := FakeTerrain.new()
	fake.heights[Vector2i(0, 0)] = 4
	fake.heights[Vector2i(-1, 0)] = 4
	fake.heights[Vector2i(1, 0)] = 4
	fake.heights[Vector2i(0, -1)] = 4
	fake.heights[Vector2i(0, 1)] = 4
	fake.heights[Vector2i(5, 5)] = 4

	_assert(WATER_BODIES.is_water_column(fake, 0, 0), "connected low terrain must form a water body")
	_assert(not WATER_BODIES.is_water_column(fake, 5, 5), "isolated low terrain must not become a global water sheet")
	_assert(not WATER_BODIES.is_water_column(fake, 8, 8), "terrain at or above sea level must stay dry")

	var mesh := WATER_BODIES.build_water_mesh(fake, Vector2i.ZERO, 12)
	_assert(mesh != null, "localized low terrain must produce a water mesh")
	_assert(mesh.get_surface_count() == 1, "localized water mesh must contain exactly one render surface")
	var arrays := mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	_assert(not vertices.is_empty(), "water block mesh must contain vertices")
	_assert(colors.size() == vertices.size(), "water block mesh must carry per-vertex colors")

	var has_top_face := false
	var has_side_face := false
	var all_y_block_aligned := true
	for index in range(vertices.size()):
		var normal := normals[index]
		if normal.y > 0.9:
			has_top_face = true
		elif absf(normal.y) < 0.1:
			has_side_face = true
		if absf(vertices[index].y - roundf(vertices[index].y)) > 0.001:
			all_y_block_aligned = false
	_assert(has_top_face, "water block mesh must retain visible top faces")
	_assert(has_side_face, "water must expose vertical voxel side faces instead of top-only quads")
	_assert(all_y_block_aligned, "water geometry must align to full block-height boundaries")

	var packed := load("res://scenes/main.tscn") as PackedScene
	_assert(packed != null, "main scene must load")
	var root := packed.instantiate()
	var manager := root.get_node("ChunkManager")
	# The consolidated architecture has one playable ChunkManager path now; the
	# old force_playable_world_port switch was retired during world consolidation.
	get_root().add_child(root)
	for _frame in range(12):
		await process_frame

	var runtime := manager.get_node_or_null("PlayableWorldRuntime")
	_assert(runtime != null, "playable world runtime must start")
	_assert(runtime.get_node_or_null("Water") == null, "legacy global water plane must be removed")
	var localized := manager.get_node_or_null("LocalizedWaterBodies")
	_assert(localized != null and localized._active, "localized water renderer must activate on the playable world path")
	_assert(localized._chunks.size() > 0, "localized water renderer must evaluate streamed chunks")

	root.queue_free()
	await process_frame
	print("POLISH_WATER_GATE_PASS")
	print("POLISH_WATER_GEOMETRY=full-block top plus exposed vertical voxel sides")
	quit(0)


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	push_error(message)
	quit(1)
