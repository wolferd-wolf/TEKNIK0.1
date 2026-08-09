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
const PADDING := 2
const PROBES := [
	{"label":"corner_-13_95", "cell":Vector2i(-13, 95)},
	{"label":"z_edge_-20_95", "cell":Vector2i(-20, 95)},
	{"label":"z_edge_-5_-13", "cell":Vector2i(-5, -13)},
]

var failures: Array[String] = []
var expected_exposed_faces := 0
var missing_exposed_faces := 0
var height_only_tree_occlusions := 0
var suppression_terrain_air := 0
var missing_from_suppression := 0
var details_printed := 0

func _fail(message: String) -> void:
	failures.append(message)
	push_error(message)

func _key(cell: Vector3i) -> String:
	return "%d,%d,%d" % [cell.x, cell.y, cell.z]

func _face_key(center: Vector3, normal: Vector3) -> String:
	return "%.1f,%.1f,%.1f|%.0f,%.0f,%.0f" % [center.x, center.y, center.z, normal.x, normal.y, normal.z]

func _shipping_state(coord: Vector2i, data) -> Dictionary:
	var caches: Dictionary = ShippingCache.build(coord, data)
	if caches.is_empty():
		_fail("empty cache %s" % coord)
		return {}
	var heights: PackedInt32Array = caches.get("heights", PackedInt32Array())
	var biomes: PackedByteArray = caches.get("biomes", PackedByteArray())
	var water_types: PackedByteArray = caches.get("stage7_water_types", PackedByteArray())
	var terrain_modifiers: PackedByteArray = caches.get("stage9_terrain_modifiers", PackedByteArray())
	var expression_codes: Dictionary = ShippingStage12Cache.build_expression_codes(caches, data)
	var transition_codes: PackedByteArray = expression_codes.get("transition_codes", PackedByteArray())
	var hydrology_codes: PackedByteArray = expression_codes.get("hydrology_codes", PackedByteArray())
	var blocked_tree_columns: PackedInt32Array = FrozenStage11Runtime._stage6_blocked_tree_columns(coord, caches, data)
	var width: int = roundi(sqrt(float(heights.size())))
	var padding: int = maxi(floori(float(width - CHUNK_SIZE) * 0.5), 1)
	var origin := Vector3i(coord.x * CHUNK_SIZE, 0, coord.y * CHUNK_SIZE)

	# Recreate the exact Stage 12 blocked-origin set up to the suppression call.
	var blocked_mask := PackedByteArray()
	blocked_mask.resize(heights.size())
	for value in blocked_tree_columns:
		var index: int = int(value)
		if index >= 0 and index < blocked_mask.size():
			blocked_mask[index] = 1
	for cache_z in range(1, width - 1):
		for cache_x in range(1, width - 1):
			var index: int = cache_z * width + cache_x
			var world_x: int = origin.x + cache_x - padding
			var world_z: int = origin.z + cache_z - padding
			var surface: int = int(heights[index])
			var biome: int = int(biomes[index])
			if Stage10Mesher._legacy_tree_origin(world_x, world_z, surface, biome, data.OVERHAUL_WORLD_HEIGHT, data.SEA_LEVEL, data):
				blocked_mask[index] = 1
	var blocked_count := 0
	for value in blocked_mask:
		if int(value) != 0:
			blocked_count += 1
	var combined_blocked := PackedInt32Array()
	combined_blocked.resize(blocked_count)
	var write_index := 0
	for index in range(blocked_mask.size()):
		if blocked_mask[index] == 0:
			continue
		combined_blocked[write_index] = index
		write_index += 1
	var suppression: Dictionary = Stage6Mesher._suppression_overrides(
		coord, heights, biomes, {}, CHUNK_SIZE, data.OVERHAUL_WORLD_HEIGHT,
		data.SEA_LEVEL, combined_blocked
	)

	# Count direct terrain cells that the suppression layer turns into AIR.
	for key_value in suppression.keys():
		if int(suppression[key_value]) != BaseMesher.BLOCK_AIR:
			continue
		var parts := String(key_value).split(",")
		if parts.size() != 3:
			continue
		var cell := Vector3i(int(parts[0]), int(parts[1]), int(parts[2]))
		var cache_x := cell.x - origin.x + padding
		var cache_z := cell.z - origin.z + padding
		if cache_x < 0 or cache_x >= width or cache_z < 0 or cache_z >= width:
			continue
		var height := int(heights[cache_z * width + cache_x])
		if cell.y <= height:
			suppression_terrain_air += 1
			if details_printed < 20:
				print("SUPPRESSION_ERASES_TERRAIN chunk=%s cell=%s column_height=%d direct_block=%d" % [coord, cell, height, int(data.get_block(cell))])
				details_printed += 1

	var mesh_height: int = mini(data.OVERHAUL_WORLD_HEIGHT, Stage2Runtime._effective_mesh_height(coord, heights, {}) + 2)
	var mesh: Dictionary = ShippingMesher.build(
		coord, heights, {}, CHUNK_SIZE, mesh_height, data.SEA_LEVEL, biomes,
		water_types, terrain_modifiers, transition_codes, hydrology_codes,
		data, blocked_tree_columns
	)
	return {
		"caches": caches,
		"heights": heights,
		"biomes": biomes,
		"origin": origin,
		"width": width,
		"padding": padding,
		"suppression": suppression,
		"mesh": mesh,
	}

