extends RefCounted

const BLOCK_AIR := 0
const BLOCK_GRASS := 1
const BLOCK_DIRT := 2
const BLOCK_STONE := 3
const BLOCK_SAND := 4
const BLOCK_LOG := 5
const BLOCK_LEAVES := 6
const WORLD_HEIGHT := 40
const SEA_LEVEL := 7
const WORLD_SEED := 734921
const TREE_SPACING := 7
const TREE_OFFSET := 3
const FOREST_TREE_SPACING := 5
const FOREST_TREE_OFFSET := 1
const TREE_TRUNK_HEIGHT := 4
const TREE_CANOPY_RADIUS := 1
const NOISE_SAMPLES_PER_COLUMN := 4
const DOMAIN_WARPED_LAYER_COUNT := 4
const DOMAIN_WARP_AMPLITUDE := 36.0
const DOMAIN_WARP_FREQUENCY := 0.004
const DOMAIN_WARP_FRACTAL_OCTAVES := 2
const DOMAIN_WARP_FRACTAL_GAIN := 0.5
const DOMAIN_WARP_FRACTAL_LACUNARITY := 2.0
const TERRAIN_BASE_HEIGHT := 10.0
const CONTINENTALNESS_HEIGHT_SCALE := 6.4
const TERRAIN_SHAPE_HEIGHT_SCALE := 3.0
const ROCKY_MOUNTAIN_BASE_RISE := 4.0
const ROCKY_MOUNTAIN_RUGGEDNESS := 11.0
const ROCKY_MOUNTAIN_LAND_BLEND_START := 6.0
const ROCKY_MOUNTAIN_LAND_BLEND_END := 9.0

const BIOME_PLAINS := 0
const BIOME_FOREST := 1
const BIOME_DESERT := 2
const BIOME_ROCKY := 3
const BIOME_COUNT := 4
const BIOME_HOT_THRESHOLD := 0.12
const BIOME_COLD_THRESHOLD := -0.12
const BIOME_DRY_THRESHOLD := -0.08
const BIOME_WET_THRESHOLD := 0.10
const BIOME_BLEND_WIDTH := 0.10
const BIOME_BLEND_PATCH_SIZE := 3

var overrides: Dictionary = {}
var dirty := false
var save_delay := 0.0

var continentalness_noise := FastNoiseLite.new()
var terrain_shape_noise := FastNoiseLite.new()
var temperature_noise := FastNoiseLite.new()
var moisture_noise := FastNoiseLite.new()

# Compatibility aliases for existing diagnostics that still refer to the
# pre-Stage-1 names.
var height_noise: FastNoiseLite
var region_noise: FastNoiseLite


func _init() -> void:
	continentalness_noise.seed = WORLD_SEED
	continentalness_noise.frequency = 0.011
	continentalness_noise.fractal_octaves = 4
	continentalness_noise.fractal_gain = 0.48
	continentalness_noise.fractal_lacunarity = 2.05
	_configure_domain_warp(continentalness_noise)

	terrain_shape_noise.seed = WORLD_SEED ^ 0x5f3759df
	terrain_shape_noise.frequency = 0.0035
	terrain_shape_noise.fractal_octaves = 2
	_configure_domain_warp(terrain_shape_noise)

	temperature_noise.seed = WORLD_SEED ^ 0x68bc21eb
	temperature_noise.frequency = 0.0024
	temperature_noise.fractal_octaves = 3
	temperature_noise.fractal_gain = 0.5
	temperature_noise.fractal_lacunarity = 2.0
	_configure_domain_warp(temperature_noise)

	moisture_noise.seed = WORLD_SEED ^ 0x02e5be93
	moisture_noise.frequency = 0.0028
	moisture_noise.fractal_octaves = 3
	moisture_noise.fractal_gain = 0.5
	moisture_noise.fractal_lacunarity = 2.0
	_configure_domain_warp(moisture_noise)

	height_noise = continentalness_noise
	region_noise = terrain_shape_noise
	load_save()


func _configure_domain_warp(noise: FastNoiseLite) -> void:
	noise.domain_warp_enabled = true
	noise.domain_warp_type = FastNoiseLite.DOMAIN_WARP_SIMPLEX_REDUCED
	noise.domain_warp_amplitude = DOMAIN_WARP_AMPLITUDE
	noise.domain_warp_frequency = DOMAIN_WARP_FREQUENCY
	noise.domain_warp_fractal_type = FastNoiseLite.DOMAIN_WARP_FRACTAL_PROGRESSIVE
	noise.domain_warp_fractal_octaves = DOMAIN_WARP_FRACTAL_OCTAVES
	noise.domain_warp_fractal_gain = DOMAIN_WARP_FRACTAL_GAIN
	noise.domain_warp_fractal_lacunarity = DOMAIN_WARP_FRACTAL_LACUNARITY


func sample_column_noise(x: int, z: int) -> Vector4:
	var world_x := float(x)
	var world_z := float(z)
	return Vector4(
		continentalness_noise.get_noise_2d(world_x, world_z),
		terrain_shape_noise.get_noise_2d(world_x, world_z),
		temperature_noise.get_noise_2d(world_x, world_z),
		moisture_noise.get_noise_2d(world_x, world_z)
	)


