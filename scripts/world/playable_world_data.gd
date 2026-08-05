extends RefCounted

const BLOCK_AIR := 0
const BLOCK_GRASS := 1
const BLOCK_DIRT := 2
const BLOCK_STONE := 3
const BLOCK_SAND := 4
const BLOCK_LOG := 5
const BLOCK_LEAVES := 6
const WORLD_HEIGHT := 30
const SEA_LEVEL := 7
const WORLD_SEED := 734921
const SAVE_PATH := "user://teknik_world_v1.json"
const TREE_SPACING := 7
const TREE_OFFSET := 3
const TREE_TRUNK_HEIGHT := 4
const TREE_CANOPY_RADIUS := 1

var overrides: Dictionary = {}
var dirty := false
var save_delay := 0.0
var height_noise := FastNoiseLite.new()
var region_noise := FastNoiseLite.new()


func _init() -> void:
	height_noise.seed = WORLD_SEED
	height_noise.frequency = 0.011
	height_noise.fractal_octaves = 4
	height_noise.fractal_gain = 0.48
	height_noise.fractal_lacunarity = 2.05
	region_noise.seed = WORLD_SEED ^ 0x5f3759df
	region_noise.frequency = 0.0035
	region_noise.fractal_octaves = 2
	load_save()


func terrain_height(x: int, z: int) -> int:
	var continental := height_noise.get_noise_2d(float(x), float(z))
	var region := region_noise.get_noise_2d(float(x), float(z))
	return clampi(roundi(10.0 + continental * 6.4 + region * 3.0), 3, WORLD_HEIGHT - 3)


func get_block(cell: Vector3i) -> int:
	if cell.y < 0:
		return BLOCK_STONE
	if cell.y >= WORLD_HEIGHT:
		return BLOCK_AIR
	var key := cell_key(cell)
	if overrides.has(key):
		return int(overrides[key])
	var height := terrain_height(cell.x, cell.z)
	if cell.y <= height:
		if cell.y == height:
			return BLOCK_SAND if height <= SEA_LEVEL + 1 else BLOCK_GRASS
		if cell.y >= height - 3:
			return BLOCK_SAND if height <= SEA_LEVEL + 1 else BLOCK_DIRT
		return BLOCK_STONE
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
	if posmod(x, TREE_SPACING) != TREE_OFFSET or posmod(z, TREE_SPACING) != TREE_OFFSET:
		return false
	var surface := terrain_height(x, z)
	if surface <= SEA_LEVEL + 1 or surface + TREE_TRUNK_HEIGHT + 1 >= WORLD_HEIGHT:
		return false
	var hash_value := absi((x * 73856093) ^ (z * 19349663) ^ WORLD_SEED)
	return hash_value % 4 != 0


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