func _face_lookup(coord: Vector2i, mesh_data: Dictionary) -> Dictionary:
	var result := {}
	var vertices: PackedVector3Array = mesh_data.get("vertices", PackedVector3Array())
	var normals: PackedVector3Array = mesh_data.get("normals", PackedVector3Array())
	var face_count: int = int(mesh_data.get("face_count", 0))
	if vertices.size() != face_count * 4 or normals.size() != vertices.size():
		_fail("invalid mesh arrays %s" % coord)
		return result
	var chunk_origin := Vector3(coord.x * CHUNK_SIZE, 0.0, coord.y * CHUNK_SIZE)
	for face in range(face_count):
		var base := face * 4
		var center := chunk_origin
		for i in range(4):
			center += vertices[base + i] * 0.25
		result[_face_key(center, normals[base])] = true
	return result

func _diagnose_face(
	lookup: Dictionary,
	state: Dictionary,
	owner: Vector3i,
	neighbor: Vector3i,
	center: Vector3,
	normal: Vector3,
	label: String
) -> void:
	var owner_direct: int = int(data_ref.get_block(owner))
	var neighbor_direct: int = int(data_ref.get_block(neighbor))
	if owner_direct == BaseMesher.BLOCK_AIR:
		return
	if neighbor_direct != BaseMesher.BLOCK_AIR:
		height_only_tree_occlusions += 1
		if details_printed < 20:
			print("BOUNDARY_HEIGHT_DELTA_OCCLUDED_BY_REAL_BLOCK label=%s owner=%s owner_block=%d neighbor=%s neighbor_block=%d" % [label,owner,owner_direct,neighbor,neighbor_direct])
			details_printed += 1
		return
	expected_exposed_faces += 1
	if lookup.has(_face_key(center, normal)):
		return
	missing_exposed_faces += 1
	var suppression: Dictionary = state["suppression"]
	var owner_suppressed := suppression.has(_key(owner))
	var neighbor_suppressed := suppression.has(_key(neighbor))
	var owner_suppression: int = int(suppression.get(_key(owner), -1))
	var neighbor_suppression: int = int(suppression.get(_key(neighbor), -1))
	if owner_suppressed and owner_suppression == BaseMesher.BLOCK_AIR:
		missing_from_suppression += 1
	print("BOUNDARY_EXPOSED_FACE_MISSING label=%s owner=%s direct=%d neighbor=%s direct_neighbor=%d normal=%s owner_suppression=%s:%d neighbor_suppression=%s:%d" % [
		label, owner, owner_direct, neighbor, neighbor_direct, normal,
		owner_suppressed, owner_suppression, neighbor_suppressed, neighbor_suppression
	])