func rocky_mountain_weight_from_climate(temperature: float, moisture: float) -> float:
	var cold := 1.0 - _smooth_range(
		BIOME_COLD_THRESHOLD - BIOME_BLEND_WIDTH,
		BIOME_COLD_THRESHOLD + BIOME_BLEND_WIDTH,
		temperature
	)
	var wet := _smooth_range(
		BIOME_WET_THRESHOLD - BIOME_BLEND_WIDTH,
		BIOME_WET_THRESHOLD + BIOME_BLEND_WIDTH,
		moisture
	)
	return cold * (1.0 - wet)


func terrain_height_from_samples(samples: Vector4) -> int:
	var base_height := (
		TERRAIN_BASE_HEIGHT
		+ samples.x * CONTINENTALNESS_HEIGHT_SCALE
		+ samples.y * TERRAIN_SHAPE_HEIGHT_SCALE
	)
	var rocky_weight := rocky_mountain_weight_from_climate(samples.z, samples.w)
	var land_factor := _smooth_range(
		ROCKY_MOUNTAIN_LAND_BLEND_START,
		ROCKY_MOUNTAIN_LAND_BLEND_END,
		base_height
	)
	var peak_strength := clampf((samples.y + 1.0) * 0.5, 0.0, 1.0)
	peak_strength *= peak_strength
	var mountain_rise := rocky_weight * land_factor * (
		ROCKY_MOUNTAIN_BASE_RISE + peak_strength * ROCKY_MOUNTAIN_RUGGEDNESS
	)
	return clampi(roundi(base_height + mountain_rise), 3, WORLD_HEIGHT - 3)


func terrain_height(x: int, z: int) -> int:
	return terrain_height_from_samples(sample_column_noise(x, z))


func select_biome_from_climate(temperature: float, moisture: float) -> int:
	if temperature >= BIOME_HOT_THRESHOLD and moisture <= BIOME_DRY_THRESHOLD:
		return BIOME_DESERT
	if moisture >= BIOME_WET_THRESHOLD:
		return BIOME_FOREST
	if temperature <= BIOME_COLD_THRESHOLD:
		return BIOME_ROCKY
	return BIOME_PLAINS


func select_biome_from_samples(samples: Vector4) -> int:
	return select_biome_from_climate(samples.z, samples.w)


func biome_weights_from_climate(temperature: float, moisture: float) -> Vector4:
	var hot := _smooth_range(
		BIOME_HOT_THRESHOLD - BIOME_BLEND_WIDTH,
		BIOME_HOT_THRESHOLD + BIOME_BLEND_WIDTH,
		temperature
	)
	var cold := 1.0 - _smooth_range(
		BIOME_COLD_THRESHOLD - BIOME_BLEND_WIDTH,
		BIOME_COLD_THRESHOLD + BIOME_BLEND_WIDTH,
		temperature
	)
	var dry := 1.0 - _smooth_range(
		BIOME_DRY_THRESHOLD - BIOME_BLEND_WIDTH,
		BIOME_DRY_THRESHOLD + BIOME_BLEND_WIDTH,
		moisture
	)
	var wet := _smooth_range(
		BIOME_WET_THRESHOLD - BIOME_BLEND_WIDTH,
		BIOME_WET_THRESHOLD + BIOME_BLEND_WIDTH,
		moisture
	)

	var desert := hot * dry
	var forest := wet * (1.0 - desert)
	var rocky := cold * (1.0 - wet) * (1.0 - desert)
	var plains := maxf(0.0, 1.0 - maxf(desert, maxf(forest, rocky)))
	var total := plains + forest + desert + rocky
	if total <= 0.000001:
		return Vector4(1.0, 0.0, 0.0, 0.0)
	return Vector4(plains, forest, desert, rocky) / total


func biome_weights_from_samples(samples: Vector4) -> Vector4:
	return biome_weights_from_climate(samples.z, samples.w)


func blended_biome_from_weights(weights: Vector4, x: int, z: int) -> int:
	var patch_x := floori(float(x) / float(BIOME_BLEND_PATCH_SIZE))
	var patch_z := floori(float(z) / float(BIOME_BLEND_PATCH_SIZE))
	var selector := _blend_selector(patch_x, patch_z)
	var cumulative := weights.x
	if selector < cumulative:
		return BIOME_PLAINS
	cumulative += weights.y
	if selector < cumulative:
		return BIOME_FOREST
	cumulative += weights.z
	if selector < cumulative:
		return BIOME_DESERT
	return BIOME_ROCKY


func blended_biome_from_samples(samples: Vector4, x: int, z: int) -> int:
	return blended_biome_from_weights(biome_weights_from_samples(samples), x, z)


func biome_at(x: int, z: int) -> int:
	var samples := sample_column_noise(x, z)
	return blended_biome_from_samples(samples, x, z)


