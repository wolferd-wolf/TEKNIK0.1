extends RefCounted
class_name ChunkMesher

const CHUNK_SIZE := Vector3i(16, 16, 16)
const BLOCK_AIR := 0
const BLOCK_GRASS := 1
const BLOCK_DIRT := 2
const BLOCK_STONE := 3
const BLOCK_SAND := 4
const TRIANGLE_INDICES := [0, 1, 2, 0, 2, 3]

const FACE_NORMALS := [
	Vector3.LEFT,
	Vector3.RIGHT,
	Vector3.DOWN,
	Vector3.UP,
	Vector3.FORWARD,
	Vector3.BACK,
]

const FACE_VERTICES := [
	[Vector3(0, 0, 1), Vector3(0, 0, 0), Vector3(0, 1, 0), Vector3(0, 1, 1)],
	[Vector3(1, 0, 0), Vector3(1, 0, 1), Vector3(1, 1, 1), Vector3(1, 1, 0)],
	[Vector3(0, 0, 0), Vector3(0, 0, 1), Vector3(1, 0, 1), Vector3(1, 0, 0)],
	[Vector3(0, 1, 1), Vector3(0, 1, 0), Vector3(1, 1, 0), Vector3(1, 1, 1)],
	[Vector3(1, 0, 0), Vector3(0, 0, 0), Vector3(0, 1, 0), Vector3(1, 1, 0)],
	[Vector3(0, 0, 1), Vector3(1, 0, 1), Vector3(1, 1, 1), Vector3(0, 1, 1)],
]


static func build_mesh(chunk) -> ArrayMesh:
	var surface_tool := SurfaceTool.new()
	surface_tool.begin(Mesh.PRIMITIVE_TRIANGLES)

	for local_y in range(CHUNK_SIZE.y):
		for local_z in range(CHUNK_SIZE.z):
			for local_x in range(CHUNK_SIZE.x):
				var local_coord := Vector3i(local_x, local_y, local_z)
				var block_id: int = chunk.get_block(local_coord)
				if block_id == BLOCK_AIR:
					continue

				_append_block_faces(surface_tool, local_coord, block_id)

	return surface_tool.commit()


static func _append_block_faces(
	surface_tool: SurfaceTool,
	local_coord: Vector3i,
	block_id: int
) -> void:
	var origin := Vector3(local_coord)
	var color := _color_for_block(block_id)

	for face_index in range(FACE_VERTICES.size()):
		var face_vertices: Array = FACE_VERTICES[face_index]
		var normal: Vector3 = FACE_NORMALS[face_index]
		for vertex_index in TRIANGLE_INDICES:
			surface_tool.set_normal(normal)
			surface_tool.set_color(color)
			surface_tool.add_vertex(origin + face_vertices[vertex_index])


static func create_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.roughness = 1.0
	return material


static func _color_for_block(block_id: int) -> Color:
	match block_id:
		BLOCK_GRASS:
			return Color(0.29, 0.62, 0.22)
		BLOCK_DIRT:
			return Color(0.42, 0.26, 0.14)
		BLOCK_STONE:
			return Color(0.46, 0.48, 0.50)
		BLOCK_SAND:
			return Color(0.78, 0.70, 0.45)
		_:
			return Color.WHITE
