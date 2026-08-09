extends SceneTree

const ShippingData = preload("res://scripts/world/playable_world_carpathian_data.gd")
const ShippingCache = preload("res://scripts/world/playable_world_carpathian_generation_cache_fast.gd")
const ShippingStage12Cache = preload("res://scripts/world/playable_world_stage12_cache_fast.gd")
const ShippingMesher = preload("res://scripts/world/playable_world_stage12_mesher.gd")
const Stage10Mesher = preload("res://scripts/world/playable_world_stage10_mesher.gd")
const Stage6Mesher = preload("res://scripts/world/playable_world_stage6_mesher.gd")
const BaseMesher = preload("res://scripts/world/playable_world_mesher.gd")
const FrozenStage11Runtime = preload("res://scripts/world/playable_world_stage11_generation_runtime.gd")
const Stage2Runtime = preload("res://scripts/world/playable_world_stage2_generation_runtime.gd")

const CHUNK_SIZE := 12
const PROBES := [
	{"label":"corner_-13_95", "cell":Vector2i(-13, 95)},
	{"label":"z_edge_-20_95", "cell":Vector2i(-20, 95)},
	{"label":"z_edge_-5_-13", "cell":Vector2i(-5, -13)},
]

var failures: Array[String] = []
var expected_exposed_faces := 0
var missing_exposed_faces := 0
var raw_suppression_terrain_air := 0
var sanitized_suppression_terrain_air := 0
var data_ref

func _fail(message: String) -> void:
	failures.append(message)
	push_error(message)

func _key(cell: Vector3i) -> String:
	return "%d,%d,%d" % [cell.x, cell.y, cell.z]

func _face_key(center: Vector3, normal: Vector3) -> String:
	return "%.1f,%.1f,%.1f|%.0f,%.0f,%.0f" % [center.x, center.y, center.z, normal.x, normal.y, normal.z]

func _build_state(coord: Vector2i) -> Dictionary:
	var caches: Dictionary = ShippingCache.build(coord, data_ref)
	if caches.is_empty():
		_fail("empty shipping cache %s" % coord)
		return {}
	var heights: PackedInt32Array = caches.get("heights", PackedInt32Array())
	var biomes: PackedByteArray = caches.get("biomes", PackedByteArray())
	var water_types: PackedByteArray = caches.get("stage7_water_types", PackedByteArray())
	var terrain_modifiers: PackedByteArray = caches.get("stage9_terrain_modifiers", PackedByteArray())
	var expression_codes: Dictionary = ShippingStage12Cache.build_expression_codes(caches, data_ref)
	var transition_codes: PackedByteArray = expression_codes.get("transition_codes", PackedByteArray())
	var hydrology_codes: PackedByteArray = expression_codes.get("hydrology_codes", PackedByteArray())
	var blocked_tree_columns: PackedInt32Array = FrozenStage11Runtime._stage6_blocked_tree_columns(coord, caches, data_ref)
	var cache_width: int = roundi(sqrt(float(heights.size())))
	var cache_padding: int = maxi(floori(float(cache_width - CHUNK_SIZE) * 0.5), 1)
	var origin := Vector3i(coord.x * CHUNK_SIZE, 0, coord.y * CHUNK_SIZE)

	# Recreate the fixed Stage 12 full-padded-domain legacy suppression set.
	var blocked_mask := PackedByteArray()
	blocked_mask.resize(heights.size())
	var blocked_count := 0
	for value in blocked_tree_columns:
		var blocked_index: int = int(value)
		if blocked_index >= 0 and blocked_index < blocked_mask.size() and blocked_mask[blocked_index] == 0:
			blocked_mask[blocked_index] = 1
			blocked_count += 1
	for cache_z in range(cache_width):
		var row := cache_z * cache_width
		for cache_x in range(cache_width):
			var index := row + cache_x
			var world_x := origin.x + cache_x - cache_padding
			var world_z := origin.z + cache_z - cache_padding
			if Stage10Mesher._legacy_tree_origin(
				world_x,
				world_z,
				int(heights[index]),
				int(biomes[index]),
				data_ref.OVERHAUL_WORLD_HEIGHT,
				data_ref.SEA_LEVEL,
				data_ref
			) and blocked_mask[index] == 0:
				blocked_mask[index] = 1
				blocked_count += 1
	var combined := PackedInt32Array()
	combined.resize(blocked_count)
	var write_index := 0
	for index in range(blocked_mask.size()):
		if blocked_mask[index] == 0:
			continue
		combined[write_index] = index
		write_index += 1

	var raw_suppression: Dictionary = Stage6Mesher._suppression_overrides(
		coord,
		heights,
		biomes,
		{},
		CHUNK_SIZE,
		data_ref.OVERHAUL_WORLD_HEIGHT,
		data_ref.SEA_LEVEL,
		combined
	)
	for key_value: Variant in raw_suppression.keys():
		if int(raw_suppression.get(key_value, -1)) != BaseMesher.BLOCK_AIR:
			continue
		var parts := String(key_value).split(",")
		if parts.size() != 3:
			continue
		var cell := Vector3i(int(parts[0]), int(parts[1]), int(parts[2]))
		var terrain_index: int = Stage10Mesher._cache_index_for_world(
			cell.x, cell.z, origin, cache_width, cache_padding
		)
		if terrain_index >= 0 and cell.y <= int(heights[terrain_index]):
			raw_suppression_terrain_air += 1

	var sanitized := raw_suppression.duplicate(true)
	ShippingMesher._restore_terrain_under_suppression(
		sanitized,
		{},
		heights,
		origin,
		cache_width,
		cache_padding
	)
	for key_value: Variant in sanitized.keys():
		if int(sanitized.get(key_value, -1)) != BaseMesher.BLOCK_AIR:
			continue
		var parts := String(key_value).split(",")
		if parts.size() != 3:
			continue
		var cell := Vector3i(int(parts[0]), int(parts[1]), int(parts[2]))
		var terrain_index: int = Stage10Mesher._cache_index_for_world(
			cell.x, cell.z, origin, cache_width, cache_padding
		)
		if terrain_index >= 0 and cell.y <= int(heights[terrain_index]):
			sanitized_suppression_terrain_air += 1

	var mesh_height: int = mini(
		data_ref.OVERHAUL_WORLD_HEIGHT,
		Stage2Runtime._effective_mesh_height(coord, heights, {}) + 2
	)
	var mesh: Dictionary = ShippingMesher.build(
		coord,
		heights,
		{},
		CHUNK_SIZE,
		mesh_height,
		data_ref.SEA_LEVEL,
		biomes,
		water_types,
		terrain_modifiers,
		transition_codes,
		hydrology_codes,
		data_ref,
		blocked_tree_columns
	)
	return {"mesh": mesh}

