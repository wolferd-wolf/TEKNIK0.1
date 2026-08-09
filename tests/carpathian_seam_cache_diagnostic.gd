extends SceneTree

const ShippingData = preload("res://scripts/world/playable_world_carpathian_data.gd")
const ShippingCache = preload("res://scripts/world/playable_world_carpathian_generation_cache_fast.gd")
const CHUNK_SIZE := 12
const PADDING := 2
const WIDTH := CHUNK_SIZE + PADDING * 2
const MIN_CHUNK_X := -20
const MAX_CHUNK_X := 20
const MIN_CHUNK_Z := -12
const MAX_CHUNK_Z := 12
const MAX_DETAIL_LINES := 24


func _cache_index(coord: Vector2i, world_x: int, world_z: int) -> int:
	var min_x: int = coord.x * CHUNK_SIZE - PADDING
	var min_z: int = coord.y * CHUNK_SIZE - PADDING
	var cache_x: int = world_x - min_x
	var cache_z: int = world_z - min_z
	if cache_x < 0 or cache_x >= WIDTH or cache_z < 0 or cache_z >= WIDTH:
		return -1
	return cache_z * WIDTH + cache_x


func _compare_overlap(
	a_coord: Vector2i,
	a_cache: Dictionary,
	b_coord: Vector2i,
	b_cache: Dictionary,
	detail_budget: int
) -> Dictionary:
	var a_heights: PackedInt32Array = a_cache.get("heights", PackedInt32Array())
	var b_heights: PackedInt32Array = b_cache.get("heights", PackedInt32Array())
	var a_water: PackedByteArray = a_cache.get("stage7_water_types", PackedByteArray())
	var b_water: PackedByteArray = b_cache.get("stage7_water_types", PackedByteArray())
	if (
		a_heights.size() != WIDTH * WIDTH
		or b_heights.size() != WIDTH * WIDTH
		or a_water.size() != WIDTH * WIDTH
		or b_water.size() != WIDTH * WIDTH
	):
		return {"invalid": 1, "height": 0, "water": 0, "details": 0}

	var a_min_x: int = a_coord.x * CHUNK_SIZE - PADDING
	var a_max_x: int = a_min_x + WIDTH - 1
	var a_min_z: int = a_coord.y * CHUNK_SIZE - PADDING
	var a_max_z: int = a_min_z + WIDTH - 1
	var b_min_x: int = b_coord.x * CHUNK_SIZE - PADDING
	var b_max_x: int = b_min_x + WIDTH - 1
	var b_min_z: int = b_coord.y * CHUNK_SIZE - PADDING
	var b_max_z: int = b_min_z + WIDTH - 1
	var overlap_min_x: int = maxi(a_min_x, b_min_x)
	var overlap_max_x: int = mini(a_max_x, b_max_x)
	var overlap_min_z: int = maxi(a_min_z, b_min_z)
	var overlap_max_z: int = mini(a_max_z, b_max_z)
	if overlap_min_x > overlap_max_x or overlap_min_z > overlap_max_z:
		return {"invalid": 0, "height": 0, "water": 0, "details": 0}

	var height_mismatches := 0
	var water_mismatches := 0
	var details_printed := 0
	for world_z in range(overlap_min_z, overlap_max_z + 1):
		for world_x in range(overlap_min_x, overlap_max_x + 1):
			var a_index: int = _cache_index(a_coord, world_x, world_z)
			var b_index: int = _cache_index(b_coord, world_x, world_z)
			var ah: int = int(a_heights[a_index])
			var bh: int = int(b_heights[b_index])
			var aw: int = int(a_water[a_index])
			var bw: int = int(b_water[b_index])
			if ah != bh:
				height_mismatches += 1
				if details_printed < detail_budget:
					print("SEAM_HEIGHT_MISMATCH a=%s b=%s world=(%d,%d) a_h=%d b_h=%d a_w=%d b_w=%d" % [
						a_coord, b_coord, world_x, world_z, ah, bh, aw, bw
					])
					details_printed += 1
			if aw != bw:
				water_mismatches += 1
				if details_printed < detail_budget:
					print("SEAM_WATER_MISMATCH a=%s b=%s world=(%d,%d) a_h=%d b_h=%d a_w=%d b_w=%d" % [
						a_coord, b_coord, world_x, world_z, ah, bh, aw, bw
					])
					details_printed += 1
	return {
		"invalid": 0,
		"height": height_mismatches,
		"water": water_mismatches,
		"details": details_printed,
	}


func _init() -> void:
	if not ClassDB.class_exists(&"TeknikCarpathianSampler"):
		push_error("TeknikCarpathianSampler was not loaded")
		quit(1)
		return
	var data = ShippingData.new()
	if not data.carpathian_enabled():
		push_error("Shipping Carpathian adapter did not activate")
		quit(1)
		return

	var caches: Dictionary = {}
	for chunk_z in range(MIN_CHUNK_Z, MAX_CHUNK_Z + 1):
		for chunk_x in range(MIN_CHUNK_X, MAX_CHUNK_X + 1):
			var coord := Vector2i(chunk_x, chunk_z)
			var cache: Dictionary = ShippingCache.build(coord, data)
			if cache.is_empty():
				push_error("Empty shipping cache at %s" % coord)
				quit(1)
				return
			caches[coord] = cache

	var invalid_pairs := 0
	var height_mismatches := 0
	var water_mismatches := 0
	var details_printed := 0
	for chunk_z in range(MIN_CHUNK_Z, MAX_CHUNK_Z + 1):
		for chunk_x in range(MIN_CHUNK_X, MAX_CHUNK_X + 1):
			var coord := Vector2i(chunk_x, chunk_z)
			for delta in [Vector2i(1, 0), Vector2i(0, 1)]:
				var neighbor: Vector2i = coord + delta
				if not caches.has(neighbor):
					continue
				var result: Dictionary = _compare_overlap(
					coord,
					caches[coord],
					neighbor,
					caches[neighbor],
					MAX_DETAIL_LINES - details_printed
				)
				invalid_pairs += int(result["invalid"])
				height_mismatches += int(result["height"])
				water_mismatches += int(result["water"])
				details_printed += int(result["details"])

	print("CARPATHIAN_SEAM_CACHE_DIAGNOSTIC pairs_invalid=%d height_mismatches=%d water_mismatches=%d" % [
		invalid_pairs, height_mismatches, water_mismatches
	])
	if invalid_pairs != 0 or height_mismatches != 0 or water_mismatches != 0:
		push_error("Shipping padded caches disagree on shared world columns")
		quit(1)
		return
	print("CARPATHIAN_SEAM_CACHE_PASS")
	quit(0)
