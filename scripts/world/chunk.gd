extends Node3D
class_name VoxelChunk

const CHUNK_MESHER_SCRIPT := preload("res://scripts/world/chunk_mesher.gd")

const SIZE := Vector3i(16, 16, 16)
const BLOCK_AIR := 0
const BLOCK_GRASS := 1
const BLOCK_DIRT := 2
const BLOCK_STONE := 3
const BLOCK_SAND := 4

const BIOME_PLAINS := 0
const BIOME_FOREST := 1
const BIOME_DESERT := 2

const PLAINS_VEGETATION_DENSITY := 20
const FOREST_VEGETATION_DENSITY := 75
const DESERT_VEGETATION_DENSITY := 0

var chunk_coord: Vector3i = Vector3i.ZERO
var blocks: PackedByteArray = PackedByteArray()
var biomes: PackedByteArray = PackedByteArray()
var vegetation_density: PackedByteArray = PackedByteArray()
var mesh_instance: MeshInstance3D
var collision_body: StaticBody3D
var collision_shape: CollisionShape3D


func configure(coord: Vector3i) -> void:
	chunk_coord = coord
	position = Vector3(
		coord.x * SIZE.x,
		coord.y * SIZE.y,
		coord.z * SIZE.z
	)
	blocks.resize(SIZE.x * SIZE.y * SIZE.z)
	blocks.fill(BLOCK_AIR)
	biomes.resize(SIZE.x * SIZE.z)
	biomes.fill(BIOME_PLAINS)
	vegetation_density.resize(SIZE.x * SIZE.z)
	vegetation_density.fill(PLAINS_VEGETATION_DENSITY)
	_ensure_render_nodes()


func generate_terrain(
	elevation_noise: FastNoiseLite,
	biome_noise: FastNoiseLite,
	base_height: int,
	height_amplitude: int
) -> void:
	for local_x in range(SIZE.x):
		for local_z in range(SIZE.z):
			var world_x := chunk_coord.x * SIZE.x + local_x
			var world_z := chunk_coord.z * SIZE.z + local_z
			var sampled_height := base_height + roundi(
				elevation_noise.get_noise_2d(world_x, world_z) * height_amplitude
			)
			var biome_id := _biome_from_noise(biome_noise.get_noise_2d(world_x, world_z))
			var column_coord := Vector2i(local_x, local_z)
			set_biome(column_coord, biome_id)
			set_vegetation_density(column_coord, _density_for_biome(biome_id))

			for local_y in range(SIZE.y):
				var world_y := chunk_coord.y * SIZE.y + local_y
				var block_id := _block_for_depth(sampled_height - world_y, biome_id)
				set_block(Vector3i(local_x, local_y, local_z), block_id)


func rebuild_mesh(world_block_lookup: Callable) -> void:
	_ensure_render_nodes()
	var chunk_mesh: ArrayMesh = CHUNK_MESHER_SCRIPT.build_mesh(self, world_block_lookup)
	mesh_instance.mesh = chunk_mesh
	if mesh_instance.material_override == null:
		mesh_instance.material_override = CHUNK_MESHER_SCRIPT.create_material()

	collision_shape.shape = null
	if chunk_mesh != null and chunk_mesh.get_surface_count() > 0:
		collision_shape.shape = chunk_mesh.create_trimesh_shape()


func _ensure_render_nodes() -> void:
	if not is_instance_valid(mesh_instance):
		mesh_instance = MeshInstance3D.new()
		mesh_instance.name = "ChunkMesh"
		add_child(mesh_instance)
	if not is_instance_valid(collision_body):
		collision_body = StaticBody3D.new()
		collision_body.name = "ChunkCollision"
		add_child(collision_body)
	if not is_instance_valid(collision_shape):
		collision_shape = CollisionShape3D.new()
		collision_shape.name = "CollisionShape3D"
		collision_body.add_child(collision_shape)


func _biome_from_noise(sample: float) -> int:
	if sample < -0.25:
		return BIOME_DESERT
	if sample > 0.25:
		return BIOME_FOREST
	return BIOME_PLAINS


func _density_for_biome(biome_id: int) -> int:
	match biome_id:
		BIOME_FOREST:
			return FOREST_VEGETATION_DENSITY
		BIOME_DESERT:
			return DESERT_VEGETATION_DENSITY
		_:
			return PLAINS_VEGETATION_DENSITY


func _block_for_depth(depth_below_surface: int, biome_id: int) -> int:
	if depth_below_surface < 0:
		return BLOCK_AIR
	if depth_below_surface == 0:
		return BLOCK_SAND if biome_id == BIOME_DESERT else BLOCK_GRASS
	if depth_below_surface <= 3:
		return BLOCK_DIRT
	return BLOCK_STONE


func set_block(local_coord: Vector3i, block_id: int) -> void:
	if not is_local_coord_valid(local_coord):
		return
	blocks[_block_index(local_coord)] = block_id


func get_block(local_coord: Vector3i) -> int:
	if not is_local_coord_valid(local_coord):
		return BLOCK_AIR
	return blocks[_block_index(local_coord)]


func set_biome(local_column: Vector2i, biome_id: int) -> void:
	if not is_local_column_valid(local_column):
		return
	biomes[_column_index(local_column)] = biome_id


func get_biome(local_column: Vector2i) -> int:
	if not is_local_column_valid(local_column):
		return BIOME_PLAINS
	return biomes[_column_index(local_column)]


func set_vegetation_density(local_column: Vector2i, density: int) -> void:
	if not is_local_column_valid(local_column):
		return
	vegetation_density[_column_index(local_column)] = clampi(density, 0, 100)


func get_vegetation_density(local_column: Vector2i) -> int:
	if not is_local_column_valid(local_column):
		return 0
	return vegetation_density[_column_index(local_column)]


func is_local_coord_valid(local_coord: Vector3i) -> bool:
	return (
		local_coord.x >= 0 and local_coord.x < SIZE.x
		and local_coord.y >= 0 and local_coord.y < SIZE.y
		and local_coord.z >= 0 and local_coord.z < SIZE.z
	)


func is_local_column_valid(local_column: Vector2i) -> bool:
	return (
		local_column.x >= 0 and local_column.x < SIZE.x
		and local_column.y >= 0 and local_column.y < SIZE.z
	)


func _block_index(local_coord: Vector3i) -> int:
	return local_coord.x + SIZE.x * (local_coord.z + SIZE.z * local_coord.y)


func _column_index(local_column: Vector2i) -> int:
	return local_column.x + SIZE.x * local_column.y