func _face_lookup(coord: Vector2i, mesh_data: Dictionary) -> Dictionary:
	var lookup := {}
	var vertices: PackedVector3Array = mesh_data.get("vertices", PackedVector3Array())
	var normals: PackedVector3Array = mesh_data.get("normals", PackedVector3Array())
	var indices: PackedInt32Array = mesh_data.get("indices", PackedInt32Array())
	var face_count: int = int(mesh_data.get("face_count", 0))
	if vertices.size() != face_count * 4 or normals.size() != vertices.size() or indices.size() != face_count * 6:
		_fail("invalid mesh array contract %s" % coord)
		return lookup
	var chunk_origin := Vector3(coord.x * CHUNK_SIZE, 0.0, coord.y * CHUNK_SIZE)
	for face in range(face_count):
		var base := face * 4
		var center := chunk_origin
		for i in range(4):
			center += vertices[base + i] * 0.25
		lookup[_face_key(center, normals[base])] = true
	return lookup

func _expect_exposed_face(
	lookup: Dictionary,
	owner: Vector3i,
	neighbor: Vector3i,
	center: Vector3,
	normal: Vector3,
	label: String
) -> void:
	var owner_block: int = int(data_ref.get_block(owner))
	var neighbor_block: int = int(data_ref.get_block(neighbor))
	if owner_block == BaseMesher.BLOCK_AIR or neighbor_block != BaseMesher.BLOCK_AIR:
		return
	expected_exposed_faces += 1
	if lookup.has(_face_key(center, normal)):
		return
	missing_exposed_faces += 1
	_fail("missing exposed boundary face %s owner=%s neighbor=%s normal=%s" % [label, owner, neighbor, normal])

