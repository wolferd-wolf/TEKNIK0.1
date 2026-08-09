extends SceneTree

const ShippingData = preload("res://scripts/world/playable_world_carpathian_data.gd")
const ShippingCache = preload("res://scripts/world/playable_world_carpathian_generation_cache_fast.gd")
const ShippingStage12Cache = preload("res://scripts/world/playable_world_stage12_cache_fast.gd")
const ShippingMesher = preload("res://scripts/world/playable_world_stage12_mesher.gd")
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
var cache_height_mismatches := 0
var cache_water_mismatches := 0
var direct_height_mismatches := 0
var expected_boundary_faces := 0
var missing_boundary_faces := 0
var details_printed := 0

func _fail(message: String) -> void:
	failures.append(message)
	push_error(message)

func _cache_index(coord: Vector2i, world_x: int, world_z: int, width: int) -> int:
	var min_x := coord.x * CHUNK_SIZE - PADDING
	var min_z := coord.y * CHUNK_SIZE - PADDING
	var cx := world_x - min_x
	var cz := world_z - min_z
	if cx < 0 or cx >= width or cz < 0 or cz >= width:
		return -1
	return cz * width + cx

func _build_mesh(coord: Vector2i, data) -> Dictionary:
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
	var mesh_height := mini(data.OVERHAUL_WORLD_HEIGHT, Stage2Runtime._effective_mesh_height(coord, heights, {}) + 2)
	return ShippingMesher.build(coord, heights, {}, CHUNK_SIZE, mesh_height, data.SEA_LEVEL, biomes, water_types, terrain_modifiers, transition_codes, hydrology_codes, data, blocked_tree_columns)

func _face_key(center: Vector3, normal: Vector3) -> String:
	return "%.1f,%.1f,%.1f|%.0f,%.0f,%.0f" % [center.x, center.y, center.z, normal.x, normal.y, normal.z]

func _mesh_face_lookup(coord: Vector2i, mesh_data: Dictionary) -> Dictionary:
	var lookup := {}
	var vertices: PackedVector3Array = mesh_data.get("vertices", PackedVector3Array())
	var normals: PackedVector3Array = mesh_data.get("normals", PackedVector3Array())
	var face_count := int(mesh_data.get("face_count", 0))
	var origin := Vector3(coord.x * CHUNK_SIZE, 0.0, coord.y * CHUNK_SIZE)
	if vertices.size() != face_count * 4 or normals.size() != vertices.size():
		_fail("invalid mesh arrays %s" % coord)
		return lookup
	for face in range(face_count):
		var base := face * 4
		var center := origin
		for i in range(4):
			center += vertices[base + i] * 0.25
		lookup[_face_key(center, normals[base])] = true
	return lookup

func _check_shared_cache(a: Vector2i, b: Vector2i, data, label: String) -> void:
	var ca: Dictionary = ShippingCache.build(a, data)
	var cb: Dictionary = ShippingCache.build(b, data)
	var ha: PackedInt32Array = ca.get("heights", PackedInt32Array())
	var hb: PackedInt32Array = cb.get("heights", PackedInt32Array())
	var wa: PackedByteArray = ca.get("stage7_water_types", PackedByteArray())
	var wb: PackedByteArray = cb.get("stage7_water_types", PackedByteArray())
	var width := CHUNK_SIZE + PADDING * 2
	var min_x := maxi(a.x * CHUNK_SIZE - PADDING, b.x * CHUNK_SIZE - PADDING)
	var max_x := mini(a.x * CHUNK_SIZE + CHUNK_SIZE + PADDING - 1, b.x * CHUNK_SIZE + CHUNK_SIZE + PADDING - 1)
	var min_z := maxi(a.y * CHUNK_SIZE - PADDING, b.y * CHUNK_SIZE - PADDING)
	var max_z := mini(a.y * CHUNK_SIZE + CHUNK_SIZE + PADDING - 1, b.y * CHUNK_SIZE + CHUNK_SIZE + PADDING - 1)
	for z in range(min_z, max_z + 1):
		for x in range(min_x, max_x + 1):
			var ia := _cache_index(a, x, z, width)
			var ib := _cache_index(b, x, z, width)
			if ia < 0 or ib < 0:
				continue
			var ah := int(ha[ia])
			var bh := int(hb[ib])
			var direct := data.terrain_height(x, z)
			if ah != bh:
				cache_height_mismatches += 1
				if details_printed < 40:
					print("BOUNDARY_CACHE_HEIGHT_MISMATCH label=%s world=(%d,%d) a=%s a_h=%d b=%s b_h=%d direct=%d river=%.4f" % [label,x,z,a,ah,b,bh,direct,data.stage5_river_signal(x,z)])
					details_printed += 1
			if ah != direct or bh != direct:
				direct_height_mismatches += 1
			if wa.size() == ha.size() and wb.size() == hb.size() and int(wa[ia]) != int(wb[ib]):
				cache_water_mismatches += 1
				if details_printed < 40:
					print("BOUNDARY_CACHE_WATER_MISMATCH label=%s world=(%d,%d) a_w=%d b_w=%d" % [label,x,z,int(wa[ia]),int(wb[ib])])
					details_printed += 1

