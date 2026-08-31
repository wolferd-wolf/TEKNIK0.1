extends RefCounted

const BASE_MESHER := preload("res://scripts/world/playable_world_mesher.gd")

const BLOCK_AIR := 0
static var WORLD_SEED: int = 734921
const TREE_SPACING := 7
const TREE_OFFSET := 3
const FOREST_TREE_SPACING := 5
const FOREST_TREE_OFFSET := 1
const TREE_TRUNK_HEIGHT := 4
const TREE_CANOPY_RADIUS := 1
const BIOME_PLAINS := 0
const BIOME_FOREST := 1
const BIOME_DESERT := 2
const BIOME_ROCKY := 3


static func _tree_origin_from_cache(
	tree_x: int,
	tree_z: int,
	origin: Vector3i,
	heights: PackedInt32Array,
	biomes: PackedByteArray,
	cache_width: int,
	cache_padding: int,
	world_height: int,
	sea_level: int,
	blocked: Dictionary
) -> bool:
	var cache_x := tree_x - origin.x + cache_padding
	var cache_z := tree_z - origin.z + cache_padding
	if cache_x < 0 or cache_x >= cache_width or cache_z < 0 or cache_z >= cache_width:
		return false
	var index := cache_z * cache_width + cache_x
	if blocked.has(index):
		return false
	var surface := int(heights[index])
	var biome := BIOME_PLAINS
	if biomes.size() == cache_width * cache_width:
		biome = int(biomes[index])
	if biome == BIOME_DESERT or biome == BIOME_ROCKY:
		return false
	if surface <= sea_level + 1 or surface + TREE_TRUNK_HEIGHT + 1 >= world_height:
		return false
	var baseline_grid := (
		posmod(tree_x, TREE_SPACING) == TREE_OFFSET
		and posmod(tree_z, TREE_SPACING) == TREE_OFFSET
	)
	var forest_grid := (
		biome == BIOME_FOREST
		and posmod(tree_x, FOREST_TREE_SPACING) == FOREST_TREE_OFFSET
		and posmod(tree_z, FOREST_TREE_SPACING) == FOREST_TREE_OFFSET
	)
	if not baseline_grid and not forest_grid:
		return false
	var hash_value := absi((tree_x * 73856093) ^ (tree_z * 19349663) ^ WORLD_SEED)
	if forest_grid and not baseline_grid:
		return hash_value % 3 != 0
	return hash_value % 4 != 0


static func _has_unblocked_tree_block(
	cell: Vector3i,
	origin: Vector3i,
	heights: PackedInt32Array,
	biomes: PackedByteArray,
	cache_width: int,
	cache_padding: int,
	world_height: int,
	sea_level: int,
	blocked: Dictionary
) -> bool:
	for tree_z in range(cell.z - TREE_CANOPY_RADIUS, cell.z + TREE_CANOPY_RADIUS + 1):
		for tree_x in range(cell.x - TREE_CANOPY_RADIUS, cell.x + TREE_CANOPY_RADIUS + 1):
			if not _tree_origin_from_cache(
				tree_x,
				tree_z,
				origin,
				heights,
				biomes,
				cache_width,
				cache_padding,
				world_height,
				sea_level,
				blocked
			):
				continue
			var cache_x := tree_x - origin.x + cache_padding
			var cache_z := tree_z - origin.z + cache_padding
			var surface := int(heights[cache_z * cache_width + cache_x])
			var trunk_top := surface + TREE_TRUNK_HEIGHT
			if cell.x == tree_x and cell.z == tree_z and cell.y > surface and cell.y <= trunk_top:
				return true
			if cell.y >= trunk_top - 1 and cell.y <= trunk_top + 1:
				return true
	return false


static func _suppression_overrides(
	coord: Vector2i,
	heights: PackedInt32Array,
	biomes: PackedByteArray,
	overrides: Dictionary,
	chunk_size: int,
	world_height: int,
	sea_level: int,
	blocked_tree_columns: PackedInt32Array
) -> Dictionary:
	if blocked_tree_columns.is_empty():
		return overrides
	var cache_width := roundi(sqrt(float(heights.size())))
	if cache_width * cache_width != heights.size():
		cache_width = chunk_size + 2
	var cache_padding := maxi(floori(float(cache_width - chunk_size) * 0.5), 1)
	var origin := Vector3i(coord.x * chunk_size, 0, coord.y * chunk_size)
	var blocked: Dictionary = {}
	for index in blocked_tree_columns:
		blocked[int(index)] = true

	var mesher_overrides := overrides.duplicate(true)
	for index_value in blocked_tree_columns:
		var index := int(index_value)
		if index < 0 or index >= heights.size():
			continue
		var cache_x := index % cache_width
		var cache_z := int(index / cache_width)
		var tree_x := origin.x + cache_x - cache_padding
		var tree_z := origin.z + cache_z - cache_padding
		var surface := int(heights[index])
		var trunk_top := surface + TREE_TRUNK_HEIGHT
		for y in range(surface + 1, trunk_top + 1):
			var cell := Vector3i(tree_x, y, tree_z)
			if _has_unblocked_tree_block(
				cell,
				origin,
				heights,
				biomes,
				cache_width,
				cache_padding,
				world_height,
				sea_level,
				blocked
			):
				continue
			var key := "%d,%d,%d" % [cell.x, cell.y, cell.z]
			if not mesher_overrides.has(key):
				mesher_overrides[key] = BLOCK_AIR
		for canopy_z in range(tree_z - TREE_CANOPY_RADIUS, tree_z + TREE_CANOPY_RADIUS + 1):
			for canopy_x in range(tree_x - TREE_CANOPY_RADIUS, tree_x + TREE_CANOPY_RADIUS + 1):
				for y in range(trunk_top - 1, trunk_top + 2):
					var cell := Vector3i(canopy_x, y, canopy_z)
					if _has_unblocked_tree_block(
						cell,
						origin,
						heights,
						biomes,
						cache_width,
						cache_padding,
						world_height,
						sea_level,
						blocked
					):
						continue
					var key := "%d,%d,%d" % [cell.x, cell.y, cell.z]
					if not mesher_overrides.has(key):
						mesher_overrides[key] = BLOCK_AIR
	return mesher_overrides


static func build(
	coord: Vector2i,
	heights: PackedInt32Array,
	overrides: Dictionary,
	chunk_size: int,
	world_height: int,
	sea_level: int,
	biomes: PackedByteArray = PackedByteArray(),
	blocked_tree_columns: PackedInt32Array = PackedInt32Array()
) -> Dictionary:
	var mesher_overrides := _suppression_overrides(
		coord,
		heights,
		biomes,
		overrides,
		chunk_size,
		world_height,
		sea_level,
		blocked_tree_columns
	)
	return BASE_MESHER.build(
		coord,
		heights,
		mesher_overrides,
		chunk_size,
		world_height,
		sea_level,
		biomes
	)