func _check_pair(a: Vector2i, b: Vector2i, label: String) -> void:
	var a_state := _build_state(a)
	var b_state := _build_state(b)
	var a_lookup := _face_lookup(a, a_state.get("mesh", {}))
	var b_lookup := _face_lookup(b, b_state.get("mesh", {}))
	if b.x == a.x + 1 and b.y == a.y:
		var boundary_x := b.x * CHUNK_SIZE
		for z in range(a.y * CHUNK_SIZE, a.y * CHUNK_SIZE + CHUNK_SIZE):
			var left_h: int = int(data_ref.terrain_height(boundary_x - 1, z))
			var right_h: int = int(data_ref.terrain_height(boundary_x, z))
			if left_h > right_h:
				for y in range(right_h + 1, left_h + 1):
					_expect_exposed_face(a_lookup, Vector3i(boundary_x - 1, y, z), Vector3i(boundary_x, y, z), Vector3(boundary_x, y + 0.5, z + 0.5), Vector3.RIGHT, label)
			elif right_h > left_h:
				for y in range(left_h + 1, right_h + 1):
					_expect_exposed_face(b_lookup, Vector3i(boundary_x, y, z), Vector3i(boundary_x - 1, y, z), Vector3(boundary_x, y + 0.5, z + 0.5), Vector3.LEFT, label)
	elif b.y == a.y + 1 and b.x == a.x:
		var boundary_z := b.y * CHUNK_SIZE
		for x in range(a.x * CHUNK_SIZE, a.x * CHUNK_SIZE + CHUNK_SIZE):
			var north_h: int = int(data_ref.terrain_height(x, boundary_z - 1))
			var south_h: int = int(data_ref.terrain_height(x, boundary_z))
			if north_h > south_h:
				for y in range(south_h + 1, north_h + 1):
					_expect_exposed_face(a_lookup, Vector3i(x, y, boundary_z - 1), Vector3i(x, y, boundary_z), Vector3(x + 0.5, y + 0.5, boundary_z), Vector3.BACK, label)
			elif south_h > north_h:
				for y in range(north_h + 1, south_h + 1):
					_expect_exposed_face(b_lookup, Vector3i(x, y, boundary_z), Vector3i(x, y, boundary_z - 1), Vector3(x + 0.5, y + 0.5, boundary_z), Vector3.FORWARD, label)

func _init() -> void:
	if not ClassDB.class_exists(&"TeknikCarpathianSampler"):
		_fail("TeknikCarpathianSampler not loaded")
		quit(1)
		return
	data_ref = ShippingData.new()
	if not data_ref.carpathian_enabled():
		_fail("Carpathian shipping sampler not active")
		quit(1)
		return

	var seen_pairs := {}
	for probe in PROBES:
		var cell: Vector2i = probe["cell"]
		var chunk := Vector2i(floori(float(cell.x) / CHUNK_SIZE), floori(float(cell.y) / CHUNK_SIZE))
		var local_x := posmod(cell.x, CHUNK_SIZE)
		var local_z := posmod(cell.y, CHUNK_SIZE)
		print("BOUNDARY_FIX_PROBE label=%s world=%s chunk=%s local=(%d,%d)" % [probe["label"], cell, chunk, local_x, local_z])
		if local_x == CHUNK_SIZE - 1:
			var east := chunk + Vector2i.RIGHT
			var east_key := "%s>%s" % [chunk, east]
			if not seen_pairs.has(east_key):
				seen_pairs[east_key] = true
				_check_pair(chunk, east, String(probe["label"]) + "_east")
		if local_z == CHUNK_SIZE - 1:
			var south := chunk + Vector2i(0, 1)
			var south_key := "%s>%s" % [chunk, south]
			if not seen_pairs.has(south_key):
				seen_pairs[south_key] = true
				_check_pair(chunk, south, String(probe["label"]) + "_south")

	print("CHUNK_BOUNDARY_FIX_RESULT expected_exposed_faces=%d missing_exposed_faces=%d raw_suppression_terrain_air=%d sanitized_suppression_terrain_air=%d failures=%d" % [
		expected_exposed_faces,
		missing_exposed_faces,
		raw_suppression_terrain_air,
		sanitized_suppression_terrain_air,
		failures.size()
	])
	if expected_exposed_faces <= 0:
		_fail("fixture did not exercise any exposed chunk-boundary wall faces")
	if raw_suppression_terrain_air <= 0:
		_fail("fixture no longer demonstrates the historical suppression/terrain overlap")
	if sanitized_suppression_terrain_air != 0:
		_fail("sanitized Stage 12 suppression still deletes solid terrain")
	if missing_exposed_faces != 0:
		_fail("shipping mesh still omits directly exposed chunk-boundary wall faces")
	if not failures.is_empty():
		print("CHUNK_BOUNDARY_HOLE_FIX_FAIL")
		quit(1)
		return
	print("CHUNK_BOUNDARY_HOLE_FIX_PASS")
	quit(0)
