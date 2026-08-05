extends RefCounted

const BLOCK_AIR := 0
const BLOCK_GRASS := 1
const BLOCK_DIRT := 2
const BLOCK_STONE := 3
const BLOCK_SAND := 4
const BLOCK_LOG := 5
const BLOCK_LEAVES := 6
const WORLD_SEED := 734921
const TREE_SPACING := 7
const TREE_OFFSET := 3
const TREE_TRUNK_HEIGHT := 4
const TREE_CANOPY_RADIUS := 1

const FACE_DIRECTIONS: Array[Vector3i] = [
	Vector3i.UP,
	Vector3i.DOWN,
	Vector3i.RIGHT,
	Vector3i.LEFT,
	Vector3i(0, 0, 1),
	Vector3i(0, 0, -1),
]
const FACE_NORMALS: Array[Vector3] = [
	Vector3.UP,
	Vector3.DOWN,
	Vector3.RIGHT,
	Vector3.LEFT,
	Vector3.BACK,
	Vector3.FORWARD,
]
const FACE_VERTICES: Array = [
	[Vector3(0, 1, 0), Vector3(0, 1, 1), Vector3(1, 1, 1), Vector3(1, 1, 0)],
	[Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(1, 0, 1), Vector3(0, 0, 1)],
	[Vector3(1, 0, 0), Vector3(1, 1, 0), Vector3(1, 1, 1), Vector3(1, 0, 1)],
	[Vector3(0, 0, 0), Vector3(0, 0, 1), Vector3(0, 1, 1), Vector3(0, 1, 0)],
	[Vector3(0, 0, 1), Vector3(1, 0, 1), Vector3(1, 1, 1), Vector3(0, 1, 1)],
	[Vector3(0, 0, 0), Vector3(0, 1, 0), Vector3(1, 1, 0), Vector3(1, 0, 0)],
]


static func build(
	coord: Vector2i,
	heights: PackedInt32Array,
	overrides: Dictionary,
	chunk_size: int,
	world_height: int,
	sea_level: int
) -> Dictionary:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	var face_count := 0
	var origin := Vector3i(coord.x * chunk_size, 0, coord.y * chunk_size)
	var cache_width := chunk_size + 2

	for local_z in range(chunk_size):
		for local_x in range(chunk_size):
			for y in range(world_height):
				var cell := Vector3i(origin.x + local_x, y, origin.z + local_z)
				var block := _get_block(cell, origin, heights, overrides, cache_width, world_height, sea_level)
				if block == BLOCK_AIR:
					continue
				for face_index in range(6):
					var neighbor := cell + FACE_DIRECTIONS[face_index]
					if _get_block(neighbor, origin, heights, overrides, cache_width, world_height, sea_level) != BLOCK_AIR:
						continue
					var base_index := vertices.size()
					var color := _block_color(block, cell, _face_shade(face_index))
					var local_cell := Vector3(local_x, y, local_z)
					var face_vertices: Array = FACE_VERTICES[face_index]
					for vertex_value: Variant in face_vertices:
						vertices.append(local_cell + Vector3(vertex_value))
						normals.append(FACE_NORMALS[face_index])
						colors.append(color)
					indices.append_array(PackedInt32Array([
						base_index,
						base_index + 2,
						base_index + 1,
						base_index,
						base_index + 3,
						base_index + 2,
					]))
					face_count += 1

	return {
		"vertices": vertices,
		"normals": normals,
		"colors": colors,
		"indices": indices,
		"face_count": face_count,
	}


