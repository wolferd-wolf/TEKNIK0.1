extends RefCounted

const WORLD_DATA := preload("res://scripts/world/playable_world_data.gd")
const WORLD_MESHER := preload("res://scripts/world/playable_world_mesher.gd")
const CHUNK_SIZE := 12
const PADDING := 2
const WIDTH := CHUNK_SIZE + PADDING * 2

static func run(data, failures: Array[String]) -> void:
	for coord in [Vector2i.ZERO, Vector2i(1, -1), Vector2i(-1, 1)]:
		var caches: Dictionary = build_caches(data, coord)
		var heights: PackedInt32Array = caches["heights"]
		var biomes: PackedByteArray = caches["biomes"]
		var origin := Vector3i(coord.x * CHUNK_SIZE, 0, coord.y * CHUNK_SIZE)
		for local_z in range(CHUNK_SIZE):
			for local_x in range(CHUNK_SIZE):
				for y in range(WORLD_DATA.WORLD_HEIGHT):
					var cell := Vector3i(origin.x + local_x, y, origin.z + local_z)
					var expected: int = data.get_block(cell)
					var actual: int = WORLD_MESHER._get_block(cell, origin, heights, data.overrides, WIDTH, PADDING, WORLD_DATA.WORLD_HEIGHT, WORLD_DATA.SEA_LEVEL, biomes)
					if actual != expected:
						_fail(failures, "Data/mesher block mismatch at %s: %d != %d" % [cell, expected, actual])
						return
		var mesh: Dictionary = WORLD_MESHER.build(coord, heights, data.overrides, CHUNK_SIZE, WORLD_DATA.WORLD_HEIGHT, WORLD_DATA.SEA_LEVEL, biomes)
		if int(mesh.get("face_count", 0)) <= 0:
			_fail(failures, "Biome-aware mesher produced an empty chunk at %s" % coord)

static func build_caches(data, coord: Vector2i) -> Dictionary:
	var heights := PackedInt32Array()
	var biomes := PackedByteArray()
	heights.resize(WIDTH * WIDTH)
	biomes.resize(WIDTH * WIDTH)
	var ox := coord.x * CHUNK_SIZE
	var oz := coord.y * CHUNK_SIZE
	for lz in range(-PADDING, CHUNK_SIZE + PADDING):
		for lx in range(-PADDING, CHUNK_SIZE + PADDING):
			var index := (lz + PADDING) * WIDTH + lx + PADDING
			var samples: Vector4 = data.sample_column_noise(ox + lx, oz + lz)
			heights[index] = data.terrain_height_from_samples(samples)
			biomes[index] = data.select_biome_from_samples(samples)
	return {"heights": heights, "biomes": biomes}

static func build_height_only(data, coord: Vector2i) -> PackedInt32Array:
	var heights := PackedInt32Array()
	heights.resize(WIDTH * WIDTH)
	var ox := coord.x * CHUNK_SIZE
	var oz := coord.y * CHUNK_SIZE
	for lz in range(-PADDING, CHUNK_SIZE + PADDING):
		for lx in range(-PADDING, CHUNK_SIZE + PADDING):
			var index := (lz + PADDING) * WIDTH + lx + PADDING
			var samples: Vector4 = data.sample_column_noise(ox + lx, oz + lz)
			heights[index] = data.terrain_height_from_samples(samples)
	return heights

static func consume_height(cache: PackedInt32Array) -> int:
	var checksum := 0
	for value in cache:
		checksum += value
	return checksum

static func consume_both(caches: Dictionary) -> Dictionary:
	var height := consume_height(caches["heights"])
	var biome := 0
	for value in caches["biomes"]:
		biome += int(value) + 1
	return {"height": height, "biome": biome}

static func _fail(failures: Array[String], message: String) -> void:
	if not failures.has(message):
		failures.append(message)
