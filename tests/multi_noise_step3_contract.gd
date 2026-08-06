extends RefCounted

const WORLD_DATA := preload("res://scripts/world/playable_world_data.gd")
const CHUNK_SIZE := 12
const PADDING := 2
const WIDTH := CHUNK_SIZE + PADDING * 2

static func run(data, failures: Array[String]) -> void:
	if WORLD_DATA.NOISE_SAMPLES_PER_COLUMN != 4 or WORLD_DATA.DOMAIN_WARPED_LAYER_COUNT != 4:
		_fail(failures, "Step 3 changed the accepted four-noise/domain-warp contract")
	if WORLD_DATA.BIOME_COUNT != 4:
		_fail(failures, "Step 3 must define exactly four biomes")
	var names: Array[String] = ["plains", "forest", "desert", "rocky"]
	for biome in range(WORLD_DATA.BIOME_COUNT):
		var actual_name: String = data.biome_name(biome)
		if actual_name != names[biome]:
			_fail(failures, "Unexpected biome name/order at id %d" % biome)
	var cases := [
		[0.0, 0.0, WORLD_DATA.BIOME_PLAINS],
		[0.5, -0.5, WORLD_DATA.BIOME_DESERT],
		[0.0, 0.5, WORLD_DATA.BIOME_FOREST],
		[-0.5, 0.0, WORLD_DATA.BIOME_ROCKY],
	]
	for entry in cases:
		var actual: int = data.select_biome_from_climate(float(entry[0]), float(entry[1]))
		if actual != int(entry[2]):
			_fail(failures, "Climate classifier contract failed for %s" % str(entry))
	for biome in range(WORLD_DATA.BIOME_COUNT):
		var shore: int = data.terrain_block(WORLD_DATA.SEA_LEVEL + 1, WORLD_DATA.SEA_LEVEL + 1, biome)
		if shore != WORLD_DATA.BLOCK_SAND:
			_fail(failures, "Biome %d broke the sandy shoreline contract" % biome)
	_validate_sources(failures)
	_validate_determinism_and_continuity(data, failures)

static func _validate_sources(failures: Array[String]) -> void:
	var data_source := FileAccess.get_file_as_string("res://scripts/world/playable_world_data.gd")
	for forbidden in ["biome_weight", "blend_biome", "smoothstep"]:
		if data_source.contains(forbidden):
			_fail(failures, "Step 4 blending appeared early: %s" % forbidden)
	var sample_start := data_source.find("func sample_column_noise")
	var height_start := data_source.find("func terrain_height_from_samples", sample_start)
	if sample_start < 0 or height_start < 0:
		_fail(failures, "Unable to isolate the production four-noise sampler")
	else:
		var sample_body := data_source.substr(sample_start, height_start - sample_start)
		if _count(sample_body, ".get_noise_2d(") != 4:
			_fail(failures, "Production sampler must retain exactly four get_noise_2d calls")
	var runtime_source := FileAccess.get_file_as_string("res://scripts/world/playable_world_runtime.gd")
	var cache_start := runtime_source.find("func _build_column_caches")
	var old_cache_start := runtime_source.find("func _build_height_cache", cache_start)
	if cache_start < 0 or old_cache_start < 0:
		_fail(failures, "Shipping runtime is missing the shared height+biome cache")
	else:
		var cache_body := runtime_source.substr(cache_start, old_cache_start - cache_start)
		if _count(cache_body, "sample_column_noise(") != 1:
			_fail(failures, "Shipping runtime must sample once per column for both caches")
		if not cache_body.contains("terrain_height_from_samples") or not cache_body.contains("select_biome_from_samples"):
			_fail(failures, "Shipping runtime does not derive both caches from one sample vector")
	if not runtime_source.contains("WORLD_MESHER.build") or not runtime_source.contains("biomes"):
		_fail(failures, "Shipping runtime does not pass biome data into the mesher")

static func _validate_determinism_and_continuity(data, failures: Array[String]) -> void:
	for z in range(-192, 193, 13):
		for x in range(-192, 193, 9):
			var first: int = data.biome_at(x, z)
			var second: int = data.biome_at(x, z)
			if first != second or first < 0 or first >= WORLD_DATA.BIOME_COUNT:
				_fail(failures, "Invalid or nondeterministic biome at (%d,%d)" % [x, z])
	var origin: PackedByteArray = _build_biomes(data, Vector2i.ZERO)
	var east: PackedByteArray = _build_biomes(data, Vector2i(1, 0))
	var south: PackedByteArray = _build_biomes(data, Vector2i(0, 1))
	var negative: PackedByteArray = _build_biomes(data, Vector2i(-1, -1))
	for local_z in range(CHUNK_SIZE):
		var a := _cached(origin, CHUNK_SIZE, local_z)
		var b := _cached(east, 0, local_z)
		var direct: int = data.biome_at(CHUNK_SIZE, local_z)
		if a != b or b != direct:
			_fail(failures, "East biome boundary mismatch at z=%d" % local_z)
	for local_x in range(CHUNK_SIZE):
		var a := _cached(origin, local_x, CHUNK_SIZE)
		var b := _cached(south, local_x, 0)
		var direct: int = data.biome_at(local_x, CHUNK_SIZE)
		if a != b or b != direct:
			_fail(failures, "South biome boundary mismatch at x=%d" % local_x)
	for local_z in range(CHUNK_SIZE):
		var direct: int = data.biome_at(-CHUNK_SIZE, -CHUNK_SIZE + local_z)
		if _cached(negative, 0, local_z) != direct:
			_fail(failures, "Negative biome cache mismatch at z=%d" % local_z)

static func _build_biomes(data, coord: Vector2i) -> PackedByteArray:
	var result := PackedByteArray()
	result.resize(WIDTH * WIDTH)
	var ox := coord.x * CHUNK_SIZE
	var oz := coord.y * CHUNK_SIZE
	for lz in range(-PADDING, CHUNK_SIZE + PADDING):
		for lx in range(-PADDING, CHUNK_SIZE + PADDING):
			var index := (lz + PADDING) * WIDTH + lx + PADDING
			result[index] = data.biome_at(ox + lx, oz + lz)
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
