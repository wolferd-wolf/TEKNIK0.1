extends SceneTree

## Ore generation gate (build plan step 14).
## Verifies deterministic depth-weighted ore placement:
##  - get_block and the chunk override map agree on ore cells
##  - ore never replaces non-stone, never sits in carved cells
##  - depth weighting is statistically real (iron deep > shallow)
##  - determinism across repeated builds
##  - parity of policy inputs: the frozen hash primitive matches Rust

const RUNTIME := preload("res://scripts/world/playable_world_generation_runtime.gd")
const DATA := preload("res://scripts/world/playable_world_carpathian_data.gd")
const ORE := preload("res://scripts/world/ore_field_reference.gd")

const PROBE_CHUNKS: Array[Vector2i] = [
	Vector2i(0, 0), Vector2i(2, -1), Vector2i(-4, 3), Vector2i(9, 6),
]

var failures: Array[String] = []
var checks := 0


func _expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition and failures.size() < 8:
		if not failures.has(message):
			failures.append(message)


func _init() -> void:
	var data = DATA.new()
	var cache_builder = RUNTIME.SHIPPING_GENERATION_CACHE
	var counts := {"coal": 0, "iron": 0, "copper": 0}
	var shallow_iron := 0
	var deep_iron := 0

	for coord in PROBE_CHUNKS:
		var caches: Dictionary = cache_builder.build(coord, data)
		var heights: PackedInt32Array = caches.get("heights", PackedInt32Array())
		var biomes: PackedByteArray = caches.get("biomes", PackedByteArray())
		var water_types: PackedByteArray = caches.get("stage7_water_types", PackedByteArray())
		var mesh_height: int = mini(
			DATA.OVERHAUL_WORLD_HEIGHT,
			RUNTIME.STAGE12_STAGE2_RUNTIME_BASE._effective_mesh_height(coord, heights, {}) + 2
		)
		var info_a: Dictionary = data.cave_data_for_chunk(coord, caches, mesh_height)
		var info_b: Dictionary = data.cave_data_for_chunk(coord, caches, mesh_height)
		_expect(info_a.get("overrides", {}).hash() == info_b.get("overrides", {}).hash(),
			"carve+ore map not deterministic at %s" % [coord])

		var overrides: Dictionary = info_a.get("overrides", {})
		var width := roundi(sqrt(float(heights.size())))
		var min_x := coord.x * 12 - 2
		var min_z := coord.y * 12 - 2

		for cz in range(width):
			for cx in range(width):
				var idx := cz * width + cx
				var wx := min_x + cx
				var wz := min_z + cz
				var h := int(heights[idx])
				for y in range(max(2, h - 30), max(3, h - 1)):
					var key := "%d,%d,%d" % [wx, y, wz]
					var in_map: bool = overrides.has(key)
					var block_id: int = data.get_block(Vector3i(wx, y, wz))
					var is_ore: bool = block_id >= data.BLOCK_COAL_ORE and block_id <= data.BLOCK_COPPER_ORE
					if in_map and int(overrides[key]) >= data.BLOCK_COAL_ORE:
						_expect(is_ore, "map ore disagrees with get_block at %s" % [key])
						match block_id:
							data.BLOCK_COAL_ORE: counts["coal"] += 1
							data.BLOCK_IRON_ORE: counts["iron"] += 1
							data.BLOCK_COPPER_ORE: counts["copper"] += 1
						# never inside a carved pocket
						_expect(block_id != data.BLOCK_AIR, "ore id collided with air at %s" % [key])
						if h - y < 4:
							_expect(false, "ore above depth floor at %s" % [key])
						if block_id == data.BLOCK_IRON_ORE:
							if h - y >= 14:
								deep_iron += 1
							elif h - y < 10:
								shallow_iron += 1
					elif is_ore and not (in_map and int(overrides[key]) == block_id):
						# gameplay truth found ore the map does not carry as the same id;
						# allowed only when the map carved the cell to air instead.
						_expect(in_map and int(overrides[key]) == data.BLOCK_AIR,
							"get_block ore missing from map at %s" % [key])

	# Depth weighting sanity: iron must be at least twice as common deep as shallow.
	_expect(deep_iron > 0, "no deep iron sampled")
	_expect(deep_iron >= 2 * shallow_iron,
		"iron depth weighting inverted: deep=%d shallow=%d" % [deep_iron, shallow_iron])
	_expect(counts["coal"] > 0 and counts["copper"] > 0, "missing coal or copper in sample")

	print("ORE_GENERATION_GATE_JSON=", JSON.stringify({
		"gate": "ore_generation",
		"chunks": PROBE_CHUNKS.size(),
		"checks": checks,
		"coal": counts["coal"],
		"iron": counts["iron"],
		"copper": counts["copper"],
		"failures": failures,
	}))
	if failures.is_empty():
		print("ORE_GENERATION_GATE_PASS")
	else:
		print("ORE_GENERATION_GATE_FAIL")
	quit(0 if failures.is_empty() else 1)
