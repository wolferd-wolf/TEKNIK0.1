extends RefCounted

const BLOCK_AIR := 0
const BLOCK_GRASS := 1
const BLOCK_DIRT := 2
const BLOCK_STONE := 3
const BLOCK_SAND := 4
const WORLD_HEIGHT := 30
const SEA_LEVEL := 7
const WORLD_SEED := 734921
const SAVE_PATH := "user://teknik_world_v1.json"

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
	if cell.y > height:
		return BLOCK_AIR
	if cell.y == height:
		return BLOCK_SAND if height <= SEA_LEVEL + 1 else BLOCK_GRASS
	if cell.y >= height - 3:
		return BLOCK_SAND if height <= SEA_LEVEL + 1 else BLOCK_DIRT
	return BLOCK_STONE


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