var data_ref

func _check_pair(a: Vector2i, b: Vector2i, label: String) -> void:
	var a_state := _shipping_state(a, data_ref)
	var b_state := _shipping_state(b, data_ref)
	var a_lookup := _face_lookup(a, a_state["mesh"])
	var b_lookup := _face_lookup(b, b_state["mesh"])
	if b.x == a.x + 1 and b.y == a.y:
		var boundary_x := b.x * CHUNK_SIZE
		for z in range(a.y * CHUNK_SIZE, a.y * CHUNK_SIZE + CHUNK_SIZE):
			var left_h: int = int(data_ref.terrain_height(boundary_x - 1, z))
			var right_h: int = int(data_ref.terrain_height(boundary_x, z))
			if left_h > right_h:
				for y in range(right_h + 1, left_h + 1):
					_diagnose_face(a_lookup, a_state, Vector3i(boundary_x - 1,y,z), Vector3i(boundary_x,y,z), Vector3(boundary_x,y+0.5,z+0.5), Vector3.RIGHT, label)
			elif right_h > left_h:
				for y in range(left_h + 1, right_h + 1):
					_diagnose_face(b_lookup, b_state, Vector3i(boundary_x,y,z), Vector3i(boundary_x-1,y,z), Vector3(boundary_x,y+0.5,z+0.5), Vector3.LEFT, label)
	elif b.y == a.y + 1 and b.x == a.x:
		var boundary_z := b.y * CHUNK_SIZE
		for x in range(a.x * CHUNK_SIZE, a.x * CHUNK_SIZE + CHUNK_SIZE):
			var north_h: int = int(data_ref.terrain_height(x, boundary_z - 1))
			var south_h: int = int(data_ref.terrain_height(x, boundary_z))
			if north_h > south_h:
				for y in range(south_h + 1, north_h + 1):
					_diagnose_face(a_lookup, a_state, Vector3i(x,y,boundary_z-1), Vector3i(x,y,boundary_z), Vector3(x+0.5,y+0.5,boundary_z), Vector3.BACK, label)
			elif south_h > north_h:
				for y in range(north_h + 1, south_h + 1):
					_diagnose_face(b_lookup, b_state, Vector3i(x,y,boundary_z), Vector3i(x,y,boundary_z-1), Vector3(x+0.5,y+0.5,boundary_z), Vector3.FORWARD, label)

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
		print("BOUNDARY_PROBE label=%s world=%s chunk=%s local=(%d,%d)" % [probe["label"],cell,chunk,local_x,local_z])
		if local_x == CHUNK_SIZE - 1:
			var east := chunk + Vector2i.RIGHT
			var pair_key := "%s>%s" % [chunk,east]
			if not seen_pairs.has(pair_key):
				seen_pairs[pair_key] = true
				_check_pair(chunk,east,String(probe["label"])+"_east")
		if local_z == CHUNK_SIZE - 1:
			var south := chunk + Vector2i(0,1)
			var pair_key := "%s>%s" % [chunk,south]
			if not seen_pairs.has(pair_key):
				seen_pairs[pair_key] = true
				_check_pair(chunk,south,String(probe["label"])+"_south")
	print("BOUNDARY_BLOCK_DIAGNOSTIC expected_exposed_faces=%d missing_exposed_faces=%d height_only_tree_occlusions=%d suppression_terrain_air=%d missing_from_suppression=%d" % [
		expected_exposed_faces, missing_exposed_faces, height_only_tree_occlusions,
		suppression_terrain_air, missing_from_suppression
	])
	if missing_exposed_faces > 0 or suppression_terrain_air > 0:
		print("CHUNK_BOUNDARY_HOLE_REPRODUCED")
		quit(1)
		return
	print("CHUNK_BOUNDARY_HOLE_NOT_REPRODUCED")
	quit(0)
