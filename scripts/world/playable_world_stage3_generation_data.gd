extends "res://scripts/world/playable_world_stage2_generation_data.gd"

# Frozen Stage 3 data implementation. Stage 4 originally extended this logic in
# the same public file; extracting it here lets Stage 3 remain independently
# testable after later hydrology stages are added.
const STAGE3_FIELD_LATTICE_SPACING := 4
const STAGE3_FIELD_LATTICE_RECIPROCAL := 1.0 / 4.0
const STAGE3_TERRAIN_CLIMATE_LATTICE_SPACING := 8
const STAGE3_TERRAIN_CLIMATE_LATTICE_RECIPROCAL := 1.0 / 8.0
const STAGE3_WARP_LATTICE_SPACING := 64
const STAGE3_WARP_LATTICE_RECIPROCAL := 1.0 / 64.0
const STAGE3_WARP_AMPLITUDE := 24.0
const STAGE3_HASH_MODULUS := 1000003
const STAGE3_HASH_RECIPROCAL := 1.0 / 1000003.0


func _stage3_smooth01(value: float) -> float:
	var t := clampf(value, 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


func _stage3_hash01(lattice_x: int, lattice_z: int, salt: int) -> float:
	var value := (
		(lattice_x * 73856093)
		^ (lattice_z * 19349663)
		^ (world_seed * 83492791)
		^ salt
	)
	value = (value ^ (value >> 13)) * 1274126177
	value = value ^ (value >> 16)
	return float(posmod(value, STAGE3_HASH_MODULUS)) * STAGE3_HASH_RECIPROCAL


func stage3_warp_lattice_vector(lattice_x: int, lattice_z: int) -> Vector2:
	var x_unit := _stage3_hash01(lattice_x, lattice_z, 0x68bc21eb) * 2.0 - 1.0
	var z_unit := _stage3_hash01(lattice_x, lattice_z, 0x02e5be93) * 2.0 - 1.0
	return Vector2(x_unit, z_unit) * STAGE3_WARP_AMPLITUDE


func stage3_macro_warp_offset(x: int, z: int) -> Vector2:
	var lattice_x := floori(float(x) * STAGE3_WARP_LATTICE_RECIPROCAL)
	var lattice_z := floori(float(z) * STAGE3_WARP_LATTICE_RECIPROCAL)
	var origin_x := lattice_x * STAGE3_WARP_LATTICE_SPACING
	var origin_z := lattice_z * STAGE3_WARP_LATTICE_SPACING
	var tx := _stage3_smooth01(float(x - origin_x) * STAGE3_WARP_LATTICE_RECIPROCAL)
	var tz := _stage3_smooth01(float(z - origin_z) * STAGE3_WARP_LATTICE_RECIPROCAL)
	var north_west := stage3_warp_lattice_vector(lattice_x, lattice_z)
	var north_east := stage3_warp_lattice_vector(lattice_x + 1, lattice_z)
	var south_west := stage3_warp_lattice_vector(lattice_x, lattice_z + 1)
	var south_east := stage3_warp_lattice_vector(lattice_x + 1, lattice_z + 1)
	var north := north_west.lerp(north_east, tx)
	var south := south_west.lerp(south_east, tx)
	return north.lerp(south, tz)


func stage3_sample_structure_node(world_x: int, world_z: int) -> float:
	var warp := stage3_macro_warp_offset(world_x, world_z)
	return terrain_shape_noise.get_noise_2d(
		float(world_x) + warp.x,
		float(world_z) + warp.y
	)


func stage3_terrain_structure(x: int, z: int) -> float:
	var node_x := floori(float(x) * STAGE3_FIELD_LATTICE_RECIPROCAL)
	var node_z := floori(float(z) * STAGE3_FIELD_LATTICE_RECIPROCAL)
	var origin_x := node_x * STAGE3_FIELD_LATTICE_SPACING
	var origin_z := node_z * STAGE3_FIELD_LATTICE_SPACING
	var tx := _stage3_smooth01(float(x - origin_x) * STAGE3_FIELD_LATTICE_RECIPROCAL)
	var tz := _stage3_smooth01(float(z - origin_z) * STAGE3_FIELD_LATTICE_RECIPROCAL)
	var north_west := stage3_sample_structure_node(origin_x, origin_z)
	var north_east := stage3_sample_structure_node(origin_x + STAGE3_FIELD_LATTICE_SPACING, origin_z)
	var south_west := stage3_sample_structure_node(origin_x, origin_z + STAGE3_FIELD_LATTICE_SPACING)
	var south_east := stage3_sample_structure_node(
		origin_x + STAGE3_FIELD_LATTICE_SPACING,
		origin_z + STAGE3_FIELD_LATTICE_SPACING
	)
	return lerpf(
		lerpf(north_west, north_east, tx),
		lerpf(south_west, south_east, tx),
		tz
	)


func stage3_sample_terrain_climate_node(world_x: int, world_z: int) -> Vector2:
	var world_xf := float(world_x)
	var world_zf := float(world_z)
	return Vector2(
		temperature_noise.get_noise_2d(world_xf, world_zf),
		moisture_noise.get_noise_2d(world_xf, world_zf)
	)


func stage3_terrain_climate(x: int, z: int) -> Vector2:
	var node_x := floori(float(x) * STAGE3_TERRAIN_CLIMATE_LATTICE_RECIPROCAL)
	var node_z := floori(float(z) * STAGE3_TERRAIN_CLIMATE_LATTICE_RECIPROCAL)
	var origin_x := node_x * STAGE3_TERRAIN_CLIMATE_LATTICE_SPACING
	var origin_z := node_z * STAGE3_TERRAIN_CLIMATE_LATTICE_SPACING
	var tx := _stage3_smooth01(
		float(x - origin_x) * STAGE3_TERRAIN_CLIMATE_LATTICE_RECIPROCAL
	)
	var tz := _stage3_smooth01(
		float(z - origin_z) * STAGE3_TERRAIN_CLIMATE_LATTICE_RECIPROCAL
	)
	var north_west := stage3_sample_terrain_climate_node(origin_x, origin_z)
	var north_east := stage3_sample_terrain_climate_node(
		origin_x + STAGE3_TERRAIN_CLIMATE_LATTICE_SPACING,
		origin_z
	)
	var south_west := stage3_sample_terrain_climate_node(
		origin_x,
		origin_z + STAGE3_TERRAIN_CLIMATE_LATTICE_SPACING
	)
	var south_east := stage3_sample_terrain_climate_node(
		origin_x + STAGE3_TERRAIN_CLIMATE_LATTICE_SPACING,
		origin_z + STAGE3_TERRAIN_CLIMATE_LATTICE_SPACING
	)
	return north_west.lerp(north_east, tx).lerp(
		south_west.lerp(south_east, tx),
		tz
	)


func stage3_unwarped_structure(x: int, z: int) -> float:
	return terrain_shape_noise.get_noise_2d(float(x), float(z))


func sample_world_fields(x: int, z: int) -> Vector4:
	var world_x := float(x)
	var world_z := float(z)
	return Vector4(
		continentalness_noise.get_noise_2d(world_x, world_z),
		stage3_terrain_structure(x, z),
		temperature_noise.get_noise_2d(world_x, world_z),
		moisture_noise.get_noise_2d(world_x, world_z)
	)
