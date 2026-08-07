extends RefCounted

const WORLD_DATA := preload("res://scripts/world/playable_world_data.gd")
const WORLD_MAP_OVERLAY := preload("res://scripts/ui/world_map_overlay.gd")
const CHUNK_SIZE := 12
const PADDING := 2
const WIDTH := CHUNK_SIZE + PADDING * 2
const DEVICE_MAP_CENTER := Vector2i(157, -16)
const DEVICE_MAP_HALF_SPAN := 48


static func run(data, failures: Array[String]) -> void:
	if WORLD_DATA.NOISE_SAMPLES_PER_COLUMN != 4 or WORLD_DATA.DOMAIN_WARPED_LAYER_COUNT != 4:
		_fail(failures, "Step 4 changed the accepted four-noise/domain-warp contract")
	if WORLD_DATA.BIOME_COUNT != 4:
		_fail(failures, "Step 4 must retain exactly four biomes")
	if WORLD_DATA.BIOME_BLEND_WIDTH <= 0.0 or WORLD_DATA.BIOME_BLEND_WIDTH >= 0.25:
		_fail(failures, "Biome blend width is outside the bounded Stage 1 range")
	if WORLD_DATA.BIOME_BLEND_PATCH_SIZE < 2 or WORLD_DATA.BIOME_BLEND_PATCH_SIZE > 4:
		_fail(failures, "Biome blend patch size must prevent single-cell speckle without creating large tiles")
	_validate_weight_contract(data, failures)
	_validate_mountain_contract(data, failures)
	_validate_sources(failures)
	_validate_determinism_and_continuity(data, failures)


static func _validate_weight_contract(data, failures: Array[String]) -> void:
	var pure_cases: Array = [
		[0.0, 0.0, WORLD_DATA.BIOME_PLAINS],
		[0.0, 0.5, WORLD_DATA.BIOME_FOREST],
		[0.5, -0.5, WORLD_DATA.BIOME_DESERT],
		[-0.5, 0.0, WORLD_DATA.BIOME_ROCKY],
	]
	for entry: Array in pure_cases:
		var weights: Vector4 = data.biome_weights_from_climate(float(entry[0]), float(entry[1]))
		_validate_weights(weights, failures, "pure climate %s" % str(entry))
		if weights[int(entry[2])] < 0.995:
			_fail(failures, "Pure climate did not strongly select biome %d: %s" % [int(entry[2]), weights])

	var border_cases: Array = [
		[WORLD_DATA.BIOME_HOT_THRESHOLD, WORLD_DATA.BIOME_DRY_THRESHOLD],
		[0.0, WORLD_DATA.BIOME_WET_THRESHOLD],
		[WORLD_DATA.BIOME_COLD_THRESHOLD, 0.0],
	]
	for entry: Array in border_cases:
		var weights: Vector4 = data.biome_weights_from_climate(float(entry[0]), float(entry[1]))
		_validate_weights(weights, failures, "border climate %s" % str(entry))
		var meaningful := 0
		for biome in range(WORLD_DATA.BIOME_COUNT):
			if weights[biome] >= 0.10:
				meaningful += 1
		if meaningful < 2:
			_fail(failures, "Classifier border remained a hard one-biome edge: %s" % weights)

	for temperature_index in range(-10, 11):
		for moisture_index in range(-10, 11):
			var weights: Vector4 = data.biome_weights_from_climate(
				float(temperature_index) / 10.0,
				float(moisture_index) / 10.0
			)
			_validate_weights(weights, failures, "climate grid")

	var even_weights := Vector4(0.25, 0.25, 0.25, 0.25)
	var patch_result: int = data.blended_biome_from_weights(even_weights, 0, 0)
	for point in [Vector2i(1, 0), Vector2i(2, 0), Vector2i(0, 1), Vector2i(2, 2)]:
		var actual: int = data.blended_biome_from_weights(even_weights, point.x, point.y)
		if actual != patch_result:
			_fail(failures, "Three-block blend patch produced single-cell salt-and-pepper variation")
	var negative_patch: int = data.blended_biome_from_weights(even_weights, -1, -1)
	for point in [Vector2i(-2, -1), Vector2i(-3, -1), Vector2i(-1, -2), Vector2i(-3, -3)]:
		var actual: int = data.blended_biome_from_weights(even_weights, point.x, point.y)
		if actual != negative_patch:
			_fail(failures, "Negative-coordinate blend patch does not use floor-based world continuity")

	for biome in range(WORLD_DATA.BIOME_COUNT):
		var shore: int = data.terrain_block(WORLD_DATA.SEA_LEVEL + 1, WORLD_DATA.SEA_LEVEL + 1, biome)
		if shore != WORLD_DATA.BLOCK_SAND:
			_fail(failures, "Biome blending broke the sandy shoreline contract")


