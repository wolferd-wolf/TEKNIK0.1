extends SceneTree

const Stage7Data = preload("res://scripts/world/playable_world_stage7_biome_data.gd")


func _fail(message: String) -> void:
	push_error("WORLD_OVERHAUL_STAGE7_FAIL: %s" % message)
	quit(1)


func _init() -> void:
	var data = Stage7Data.new()

	# Prototype identity: the existing four ecological identities must remain
	# reachable without introducing any Stage 8 biome IDs.
	if data.stage7_classify_with_context(Vector2(0.0, 0.0), 0.0, 20, data.WATER_NONE) != data.BIOME_PLAINS:
		_fail("temperate/medium prototype did not select Plains")
		return
	if data.stage7_classify_with_context(Vector2(-0.02, 0.60), 0.0, 20, data.WATER_NONE) != data.BIOME_FOREST:
		_fail("wet temperate prototype did not select Forest")
		return
	if data.stage7_classify_with_context(Vector2(0.65, -0.60), 0.0, 20, data.WATER_NONE) != data.BIOME_DESERT:
		_fail("hot/dry prototype did not select Desert")
		return
	if data.stage7_classify_with_context(Vector2(-0.55, -0.38), 0.65, 60, data.WATER_NONE) != data.BIOME_ROCKY:
		_fail("cold/dry rugged prototype did not select Rocky")
		return

	# Terrain eligibility comes before nearest-prototype selection for Rocky.
	if data.stage7_classify_with_context(Vector2(-0.55, -0.38), 0.0, 20, data.WATER_NONE) == data.BIOME_ROCKY:
		_fail("flat lowland incorrectly selected Rocky")
		return

	# Physical hydrology must be authoritative; wet columns cannot become Forest,
	# Rocky or Desert during Stage 7.
	for water_type in [data.WATER_OCEAN, data.WATER_RIVER, data.WATER_LAKE, data.WATER_POND]:
		if data.stage7_classify_with_context(Vector2(-0.02, 0.70), 0.8, 70, water_type) != data.BIOME_PLAINS:
			_fail("water context did not force neutral ecology for type %d" % water_type)
			return

	# The replacement classifier must not contain coordinate-based patch roulette.
	# Identical climate + physical context must always return the same biome.
	var contexts := [
		[Vector2(0.0, 0.0), 0.0, 20],
		[Vector2(-0.02, 0.55), 0.1, 25],
		[Vector2(0.60, -0.50), 0.1, 30],
		[Vector2(-0.50, -0.35), 0.7, 55],
	]
	for context in contexts:
		var climate: Vector2 = context[0]
		var structure: float = context[1]
		var height: int = context[2]
		var expected := data.stage7_classify_with_context(climate, structure, height, data.WATER_NONE)
		for repeat in range(64):
			var actual := data.stage7_classify_with_context(climate, structure, height, data.WATER_NONE)
			if actual != expected:
				_fail("classifier is not deterministic")
				return

	# Shipping query smoke test: fixed positions must be deterministic, legal IDs,
	# and remain inside the 150-block legal vertical contract.
	if data.OVERHAUL_WORLD_HEIGHT != 150:
		_fail("150-block world-height contract changed")
		return
	var fixed_points := [
		Vector2i(0, 0), Vector2i(64, 64), Vector2i(-96, 48),
		Vector2i(192, -128), Vector2i(-256, -192), Vector2i(384, 224),
	]
	for point in fixed_points:
		var first := data.biome_at(point.x, point.y)
		var second := data.biome_at(point.x, point.y)
		if first != second:
			_fail("biome_at is not deterministic at %s" % point)
			return
		if first < 0 or first >= data.BIOME_COUNT:
			_fail("biome_at returned illegal ID %d at %s" % [first, point])
			return
		var height := data.terrain_height(point.x, point.y)
		if height < 3 or height >= data.OVERHAUL_WORLD_HEIGHT:
			_fail("terrain height escaped legal range at %s: %d" % [point, height])
			return

	print("WORLD_OVERHAUL_STAGE7_PASS")
	quit(0)
