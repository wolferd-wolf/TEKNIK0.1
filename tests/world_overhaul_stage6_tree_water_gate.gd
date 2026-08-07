extends SceneTree

const SHIPPING_DATA := preload("res://scripts/world/playable_world_generation_data.gd")
const SHIPPING_RUNTIME := preload("res://scripts/world/playable_world_generation_runtime.gd")
const STAGE6_CACHE := preload("res://scripts/world/playable_world_stage6_cache_fast.gd")
const STAGE6_MESHER := preload("res://scripts/world/playable_world_stage6_mesher.gd")

const CHUNK_SIZE := 12
const PADDING := 2
const BLOCK_AIR := 0
const BLOCK_STONE := 3
const BLOCK_LOG := 5

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _fail(message: String) -> void:
	failures.append(message)
	push_error(message)


func _run() -> void:
	var data = SHIPPING_DATA.new()
	var runtime = SHIPPING_RUNTIME.new()
	if runtime.data == null:
		_fail("Shipping runtime did not initialize generation data")
		_finish()
		return

	var found := false
	var found_coord := Vector2i.ZERO
	var found_index := -1
	var found_cache: Dictionary = {}
	# Deterministic bounded search. The cache itself identifies only tree-grid/hash
	# origins that are wet, so this does not duplicate the water classifier.
	for chunk_z in range(-20, 21):
		if found:
			break
		for chunk_x in range(-20, 21):
			var coord := Vector2i(chunk_x, chunk_z)
			var cache: Dictionary = STAGE6_CACHE.build(coord, data)
			var blocked: PackedInt32Array = cache.get(
				"blocked_tree_columns",
				PackedInt32Array()
			)
			if blocked.is_empty():
				continue
			found = true
			found_coord = coord
			found_index = int(blocked[0])
			found_cache = cache
			break

	if not found:
		_fail("No deterministic wet tree-origin fixture was found")
		_finish()
		return

	var width := CHUNK_SIZE + PADDING * 2
	var cache_x := found_index % width
	var cache_z := int(found_index / width)
	var world_x := found_coord.x * CHUNK_SIZE - PADDING + cache_x
	var world_z := found_coord.y * CHUNK_SIZE - PADDING + cache_z
	var heights: PackedInt32Array = found_cache.get("heights", PackedInt32Array())
	var biomes: PackedByteArray = found_cache.get("biomes", PackedByteArray())
	var blocked: PackedInt32Array = found_cache.get(
		"blocked_tree_columns",
		PackedInt32Array()
	)
	var surface := int(heights[found_index])
	var water_type := int(data.water_type_at(world_x, world_z))
	if water_type == int(data.WATER_NONE):
		_fail("Cache marked a dry tree origin as water-blocked")
	if data.is_tree_origin(world_x, world_z):
		_fail("Canonical Stage 6 data still accepts a tree origin in generated water")
	if data.get_block(world_x, surface + 1, world_z) == BLOCK_LOG:
		_fail("Canonical direct block query still generated a wet-origin trunk")

	# The stable public data facade and the threaded runtime must describe the
	# same shipping world at this regression fixture.
	if runtime.data.terrain_height(world_x, world_z) != data.terrain_height(world_x, world_z):
		_fail("Public data facade and runtime terrain height diverged")
	if runtime.data.water_type_at(world_x, world_z) != water_type:
		_fail("Public data facade and runtime water topology diverged")
	if runtime.data.is_tree_origin(world_x, world_z) != data.is_tree_origin(world_x, world_z):
		_fail("Public data facade and runtime tree-origin rule diverged")

	var origin := Vector3i(found_coord.x * CHUNK_SIZE, 0, found_coord.y * CHUNK_SIZE)
	var trunk_key := "%d,%d,%d" % [world_x, surface + 1, world_z]
	var suppression: Dictionary = STAGE6_MESHER._suppression_overrides(
		found_coord,
		heights,
		biomes,
		{},
		CHUNK_SIZE,
		int(data.OVERHAUL_WORLD_HEIGHT),
		int(data.SEA_LEVEL),
		blocked
	)
	# If no dry neighboring canopy legitimately occupies this exact cell, the
	# wet-origin trunk must be explicitly suppressed. Otherwise the direct world
	# is allowed to contain the neighbor's leaf, but never this origin's log.
	var direct_block := int(data.get_block(world_x, surface + 1, world_z))
	if direct_block == BLOCK_AIR and int(suppression.get(trunk_key, -1)) != BLOCK_AIR:
		_fail("Stage 6 mesher did not suppress the wet-origin trunk cell")

	# Real player edits always outrank generated suppression.
	var edited: Dictionary = {trunk_key: BLOCK_STONE}
	var with_edit: Dictionary = STAGE6_MESHER._suppression_overrides(
		found_coord,
		heights,
		biomes,
		edited,
		CHUNK_SIZE,
		int(data.OVERHAUL_WORLD_HEIGHT),
		int(data.SEA_LEVEL),
		blocked
	)
	if int(with_edit.get(trunk_key, BLOCK_AIR)) != BLOCK_STONE:
		_fail("Wet-tree suppression overwrote a real player block edit")

	if failures.is_empty():
		print("WORLD_OVERHAUL_STAGE6_TREE_WATER_PASS")
		print("STAGE6_TREE_WATER_FIXTURE=%d,%d,%d" % [world_x, surface + 1, world_z])
		print("STAGE6_TREE_WATER_TYPE=%d" % water_type)
		print("STAGE6_BLOCKED_TREE_COLUMNS=%d" % blocked.size())
	_finish()


func _finish() -> void:
	if failures.is_empty():
		quit(0)
		return
	print("WORLD_OVERHAUL_STAGE6_TREE_WATER_FAIL")
	for failure in failures:
		print("FAILURE=%s" % failure)
	quit(1)