static func _validate_mountain_contract(data, failures: Array[String]) -> void:
	if WORLD_DATA.WORLD_HEIGHT < 40:
		_fail(failures, "World height still lacks headroom for the rocky mountain profile")
	if WORLD_DATA.ROCKY_MOUNTAIN_BASE_RISE <= 0.0 or WORLD_DATA.ROCKY_MOUNTAIN_RUGGEDNESS <= 0.0:
		_fail(failures, "Rocky biome has no positive mountain elevation parameters")

	var plains_samples := Vector4(0.35, 0.45, 0.0, 0.0)
	var rocky_samples := Vector4(0.35, 0.45, -0.8, -0.4)
	var desert_samples := Vector4(0.35, 0.45, 0.8, -0.8)
	var plains_height: int = data.terrain_height_from_samples(plains_samples)
	var rocky_height: int = data.terrain_height_from_samples(rocky_samples)
	var desert_height: int = data.terrain_height_from_samples(desert_samples)
	if rocky_height < plains_height + 8:
		_fail(failures, "Rocky climate still changes only material instead of producing mountain elevation")
	if absi(desert_height - plains_height) > 1:
		_fail(failures, "Mountain elevation leaked into non-rocky climate")
	if data.rocky_mountain_weight_from_climate(-0.8, -0.4) < 0.99:
		_fail(failures, "Pure rocky climate does not produce a full mountain weight")
	if data.rocky_mountain_weight_from_climate(0.0, 0.0) > 0.01:
		_fail(failures, "Neutral plains climate incorrectly receives mountain elevation")

	var ocean_height: int = data.terrain_height_from_samples(Vector4(-1.0, -1.0, -1.0, -1.0))
	if ocean_height > WORLD_DATA.SEA_LEVEL:
		_fail(failures, "Cold ocean basins were lifted into mountains")
	var peak_height: int = data.terrain_height_from_samples(Vector4(1.0, 1.0, -1.0, -1.0))
	if peak_height < WORLD_DATA.SEA_LEVEL + 20:
		_fail(failures, "Synthetic rocky peak remains too low to read as a mountain")
	if peak_height > WORLD_DATA.WORLD_HEIGHT - 3:
		_fail(failures, "Synthetic rocky peak clips the world-height safety margin")

	var rocky_columns := 0
	var elevated_rocky_columns := 0
	var local_peak := 0
	for z in range(
		DEVICE_MAP_CENTER.y - DEVICE_MAP_HALF_SPAN,
		DEVICE_MAP_CENTER.y + DEVICE_MAP_HALF_SPAN + 1,
		2
	):
		for x in range(
			DEVICE_MAP_CENTER.x - DEVICE_MAP_HALF_SPAN,
			DEVICE_MAP_CENTER.x + DEVICE_MAP_HALF_SPAN + 1,
			2
		):
			var samples: Vector4 = data.sample_column_noise(x, z)
			var height: int = data.terrain_height_from_samples(samples)
			local_peak = maxi(local_peak, height)
			if data.blended_biome_from_samples(samples, x, z) != WORLD_DATA.BIOME_ROCKY:
				continue
			rocky_columns += 1
			if height >= WORLD_DATA.SEA_LEVEL + 8:
				elevated_rocky_columns += 1
	if rocky_columns < 200:
		_fail(failures, "Device-reported map area no longer contains the visible rocky region")
	if elevated_rocky_columns * 3 < rocky_columns:
		_fail(failures, "Most of the device-reported rocky region remains ordinary-height terrain")
	if local_peak < WORLD_DATA.SEA_LEVEL + 10:
		_fail(failures, "Device-reported map area still contains no meaningful mountain peak")

	var overlay = WORLD_MAP_OVERLAY.new()
	var low_color: Color = overlay._map_color(WORLD_DATA.BLOCK_STONE, WORLD_DATA.SEA_LEVEL + 2)
	var high_color: Color = overlay._map_color(WORLD_DATA.BLOCK_STONE, WORLD_DATA.WORLD_HEIGHT - 3)
	var low_brightness := low_color.r + low_color.g + low_color.b
	var high_brightness := high_color.r + high_color.g + high_color.b
	if high_brightness <= low_brightness + 0.25:
		_fail(failures, "Map stone color does not visibly distinguish low rocky ground from high mountains")
	overlay.free()


static func _validate_weights(weights: Vector4, failures: Array[String], context: String) -> void:
	var total := weights.x + weights.y + weights.z + weights.w
	if absf(total - 1.0) > 0.0001:
		_fail(failures, "Biome weights are not normalized during %s: %.6f" % [context, total])
	for biome in range(WORLD_DATA.BIOME_COUNT):
		if weights[biome] < -0.0001 or weights[biome] > 1.0001:
			_fail(failures, "Biome weight %d is outside [0,1] during %s" % [biome, context])