func biome_name(biome: int) -> String:
	match biome:
		BIOME_PLAINS:
			return "plains"
		BIOME_FOREST:
			return "forest"
		BIOME_DESERT:
			return "desert"
		BIOME_ROCKY:
			return "rocky"
		_:
			return "unknown"


func terrain_block(y: int, height: int, biome: int) -> int:
	if y == height:
		if height <= SEA_LEVEL + 1 or biome == BIOME_DESERT:
			return BLOCK_SAND
		if biome == BIOME_ROCKY:
			return BLOCK_STONE
		return BLOCK_GRASS
	if y >= height - 3:
		if height <= SEA_LEVEL + 1 or biome == BIOME_DESERT:
			return BLOCK_SAND
		if biome == BIOME_ROCKY:
			return BLOCK_STONE
		return BLOCK_DIRT
	return BLOCK_STONE


func get_block(cell: Vector3i) -> int:
	if cell.y < 0:
		return BLOCK_STONE
	if cell.y >= WORLD_HEIGHT:
		return BLOCK_AIR
	var key := cell_key(cell)
	if overrides.has(key):
		return int(overrides[key])
	var samples := sample_column_noise(cell.x, cell.z)
	var height := terrain_height_from_samples(samples)
	var biome := blended_biome_from_samples(samples, cell.x, cell.z)
	if cell.y <= height:
		return terrain_block(cell.y, height, biome)
	return generated_tree_block(cell)


func generated_tree_block(cell: Vector3i) -> int:
	for tree_z in range(cell.z - TREE_CANOPY_RADIUS, cell.z + TREE_CANOPY_RADIUS + 1):
		for tree_x in range(cell.x - TREE_CANOPY_RADIUS, cell.x + TREE_CANOPY_RADIUS + 1):
			if not is_tree_origin(tree_x, tree_z):
				continue
			var surface := terrain_height(tree_x, tree_z)
			var trunk_top := surface + TREE_TRUNK_HEIGHT
			if cell.x == tree_x and cell.z == tree_z and cell.y > surface and cell.y <= trunk_top:
				return BLOCK_LOG
			if (
				cell.y >= trunk_top - 1
				and cell.y <= trunk_top + 1
				and absi(cell.x - tree_x) <= TREE_CANOPY_RADIUS
				and absi(cell.z - tree_z) <= TREE_CANOPY_RADIUS
			):
				return BLOCK_LEAVES
	return BLOCK_AIR


func is_tree_origin(x: int, z: int) -> bool:
	var samples := sample_column_noise(x, z)
	var surface := terrain_height_from_samples(samples)
	var biome := blended_biome_from_samples(samples, x, z)
	return is_tree_origin_for_biome(x, z, surface, biome)


func is_tree_origin_for_biome(x: int, z: int, surface: int, biome: int) -> bool:
	if biome == BIOME_DESERT or biome == BIOME_ROCKY:
		return false
	if surface <= SEA_LEVEL + 1 or surface + TREE_TRUNK_HEIGHT + 1 >= WORLD_HEIGHT:
		return false
	var baseline_grid := (
		posmod(x, TREE_SPACING) == TREE_OFFSET
		and posmod(z, TREE_SPACING) == TREE_OFFSET
	)
	var forest_grid := (
		biome == BIOME_FOREST
		and posmod(x, FOREST_TREE_SPACING) == FOREST_TREE_OFFSET
		and posmod(z, FOREST_TREE_SPACING) == FOREST_TREE_OFFSET
	)
	if not baseline_grid and not forest_grid:
		return false
	var hash_value := absi((x * 73856093) ^ (z * 19349663) ^ WORLD_SEED)
	if forest_grid and not baseline_grid:
		return hash_value % 3 != 0
	return hash_value % 4 != 0


func _smooth_range(edge_start: float, edge_end: float, value: float) -> float:
	var t := clampf((value - edge_start) / (edge_end - edge_start), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


func _blend_selector(patch_x: int, patch_z: int) -> float:
	var hash_value := (patch_x * 73856093) ^ (patch_z * 19349663) ^ (WORLD_SEED * 83492791)
	hash_value = absi(hash_value)
	return float(hash_value % 1000003) / 1000003.0


func set_block(cell: Vector3i, block_id: int) -> bool:
	if cell.y < 0 or cell.y >= WORLD_HEIGHT or get_block(cell) == block_id:
		return false
	overrides[cell_key(cell)] = block_id
	dirty = true
	save_delay = 1.5
	return true


func tick_save(delta: float) -> void:
	if not dirty:
		return
	save_delay -= delta
	if save_delay <= 0.0:
		save_world()


func save_world() -> void:
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_warning("Unable to save imported TEKNIK world edits")
		return
	file.store_string(JSON.stringify({
		"version": 1,
		"seed": WORLD_SEED,
		"overrides": overrides,
	}))
	dirty = false


func load_save() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if parsed is Dictionary and parsed.get("overrides") is Dictionary:
		overrides = parsed["overrides"].duplicate(true)


func cell_key(cell: Vector3i) -> String:
	return "%d,%d,%d" % [cell.x, cell.y, cell.z]
