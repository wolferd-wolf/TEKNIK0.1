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
const DETAIL_LIMIT := 20

var failures: Array[String] = []
var mismatch_details: Array[Dictionary] = []
var topology_faces := 0
var topology_triangles := 0
var side_faces := 0
var brightness_diagonal_mismatches := 0
var severe_side_faces := 0


func _fail(message: String) -> void:
	failures.append(message)
	push_error(message)


func _luminance(color: Color) -> float:
	return color.r * 0.2126 + color.g * 0.7152 + color.b * 0.0722


func _relative_pattern(indices: PackedInt32Array, index_offset: int, base: int) -> Array[int]:
	var result: Array[int] = []
	for i in range(6):
		result.append(int(indices[index_offset + i]) - base)
	return result


func _same_pattern(a: Array[int], b: Array) -> bool:
	if a.size() != b.size():
		return false
	for i in range(a.size()):
		if int(a[i]) != int(b[i]):
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


func _inspect_mesh(coord: Vector2i, mesh_data: Dictionary) -> void:
	var vertices: PackedVector3Array = mesh_data.get("vertices", PackedVector3Array())
	var normals: PackedVector3Array = mesh_data.get("normals", PackedVector3Array())
	var colors: PackedColorArray = mesh_data.get("colors", PackedColorArray())
	var indices: PackedInt32Array = mesh_data.get("indices", PackedInt32Array())
	var face_count: int = int(mesh_data.get("face_count", 0))
	if vertices.size() != face_count * 4:
		_fail("%s vertex count %d != face_count*4 (%d)" % [coord, vertices.size(), face_count * 4])
		return
	if normals.size() != vertices.size() or colors.size() != vertices.size():
		_fail("%s vertex/normal/color array sizes disagree" % coord)
		return
	if indices.size() != face_count * 6:
		_fail("%s index count %d != face_count*6 (%d)" % [coord, indices.size(), face_count * 6])
		return

	var chunk_origin := Vector3(coord.x * CHUNK_SIZE, 0, coord.y * CHUNK_SIZE)
	for face_number in range(face_count):
		topology_faces += 1
		var base := face_number * 4
		var index_offset := face_number * 6
		var rel := _relative_pattern(indices, index_offset, base)
		var is_default := _same_pattern(rel, DEFAULT_REL)
		var is_flipped := _same_pattern(rel, FLIPPED_REL)
		if not is_default and not is_flipped:
			_fail("%s face %d has cross-face/invalid indices %s" % [coord, face_number, rel])
			continue

		var normal: Vector3 = normals[base]
		for triangle in range(2):
			topology_triangles += 1
			var i0 := int(indices[index_offset + triangle * 3])
			var i1 := int(indices[index_offset + triangle * 3 + 1])
			var i2 := int(indices[index_offset + triangle * 3 + 2])
			var a: Vector3 = vertices[i0]
			var b: Vector3 = vertices[i1]
			var c: Vector3 = vertices[i2]
			var cross := (b - a).cross(c - a)
			var area := cross.length() * 0.5
			if absf(area - 0.5) > EPS:
				_fail("%s face %d triangle %d area %.6f is not a unit-face half" % [coord, face_number, triangle, area])
			if cross.normalized().dot(normal) > -0.999:
				_fail("%s face %d triangle %d winding disagrees with outward normal" % [coord, face_number, triangle])

		if absf(normal.y) > 0.5:
			continue
		side_faces += 1
		var light: Array[float] = []
		for vertex_offset in range(4):
			light.append(_luminance(colors[base + vertex_offset]))
		var min_light: float = light.min()
		var max_light: float = light.max()
		var spread := max_light - min_light
		var actual_flip := is_flipped
		# The existing mesher chooses this relation from AO levels only. Applying
		# the same relation to the final vertex brightness shows whether sky light
		# changed which diagonal the rendered quad actually wants.
		var final_brightness_flip := light[0] + light[2] > light[1] + light[3] + EPS
		var disagrees := actual_flip != final_brightness_flip
		var contrast_ratio := min_light / maxf(max_light, EPS)
		if contrast_ratio < 0.45 and spread > 0.08:
			severe_side_faces += 1
		if not disagrees or spread <= 0.03:
			continue
		brightness_diagonal_mismatches += 1
		var center := Vector3.ZERO
		for vertex_offset in range(4):
			center += vertices[base + vertex_offset]
		center = center * 0.25 + chunk_origin
		mismatch_details.append({
			"coord": coord,
			"face": face_number,
			"center": center,
			"normal": normal,
			"light": light,
			"spread": spread,
			"ratio": contrast_ratio,
			"actual_flip": actual_flip,
			"final_flip": final_brightness_flip,
		})


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

	print("SIDE_FACE_TARGET world=(%d,%d) chunk=%s" % [TARGET_WORLD.x, TARGET_WORLD.y, TARGET_CHUNK])
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var coord := TARGET_CHUNK + Vector2i(dx, dz)
			var mesh_data := _build_shipping_mesh(coord, data)
			if not mesh_data.is_empty():
				_inspect_mesh(coord, mesh_data)

	mismatch_details.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a["spread"]) > float(b["spread"])
	)
	for i in range(mini(DETAIL_LIMIT, mismatch_details.size())):
		var item: Dictionary = mismatch_details[i]
		print("SIDE_FACE_LIGHT_MISMATCH chunk=%s face=%d center=%s normal=%s light=%s spread=%.4f ratio=%.4f ao_selected_flip=%s final_brightness_flip=%s" % [
			item["coord"],
			int(item["face"]),
			item["center"],
			item["normal"],
			item["light"],
			float(item["spread"]),
			float(item["ratio"]),
			bool(item["actual_flip"]),
			bool(item["final_flip"]),
		])

	print("SIDE_FACE_TOPOLOGY faces=%d triangles=%d failures=%d" % [
		topology_faces, topology_triangles, failures.size()
	])
	print("SIDE_FACE_LIGHTING side_faces=%d diagonal_mismatches=%d severe_dark_faces=%d" % [
		side_faces, brightness_diagonal_mismatches, severe_side_faces
	])
	if not failures.is_empty():
		print("SIDE_FACE_TOPOLOGY_FAIL")
		quit(1)
		return
	print("SIDE_FACE_TOPOLOGY_PASS")
	if brightness_diagonal_mismatches <= 0:
		_fail("Target region did not reproduce AO-vs-final-brightness diagonal disagreement")
		quit(1)
		return
	print("SIDE_FACE_LIGHTING_ARTIFACT_REPRODUCED")
	# Deliberately red before a fix: topology is valid, but the current AO-only
	# diagonal policy demonstrably disagrees with the final shaded vertex data.
	quit(1)