static func _get_block(
	cell: Vector3i,
	origin: Vector3i,
	heights: PackedInt32Array,
	overrides: Dictionary,
	cache_width: int,
	world_height: int,
	sea_level: int
) -> int:
	if cell.y < 0:
		return BLOCK_STONE
	if cell.y >= world_height:
		return BLOCK_AIR
	var key := "%d,%d,%d" % [cell.x, cell.y, cell.z]
	if overrides.has(key):
		return int(overrides[key])
	var cache_x := cell.x - origin.x + 1
	var cache_z := cell.z - origin.z + 1
	if cache_x < 0 or cache_x >= cache_width or cache_z < 0 or cache_z >= cache_width:
		return BLOCK_AIR
	var height := heights[cache_z * cache_width + cache_x]
	if cell.y <= height:
		return _terrain_block(cell.y, height, sea_level)
	return _generated_tree_block(cell, origin, heights, cache_width, world_height, sea_level)


static func _terrain_block(y: int, height: int, sea_level: int) -> int:
	if y == height:
		return BLOCK_SAND if height <= sea_level + 1 else BLOCK_GRASS
	if y >= height - 3:
		return BLOCK_SAND if height <= sea_level + 1 else BLOCK_DIRT
	return BLOCK_STONE


static func _generated_tree_block(
	cell: Vector3i,
	origin: Vector3i,
	heights: PackedInt32Array,
	cache_width: int,
	world_height: int,
	sea_level: int
) -> int:
	for tree_z in range(cell.z - TREE_CANOPY_RADIUS, cell.z + TREE_CANOPY_RADIUS + 1):
		for tree_x in range(cell.x - TREE_CANOPY_RADIUS, cell.x + TREE_CANOPY_RADIUS + 1):
			var cache_x := tree_x - origin.x + 1
			var cache_z := tree_z - origin.z + 1
			if cache_x < 0 or cache_x >= cache_width or cache_z < 0 or cache_z >= cache_width:
				continue
			var surface := heights[cache_z * cache_width + cache_x]
			if not _is_tree_origin(tree_x, tree_z, surface, world_height, sea_level):
				continue
			var trunk_top := surface + TREE_TRUNK_HEIGHT
			if cell.x == tree_x and cell.z == tree_z and cell.y > surface and cell.y <= trunk_top:
				return BLOCK_LOG
			if cell.y >= trunk_top - 1 and cell.y <= trunk_top + 1:
				return BLOCK_LEAVES
	return BLOCK_AIR


static func _is_tree_origin(x: int, z: int, surface: int, world_height: int, sea_level: int) -> bool:
	if posmod(x, TREE_SPACING) != TREE_OFFSET or posmod(z, TREE_SPACING) != TREE_OFFSET:
		return false
	if surface <= sea_level + 1 or surface + TREE_TRUNK_HEIGHT + 1 >= world_height:
		return false
	var hash_value := absi((x * 73856093) ^ (z * 19349663) ^ WORLD_SEED)
	return hash_value % 4 != 0


static func _block_color(block: int, cell: Vector3i, shade: float) -> Color:
	var base_color: Color
	match block:
		BLOCK_GRASS:
			base_color = Color(0.34, 0.68, 0.25) if shade >= 0.98 else Color(0.38, 0.48, 0.23)
		BLOCK_DIRT:
			base_color = Color(0.50, 0.34, 0.20)
		BLOCK_STONE:
			base_color = Color(0.56, 0.58, 0.60)
		BLOCK_SAND:
			base_color = Color(0.82, 0.75, 0.54)
		BLOCK_LOG:
			base_color = Color(0.48, 0.30, 0.14)
		BLOCK_LEAVES:
			base_color = Color(0.22, 0.52, 0.18)
		_:
			base_color = Color.WHITE
	var hash_value := absi((cell.x * 73856093) ^ (cell.y * 83492791) ^ (cell.z * 19349663))
	var variation := 0.97 + float(hash_value % 7) * 0.01
	var factor := shade * variation
	return Color(
		clampf(base_color.r * factor, 0.0, 1.0),
		clampf(base_color.g * factor, 0.0, 1.0),
		clampf(base_color.b * factor, 0.0, 1.0),
		1.0
	)


static func _face_shade(face_index: int) -> float:
	match face_index:
		0:
			return 1.0
		1:
			return 0.78
		2, 3:
			return 0.92
		_:
			return 0.86
