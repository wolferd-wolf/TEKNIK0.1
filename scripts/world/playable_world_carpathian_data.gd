extends "res://scripts/world/playable_world_stage13_data.gd"

const CARPATHIAN_CLASS := &"TeknikCarpathianSampler"
const BLOCK_WATER := 7
const CARPATHIAN_HEIGHT_OFFSET := 12
const CARPATHIAN_TREE_JITTER_X_SALT := 0x4b1d53a7
const CARPATHIAN_TREE_JITTER_Z_SALT := 0x7c29e411
const CARPATHIAN_TREE_ACCEPT_SALT := 0x326f9bd5

var _carpathian_sampler: Object = null


func _native_carpathian() -> Object:
	if _carpathian_sampler != null:
		return _carpathian_sampler
	if not ClassDB.class_exists(CARPATHIAN_CLASS):
		return null
	var created: Object = ClassDB.instantiate(CARPATHIAN_CLASS)
	if created == null:
		return null
	created.call("set_seed", world_seed)
	_carpathian_sampler = created
	return _carpathian_sampler


func carpathian_enabled() -> bool:
	return _native_carpathian() != null


func carpathian_height_from_raw(raw_height: int) -> int:
	return clampi(raw_height + CARPATHIAN_HEIGHT_OFFSET, 3, STAGE2_SAFE_TERRAIN_TOP)


func carpathian_generate_grid(origin_x: int, origin_z: int, width: int, depth: int, step: int = 1) -> PackedInt32Array:
	var native: Object = _native_carpathian()
	if native == null:
		return PackedInt32Array()
	return native.call("generate_grid_shifted", origin_x, origin_z, width, depth, step, CARPATHIAN_HEIGHT_OFFSET, 3, STAGE2_SAFE_TERRAIN_TOP)


func carpathian_provisional_height_at(x: int, z: int) -> int:
	var native: Object = _native_carpathian()
	if native == null:
		return build_provisional_terrain(sample_world_fields(x, z))
	return carpathian_height_from_raw(int(native.call("sample_height", x, z)))


func _carpathian_stage4_height(fields: Vector4, provisional_height: int) -> int:
	var continentalness: float = clampf(fields.x, -1.0, 1.0)
	if continentalness <= STAGE4_OCEAN_WATER_START:
		var ocean_strength: float = stage4_ocean_strength(continentalness)
		var ocean_floor: int = roundi(lerpf(float(STAGE4_OCEAN_EDGE_FLOOR), float(STAGE4_OCEAN_CORE_FLOOR), ocean_strength))
		return mini(provisional_height, ocean_floor)
	if continentalness < STAGE4_COAST_INLAND_END:
		var inland_weight: float = stage4_coast_inland_weight(continentalness)
		return roundi(lerpf(float(SEA_LEVEL), float(provisional_height), inland_weight))
	return provisional_height


func _carpathian_stage5_height(fields: Vector4, stage4_height: int, x: int, z: int) -> int:
	if fields.x <= STAGE4_OCEAN_WATER_START:
		return stage4_height
	return stage5_shape_height_from_signal(fields.x, stage4_height, stage5_river_signal(x, z))


func stage6_stage5_height_at(x: int, z: int) -> int:
	if not carpathian_enabled():
		return super.stage6_stage5_height_at(x, z)
	var fields: Vector4 = sample_world_fields(x, z)
	var provisional_height: int = carpathian_provisional_height_at(x, z)
	var stage4_height: int = _carpathian_stage4_height(fields, provisional_height)
	return finalize_height(_carpathian_stage5_height(fields, stage4_height, x, z))


func terrain_height(x: int, z: int) -> int:
	if not carpathian_enabled():
		return super.terrain_height(x, z)
	var fields: Vector4 = sample_world_fields(x, z)
	var provisional_height: int = carpathian_provisional_height_at(x, z)
	var stage4_height: int = _carpathian_stage4_height(fields, provisional_height)
	var stage5_height: int = _carpathian_stage5_height(fields, stage4_height, x, z)
	var feature: Dictionary = stage6_feature_for_point(x, z)
	if not feature.is_empty():
		stage5_height = stage6_shape_height_for_feature(stage5_height, x, z, feature)
	return finalize_height(stage5_height)


func water_info_at(x: int, z: int) -> Vector2i:
	if not carpathian_enabled():
		return super.water_info_at(x, z)
	var fields: Vector4 = sample_world_fields(x, z)
	var provisional_height: int = carpathian_provisional_height_at(x, z)
	var stage4_height: int = _carpathian_stage4_height(fields, provisional_height)
	if fields.x <= STAGE4_OCEAN_WATER_START:
		var ocean_height: int = finalize_height(stage4_height)
		if water_type_from_fields(fields, ocean_height) == WATER_OCEAN:
			return Vector2i(WATER_OCEAN, SEA_LEVEL)
		return Vector2i(WATER_NONE, -1)

	var river_value: float = stage5_river_signal(x, z)
	var strengths: Vector2 = stage5_river_strengths_from_signal(fields.x, river_value)
	var stage5_height: int = finalize_height(stage5_shape_height_from_signal(fields.x, stage4_height, river_value))
	if strengths.x >= STAGE5_CHANNEL_WATER_CUTOFF:
		return Vector2i(WATER_RIVER, stage5_height + 1)

	var feature: Dictionary = stage6_feature_for_point(x, z)
	if feature.is_empty():
		return Vector2i(WATER_NONE, -1)
	var water_radius: float = float(feature["water_radius"])
	if stage6_feature_distance_squared(x, z, feature) > water_radius * water_radius:
		return Vector2i(WATER_NONE, -1)
	var final_height: int = stage6_shape_height_for_feature(stage5_height, x, z, feature)
	var water_level: int = int(feature["water_level"])
	if final_height >= water_level:
		return Vector2i(WATER_NONE, -1)
	return Vector2i(int(feature["type"]), water_level)


