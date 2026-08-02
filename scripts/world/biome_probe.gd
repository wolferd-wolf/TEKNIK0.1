extends Node

const CHUNK_SCRIPT := preload("res://scripts/world/chunk.gd")


static func run(chunk: Node) -> void:
	assert(chunk.biomes.size() == CHUNK_SCRIPT.SIZE.x * CHUNK_SCRIPT.SIZE.z)
	assert(chunk.vegetation_density.size() == CHUNK_SCRIPT.SIZE.x * CHUNK_SCRIPT.SIZE.z)

	for local_x in range(CHUNK_SCRIPT.SIZE.x):
		for local_z in range(CHUNK_SCRIPT.SIZE.z):
			var column := Vector2i(local_x, local_z)
			var biome_id: int = chunk.get_biome(column)
			var density: int = chunk.get_vegetation_density(column)
			assert(biome_id >= CHUNK_SCRIPT.BIOME_PLAINS)
			assert(biome_id <= CHUNK_SCRIPT.BIOME_DESERT)
			assert(density >= 0 and density <= 100)

			if biome_id == CHUNK_SCRIPT.BIOME_DESERT:
				assert(density == 0)