static func _validate_sources(failures: Array[String]) -> void:
	var data_source := FileAccess.get_file_as_string("res://scripts/world/playable_world_data.gd")
	for required in [
		"biome_weights_from_climate",
		"blended_biome_from_samples",
		"BIOME_BLEND_PATCH_SIZE",
		"rocky_mountain_weight_from_climate",
		"ROCKY_MOUNTAIN_RUGGEDNESS",
	]:
		if not data_source.contains(required):
			_fail(failures, "Step 4 production source is missing %s" % required)
	var sample_start := data_source.find("func sample_column_noise")
	var height_start := data_source.find("func rocky_mountain_weight_from_climate", sample_start)
	if sample_start < 0 or height_start < 0:
		_fail(failures, "Unable to isolate the production four-noise sampler")
	else:
		var sample_body := data_source.substr(sample_start, height_start - sample_start)
		if _count(sample_body, ".get_noise_2d(") != 4:
			_fail(failures, "Production sampler must retain exactly four get_noise_2d calls")
	var weights_start := data_source.find("func biome_weights_from_climate")
	var biome_at_start := data_source.find("func biome_at", weights_start)
	if weights_start < 0 or biome_at_start < 0:
		_fail(failures, "Unable to isolate the Step 4 blend implementation")
	else:
		var blend_body := data_source.substr(weights_start, biome_at_start - weights_start)
		if blend_body.contains(".get_noise_2d(") or blend_body.contains("sample_column_noise("):
			_fail(failures, "Biome blending added extra noise samples instead of reusing climate values")

	var map_source := FileAccess.get_file_as_string("res://scripts/ui/world_map_overlay.gd")
	if not map_source.contains("BRIGHTER = HIGHER"):
		_fail(failures, "Map legend does not explain that brightness represents elevation")
	if not map_source.contains("WORLD_HEIGHT - WORLD_DATA.SEA_LEVEL"):
		_fail(failures, "Map elevation shading is not normalized to the actual world height")

	var runtime_source := FileAccess.get_file_as_string("res://scripts/world/playable_world_runtime.gd")
	var cache_start := runtime_source.find("func _build_column_caches")
	var old_cache_start := runtime_source.find("func _build_height_cache", cache_start)
	if cache_start < 0 or old_cache_start < 0:
		_fail(failures, "Shipping runtime is missing the shared blended column cache")
	else:
		var cache_body := runtime_source.substr(cache_start, old_cache_start - cache_start)
		if _count(cache_body, "sample_column_noise(") != 1:
			_fail(failures, "Shipping runtime must still sample once per column")
		if not cache_body.contains("terrain_height_from_samples") or not cache_body.contains("blended_biome_from_samples"):
			_fail(failures, "Shipping runtime does not derive height and blended biome from one sample vector")


static func _validate_determinism_and_continuity(data, failures: Array[String]) -> void:
	for z in range(-192, 193, 13):
		for x in range(-192, 193, 9):
			var first: int = data.biome_at(x, z)
			var second: int = data.biome_at(x, z)
			if first != second or first < 0 or first >= WORLD_DATA.BIOME_COUNT:
				_fail(failures, "Invalid or nondeterministic blended biome at (%d,%d)" % [x, z])
	var origin: PackedByteArray = _build_biomes(data, Vector2i.ZERO)
	var east: PackedByteArray = _build_biomes(data, Vector2i(1, 0))
	var south: PackedByteArray = _build_biomes(data, Vector2i(0, 1))
	var negative: PackedByteArray = _build_biomes(data, Vector2i(-1, -1))
	for local_z in range(CHUNK_SIZE):
		var a: int = _cached(origin, CHUNK_SIZE, local_z)
		var b: int = _cached(east, 0, local_z)
		var direct: int = data.biome_at(CHUNK_SIZE, local_z)
		if a != b or b != direct:
			_fail(failures, "East blended-biome boundary mismatch at z=%d" % local_z)
	for local_x in range(CHUNK_SIZE):
		var a: int = _cached(origin, local_x, CHUNK_SIZE)
		var b: int = _cached(south, local_x, 0)
		var direct: int = data.biome_at(local_x, CHUNK_SIZE)
		if a != b or b != direct:
			_fail(failures, "South blended-biome boundary mismatch at x=%d" % local_x)
	for local_z in range(CHUNK_SIZE):
		var direct: int = data.biome_at(-CHUNK_SIZE, -CHUNK_SIZE + local_z)
		if _cached(negative, 0, local_z) != direct:
			_fail(failures, "Negative blended-biome cache mismatch at z=%d" % local_z)


static func _build_biomes(data, coord: Vector2i) -> PackedByteArray:
	var result := PackedByteArray()
	result.resize(WIDTH * WIDTH)
	var origin_x := coord.x * CHUNK_SIZE
	var origin_z := coord.y * CHUNK_SIZE
	for local_z in range(-PADDING, CHUNK_SIZE + PADDING):
		for local_x in range(-PADDING, CHUNK_SIZE + PADDING):
			var index := (local_z + PADDING) * WIDTH + local_x + PADDING
			result[index] = data.biome_at(origin_x + local_x, origin_z + local_z)
	return result


static func _cached(cache: PackedByteArray, x: int, z: int) -> int:
	return int(cache[(z + PADDING) * WIDTH + x + PADDING])


static func _count(text: String, needle: String) -> int:
	var count := 0
	var offset := 0
	while true:
		var found := text.find(needle, offset)
		if found < 0:
			return count
		count += 1
		offset = found + needle.length()
	return count


static func _fail(failures: Array[String], message: String) -> void:
	if not failures.has(message):
		failures.append(message)