func _expect_wall_face(lookup: Dictionary, center: Vector3, normal: Vector3, label: String, owner: Vector2i) -> void:
	expected_boundary_faces += 1
	var key := _face_key(center, normal)
	if lookup.has(key):
		return
	missing_boundary_faces += 1
	if details_printed < 40:
		print("BOUNDARY_TERRAIN_FACE_MISSING label=%s owner=%s center=%s normal=%s" % [label,owner,center,normal])
		details_printed += 1

func _check_boundary_faces(a: Vector2i, b: Vector2i, data, label: String) -> void:
	var la := _mesh_face_lookup(a, _build_mesh(a, data))
	var lb := _mesh_face_lookup(b, _build_mesh(b, data))
	var dx := b.x - a.x
	var dz := b.y - a.y
	if absi(dx) + absi(dz) != 1:
		_fail("non-cardinal pair %s %s" % [a,b])
		return
	if dx != 0:
		var boundary_x := mini(a.x, b.x) * CHUNK_SIZE + CHUNK_SIZE
		var left_chunk := a if a.x < b.x else b
		var right_chunk := b if a.x < b.x else a
		var left_lookup: Dictionary = la if a.x < b.x else lb
		var right_lookup: Dictionary = lb if a.x < b.x else la
		var z0 := a.y * CHUNK_SIZE
		for z in range(z0, z0 + CHUNK_SIZE):
			var left_h := data.terrain_height(boundary_x - 1, z)
			var right_h := data.terrain_height(boundary_x, z)
			if left_h > right_h:
				for y in range(right_h + 1, left_h + 1):
					_expect_wall_face(left_lookup, Vector3(boundary_x, y + 0.5, z + 0.5), Vector3.RIGHT, label, left_chunk)
			elif right_h > left_h:
				for y in range(left_h + 1, right_h + 1):
					_expect_wall_face(right_lookup, Vector3(boundary_x, y + 0.5, z + 0.5), Vector3.LEFT, label, right_chunk)
	else:
		var boundary_z := mini(a.y, b.y) * CHUNK_SIZE + CHUNK_SIZE
		var north_chunk := a if a.y < b.y else b
		var south_chunk := b if a.y < b.y else a
		var north_lookup: Dictionary = la if a.y < b.y else lb
		var south_lookup: Dictionary = lb if a.y < b.y else la
		var x0 := a.x * CHUNK_SIZE
		for x in range(x0, x0 + CHUNK_SIZE):
			var north_h := data.terrain_height(x, boundary_z - 1)
			var south_h := data.terrain_height(x, boundary_z)
			if north_h > south_h:
				for y in range(south_h + 1, north_h + 1):
					_expect_wall_face(north_lookup, Vector3(x + 0.5, y + 0.5, boundary_z), Vector3.BACK, label, north_chunk)
			elif south_h > north_h:
				for y in range(north_h + 1, south_h + 1):
					_expect_wall_face(south_lookup, Vector3(x + 0.5, y + 0.5, boundary_z), Vector3.FORWARD, label, south_chunk)

func _init() -> void:
	if not ClassDB.class_exists(&"TeknikCarpathianSampler"):
		_fail("TeknikCarpathianSampler not loaded")
		quit(1)
		return
	var data = ShippingData.new()
	if not data.carpathian_enabled():
		_fail("Carpathian shipping sampler not active")
		quit(1)
		return
	for probe in PROBES:
		var cell: Vector2i = probe["cell"]
		var chunk := Vector2i(floori(float(cell.x) / CHUNK_SIZE), floori(float(cell.y) / CHUNK_SIZE))
		var local_x := posmod(cell.x, CHUNK_SIZE)
		var local_z := posmod(cell.y, CHUNK_SIZE)
		print("BOUNDARY_PROBE label=%s world=%s chunk=%s local=(%d,%d)" % [probe["label"],cell,chunk,local_x,local_z])
		if local_x == CHUNK_SIZE - 1:
			var east := chunk + Vector2i.RIGHT
			_check_shared_cache(chunk, east, data, String(probe["label"]) + "_east")
			_check_boundary_faces(chunk, east, data, String(probe["label"]) + "_east")
		if local_z == CHUNK_SIZE - 1:
			var south := chunk + Vector2i(0, 1)
			_check_shared_cache(chunk, south, data, String(probe["label"]) + "_south")
			_check_boundary_faces(chunk, south, data, String(probe["label"]) + "_south")
	print("BOUNDARY_DIAGNOSTIC cache_height_mismatches=%d cache_water_mismatches=%d direct_height_mismatches=%d expected_faces=%d missing_faces=%d" % [cache_height_mismatches,cache_water_mismatches,direct_height_mismatches,expected_boundary_faces,missing_boundary_faces])
	if cache_height_mismatches > 0 or cache_water_mismatches > 0 or missing_boundary_faces > 0:
		print("CHUNK_BOUNDARY_HOLE_REPRODUCED")
		quit(1)
		return
	print("CHUNK_BOUNDARY_HOLE_NOT_REPRODUCED")
	quit(0)
