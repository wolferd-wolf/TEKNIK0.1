extends RefCounted

const BLOCK_AIR := 0
const BLOCK_GRASS := 1
const BLOCK_DIRT := 2
const BLOCK_STONE := 3
const BLOCK_SAND := 4

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
const FACE_TANGENT_AXES: Array = [
	[Vector3i.RIGHT, Vector3i(0, 0, 1)],
	[Vector3i.RIGHT, Vector3i(0, 0, 1)],
	[Vector3i.UP, Vector3i(0, 0, 1)],
	[Vector3i.UP, Vector3i(0, 0, 1)],
	[Vector3i.RIGHT, Vector3i.UP],
	[Vector3i.RIGHT, Vector3i.UP],
]
const AO_FACTORS: Array[float] = [0.62, 0.76, 0.88, 1.0]


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
					var face_color := _block_color(block, cell, _face_shade(face_index))
					var local_cell := Vector3(local_x, y, local_z)
					var face_vertices: Array = FACE_VERTICES[face_index]
					var face_ao := PackedInt32Array()
					for vertex_value: Variant in face_vertices:
						var face_vertex := Vector3(vertex_value)
						var ao_level := _vertex_ao(
							cell,
							face_index,
							face_vertex,
							origin,
							heights,
							overrides,
							cache_width,
							world_height,
							sea_level
						)
						vertices.append(local_cell + face_vertex)
						normals.append(FACE_NORMALS[face_index])
						colors.append(_multiply_color(face_color, AO_FACTORS[ao_level]))
						face_ao.append(ao_level)
					if face_ao[0] + face_ao[2] > face_ao[1] + face_ao[3]:
						indices.append_array(PackedInt32Array([
							base_index,
							base_index + 1,
							base_index + 3,
							base_index + 1,
							base_index + 2,
							base_index + 3,
						]))
					else:
						indices.append_array(PackedInt32Array([
							base_index,
							base_index + 1,
							base_index + 2,
							base_index,
							base_index + 2,
							base_index + 3,
						]))
					face_count += 1

	return {
		"vertices": vertices,
		"normals": normals,
		"colors": colors,
		"indices": indices,
		"face_count": face_count,
	}


static func _vertex_ao(
	cell: Vector3i,
	face_index: int,
	face_vertex: Vector3,
	origin: Vector3i,
	heights: PackedInt32Array,
	overrides: Dictionary,
	cache_width: int,
	world_height: int,
	sea_level: int
) -> int:
	var normal := FACE_DIRECTIONS[face_index]
	var tangent_axes: Array = FACE_TANGENT_AXES[face_index]
	var first_axis := Vector3i(tangent_axes[0])
	var second_axis := Vector3i(tangent_axes[1])
	var first_direction := first_axis * _vertex_axis_sign(face_vertex, first_axis)
	var second_direction := second_axis * _vertex_axis_sign(face_vertex, second_axis)
	var outside := cell + normal
	var side_first := _is_solid(
		outside + first_direction,
		origin,
		heights,
		overrides,
		cache_width,
		world_height,
		sea_level
	)
	var side_second := _is_solid(
		outside + second_direction,
		origin,
		heights,
		overrides,
		cache_width,
		world_height,
		sea_level
	)
	var corner := _is_solid(
		outside + first_direction + second_direction,
		origin,
		heights,
		overrides,
		cache_width,
		world_height,
		sea_level
	)
	if side_first and side_second:
		return 0
	return 3 - int(side_first) - int(side_second) - int(corner)


static func _vertex_axis_sign(face_vertex: Vector3, axis: Vector3i) -> int:
	if axis.x != 0:
		return -1 if face_vertex.x < 0.5 else 1
	if axis.y != 0:
		return -1 if face_vertex.y < 0.5 else 1
	return -1 if face_vertex.z < 0.5 else 1


static func _is_solid(
	cell: Vector3i,
	origin: Vector3i,
	heights: PackedInt32Array,
	overrides: Dictionary,
	cache_width: int,
	world_height: int,
	sea_level: int
) -> bool:
	return _get_block(
		cell,
		origin,
		heights,
		overrides,
		cache_width,
		world_height,
		sea_level
	) != BLOCK_AIR


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
	return _generated_block(cell.y, height, sea_level)


static func _generated_block(y: int, height: int, sea_level: int) -> int:
	if y > height:
		return BLOCK_AIR
	if y == height:
		return BLOCK_SAND if height <= sea_level + 1 else BLOCK_GRASS
	if y >= height - 3:
		return BLOCK_SAND if height <= sea_level + 1 else BLOCK_DIRT
	return BLOCK_STONE


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


static func _multiply_color(color: Color, factor: float) -> Color:
	return Color(
		clampf(color.r * factor, 0.0, 1.0),
		clampf(color.g * factor, 0.0, 1.0),
		clampf(color.b * factor, 0.0, 1.0),
		color.a
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
