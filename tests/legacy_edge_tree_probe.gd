extends SceneTree

const ShippingData = preload("res://scripts/world/playable_world_carpathian_data.gd")
const ShippingCache = preload("res://scripts/world/playable_world_carpathian_generation_cache_fast.gd")
const Stage10Mesher = preload("res://scripts/world/playable_world_stage10_mesher.gd")
const CHUNK_SIZE := 12
const PADDING := 2
const TARGET_CHUNK := Vector2i(-2, 8)
const TARGETS := [
	Vector3i(-19, 12, 95),
	Vector3i(-18, 12, 95),
	Vector3i(-17, 13, 95),
	Vector3i(-17, 14, 95),
]

func _init() -> void:
	if not ClassDB.class_exists(&"TeknikCarpathianSampler"):
		push_error("native sampler missing"); quit(1); return
	var data = ShippingData.new()
	var cache: Dictionary = ShippingCache.build(TARGET_CHUNK, data)
	var heights: PackedInt32Array = cache.get("heights", PackedInt32Array())
	var biomes: PackedByteArray = cache.get("biomes", PackedByteArray())
	var width := roundi(sqrt(float(heights.size())))
	var origin := Vector3i(TARGET_CHUNK.x * CHUNK_SIZE, 0, TARGET_CHUNK.y * CHUNK_SIZE)
	var sources_found := 0
	for cell in TARGETS:
		print("LEGACY_EDGE_TARGET cell=%s direct=%d" % [cell, int(data.get_block(cell))])
		for tree_z in range(cell.z - 1, cell.z + 2):
			for tree_x in range(cell.x - 1, cell.x + 2):
				var cx := tree_x - origin.x + PADDING
				var cz := tree_z - origin.z + PADDING
				if cx < 0 or cx >= width or cz < 0 or cz >= width: continue
				var index := cz * width + cx
				var surface := int(heights[index])
				var biome := int(biomes[index])
				if not Stage10Mesher._legacy_tree_origin(tree_x, tree_z, surface, biome, data.OVERHAUL_WORLD_HEIGHT, data.SEA_LEVEL, data): continue
				var trunk_top := surface + int(data.TREE_TRUNK_HEIGHT)
				var covers := false
				var block_kind := "none"
				if cell.x == tree_x and cell.z == tree_z and cell.y > surface and cell.y <= trunk_top:
					covers = true; block_kind = "log"
				elif cell.y >= trunk_top - 1 and cell.y <= trunk_top + 1:
					covers = true; block_kind = "leaves"
				if not covers: continue
				var outer := cx == 0 or cz == 0 or cx == width - 1 or cz == width - 1
				var direct_surface := int(data.terrain_height(tree_x, tree_z))
				var direct_biome := int(data.biome_at(tree_x, tree_z))
				var accepted_direct := bool(data.is_tree_origin_for_biome(tree_x, tree_z, direct_surface, direct_biome))
				print("LEGACY_EDGE_SOURCE target=%s origin=(%d,%d) surface=%d cache=(%d,%d) outer_ring=%s block=%s direct_origin=%s direct_surface=%d direct_biome=%d" % [cell,tree_x,tree_z,surface,cx,cz,outer,block_kind,accepted_direct,direct_surface,direct_biome])
				if outer and not accepted_direct:
					sources_found += 1
	print("LEGACY_EDGE_SOURCE_COUNT=%d" % sources_found)
	if sources_found > 0:
		print("LEGACY_EDGE_PHANTOM_TREE_REPRODUCED")
		quit(1)
		return
	print("LEGACY_EDGE_PHANTOM_TREE_NOT_FOUND")
	quit(0)