func water_type_at(x: int, z: int) -> int:
	return water_info_at(x, z).x


func water_surface_height_at(x: int, z: int) -> int:
	return water_info_at(x, z).y


func _carpathian_jittered_tree_origin(x: int, z: int, spacing: int, salt: int) -> bool:
	var cell_x: int = floori(float(x) / float(spacing))
	var cell_z: int = floori(float(z) / float(spacing))
	var jitter_x: int = posmod(_stage8_hash(cell_x, cell_z, CARPATHIAN_TREE_JITTER_X_SALT ^ salt), spacing)
	var jitter_z: int = posmod(_stage8_hash(cell_x, cell_z, CARPATHIAN_TREE_JITTER_Z_SALT ^ salt), spacing)
	return x == cell_x * spacing + jitter_x and z == cell_z * spacing + jitter_z


func stage8_tree_candidate_for_biome(x: int, z: int, surface: int, biome: int) -> bool:
	if not carpathian_enabled():
		return super.stage8_tree_candidate_for_biome(x, z, surface, biome)
	if biome == BIOME_DESERT or biome == BIOME_ROCKY:
		return false
	var trunk_height: int = stage8_tree_trunk_height(biome)
	if surface <= SEA_LEVEL + 1 or surface + trunk_height + 2 >= OVERHAUL_WORLD_HEIGHT:
		return false

	var spacing: int = TREE_SPACING
	var biome_salt: int = biome * 0x1f123bb5
	var accept_mod: int = 4
	var accept_limit: int = 3
	match biome:
		BIOME_FOREST:
			spacing = FOREST_TREE_SPACING
			accept_mod = 6
			accept_limit = 5
		BIOME_DENSE_FOREST:
			spacing = STAGE8_DENSE_TREE_SPACING
			accept_mod = 5
			accept_limit = 4
		BIOME_DRY_GRASSLAND:
			if stage8_dry_surface_is_sand(x, z):
				return false
			spacing = STAGE8_DRY_TREE_SPACING
			accept_mod = 2
			accept_limit = 1
		BIOME_COLD_FOREST:
			if stage8_cold_surface_is_stone(x, z):
				return false
			spacing = STAGE8_COLD_TREE_SPACING
			accept_mod = 4
			accept_limit = 3
		BIOME_PLAINS:
			pass
		_:
			return false
	if not _carpathian_jittered_tree_origin(x, z, spacing, biome_salt):
		return false
	var accept_hash: int = absi(_stage8_hash(x, z, CARPATHIAN_TREE_ACCEPT_SALT ^ biome_salt))
	return posmod(accept_hash, accept_mod) < accept_limit


func stage9_surface_exposes_stone(x: int, z: int, height: int, modifier: int, slope: float) -> bool:
	if not carpathian_enabled():
		return super.stage9_surface_exposes_stone(x, z, height, modifier, slope)
	if slope < 2.0:
		return false
	return super.stage9_surface_exposes_stone(x, z, height, modifier, slope)


func get_block(cell: Vector3i) -> int:
	if cell.y < 0:
		return BLOCK_STONE
	if cell.y >= OVERHAUL_WORLD_HEIGHT:
		return BLOCK_AIR
	var key: String = cell_key(cell)
	if overrides.has(key):
		return int(overrides[key])

	# Water is an explicit voxel state. It is derived once from the world's
	# generated fluid source, then participates in normal block override/edit
	# semantics. The renderer consumes this get_block() result and never asks
	# water_info_at() directly.
	var height: int = terrain_height(cell.x, cell.z)
	var water_info: Vector2i = water_info_at(cell.x, cell.z)
	if water_info.x != WATER_NONE and cell.y > height and cell.y <= water_info.y:
		return BLOCK_WATER

	if not carpathian_enabled():
		return super.get_block(cell)

	var fields: Vector4 = sample_world_fields(cell.x, cell.z)
	var climate: Vector2 = sample_biome_climate(cell.x, cell.z)
	var biome: int = stage8_classify_climate(climate, water_info.x)
	if cell.y <= height:
		if cell.y < height - 2:
			return stage8_surface_block(cell, height, biome)
		var terrain_modifier: int = stage9_terrain_modifier_from_fields(fields.x, fields.y, water_info.x)
		var slope: float = stage7_surface_slope_at(cell.x, cell.z, height)
		var transition_code: int = stage10_transition_code_for_climate(climate, water_info.x)
		var hydrology_modifier: int = stage11_hydrology_modifier_at(cell.x, cell.z)
		return stage11_surface_block(cell, height, biome, transition_code, terrain_modifier, slope, hydrology_modifier)
	return generated_tree_block(cell)
