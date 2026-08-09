extends SceneTree

const ShippingData = preload("res://scripts/world/playable_world_carpathian_data.gd")
const ShippingCache = preload("res://scripts/world/playable_world_carpathian_generation_cache_fast.gd")
const ShippingStage12Cache = preload("res://scripts/world/playable_world_stage12_cache_fast.gd")
const ShippingStage12Mesher = preload("res://scripts/world/playable_world_stage12_mesher.gd")
const FrozenStage11Runtime = preload("res://scripts/world/playable_world_stage11_generation_runtime.gd")
const Stage2Runtime = preload("res://scripts/world/playable_world_stage2_generation_runtime.gd")

const CHUNK_SIZE := 12
const TARGET_WORLD := Vector2i(-4, -9)
const TARGET_CHUNK := Vector2i(-1, -1)
const DEFAULT_REL := [0, 2, 1, 0, 3, 2]
const FLIPPED_REL := [0, 3, 1, 1, 3, 2]
const EPS := 0.0001

var failures: Array[String] = []
var faces := 0
var triangles := 0
var side_faces := 0
var diagonal_mismatches := 0
var severe_dark_faces := 0


func _fail(message: String) -> void:
	failures.append(message)
	push_error(message)


func _luminance(color: Color) -> float:
	return color.r * 0.2126 + color.g * 0.7152 + color.b * 0.0722


func _same_pattern(indices: PackedInt32Array, offset: int, base: int, pattern: Array) -> bool:
	for i in range(6):
		if int(indices[offset + i]) - base != int(pattern[i]):
			return false
	return true


func _build_shipping_mesh(coord: Vector2i, data) -> Dictionary:
	var caches: Dictionary = ShippingCache.build(coord, data)
	if caches.is_empty():
		_fail("Empty shipping cache at %s" % coord)
		return {}
	var heights: PackedInt32Array = caches.get("heights", PackedInt32Array())
	var biomes: PackedByteArray = caches.get("biomes", PackedByteArray())
	var water_types: PackedByteArray = caches.get("stage7_water_types", PackedByteArray())
	var terrain_modifiers: PackedByteArray = caches.get("stage9_terrain_modifiers", PackedByteArray())
	var expression_codes: Dictionary = ShippingStage12Cache.build_expression_codes(caches, data)
	var transition_codes: PackedByteArray = expression_codes.get("transition_codes", PackedByteArray())
	var hydrology_codes: PackedByteArray = expression_codes.get("hydrology_codes", PackedByteArray())
	var blocked_tree_columns: PackedInt32Array = FrozenStage11Runtime._stage6_blocked_tree_columns(
		coord, caches, data
	)
	var mesh_height := mini(
		data.OVERHAUL_WORLD_HEIGHT,
		Stage2Runtime._effective_mesh_height(coord, heights, {}) + 2
	)
	return ShippingStage12Mesher.build(
		coord,
		heights,
		{},
		CHUNK_SIZE,
		mesh_height,
		data.SEA_LEVEL,
		biomes,
		water_types,
		terrain_modifiers,
		transition_codes,
		hydrology_codes,
		data,
		blocked_tree_columns
	)


func _inspect(coord: Vector2i, mesh_data: Dictionary) -> void:
	var vertices: PackedVector3Array = mesh_data.get("vertices", PackedVector3Array())
	var normals: PackedVector3Array = mesh_data.get("normals", PackedVector3Array())
	var colors: PackedColorArray = mesh_data.get("colors", PackedColorArray())
	var indices: PackedInt32Array = mesh_data.get("indices", PackedInt32Array())
	var face_count := int(mesh_data.get("face_count", 0))
	if vertices.size() != face_count * 4:
		_fail("%s vertex count does not match four vertices per face" % coord)
		return
	if normals.size() != vertices.size() or colors.size() != vertices.size():
		_fail("%s vertex/normal/color sizes disagree" % coord)
		return
	if indices.size() != face_count * 6:
		_fail("%s index count does not match six indices per face" % coord)
		return

	for face_number in range(face_count):
		faces += 1
		var base := face_number * 4
		var offset := face_number * 6
		var default_pattern := _same_pattern(indices, offset, base, DEFAULT_REL)
		var flipped_pattern := _same_pattern(indices, offset, base, FLIPPED_REL)
		if not default_pattern and not flipped_pattern:
			_fail("%s face %d has invalid/cross-face indices" % [coord, face_number])
			continue
		var normal: Vector3 = normals[base]
		for tri in range(2):
			triangles += 1
			var i0 := int(indices[offset + tri * 3])
			var i1 := int(indices[offset + tri * 3 + 1])
			var i2 := int(indices[offset + tri * 3 + 2])
			var cross := (vertices[i1] - vertices[i0]).cross(vertices[i2] - vertices[i0])
			if absf(cross.length() * 0.5 - 0.5) > EPS:
				_fail("%s face %d triangle %d is degenerate" % [coord, face_number, tri])
			elif cross.normalized().dot(normal) > -0.999:
				_fail("%s face %d triangle %d has wrong winding" % [coord, face_number, tri])

		if absf(normal.y) > 0.5:
			continue
		side_faces += 1
		var light := [
			_luminance(colors[base]),
			_luminance(colors[base + 1]),
			_luminance(colors[base + 2]),
			_luminance(colors[base + 3]),
		]
		var min_light: float = light.min()
		var max_light: float = light.max()
		if min_light / maxf(max_light, EPS) < 0.45 and max_light - min_light > 0.08:
			severe_dark_faces += 1
		var expected_flip := light[0] + light[2] > light[1] + light[3] + EPS
		if flipped_pattern != expected_flip and max_light - min_light > 0.03:
			diagonal_mismatches += 1
			if diagonal_mismatches <= 12:
				print("SIDE_FACE_POSTFIX_MISMATCH chunk=%s face=%d normal=%s light=%s actual_flip=%s expected_flip=%s" % [
					coord, face_number, normal, light, flipped_pattern, expected_flip
				])


func _init() -> void:
	if not ClassDB.class_exists(&"TeknikCarpathianSampler"):
		_fail("TeknikCarpathianSampler was not loaded")
		quit(1)
		return
	var data = ShippingData.new()
	if not data.carpathian_enabled():
		_fail("Shipping Carpathian adapter did not activate")
		quit(1)
		return

	print("SIDE_FACE_POSTFIX_TARGET world=(%d,%d) chunk=%s" % [TARGET_WORLD.x, TARGET_WORLD.y, TARGET_CHUNK])
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var coord := TARGET_CHUNK + Vector2i(dx, dz)
			var mesh_data := _build_shipping_mesh(coord, data)
			if not mesh_data.is_empty():
				_inspect(coord, mesh_data)

	print("SIDE_FACE_POSTFIX_TOPOLOGY faces=%d triangles=%d failures=%d" % [faces, triangles, failures.size()])
	print("SIDE_FACE_POSTFIX_LIGHTING side_faces=%d diagonal_mismatches=%d severe_dark_faces=%d" % [
		side_faces, diagonal_mismatches, severe_dark_faces
	])
	if not failures.is_empty() or diagonal_mismatches != 0:
		_fail("Final-light diagonal gate failed")
		quit(1)
		return
	print("SIDE_FACE_LIGHTING_DIAGONAL_PASS")
	quit(0)
