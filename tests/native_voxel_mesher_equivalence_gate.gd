extends SceneTree

const SHIPPING_RUNTIME := preload("res://scripts/world/playable_world_generation_runtime.gd")
const BASE_MESHER := preload("res://scripts/world/playable_world_mesher.gd")
const SHIPPING_DATA := preload("res://scripts/world/playable_world_carpathian_data.gd")
const STAGE2_RUNTIME := preload("res://scripts/world/playable_world_stage2_generation_runtime.gd")

const NATIVE_CLASS := &"TeknikVoxelMesher"
const CHUNK_SIZE := 12
const PADDING := 2
const COLOR_TOLERANCE := 0.000002
const COORDS: Array[Vector2i] = [
	Vector2i(0, 0),
	Vector2i(1, -1),
	Vector2i(-2, 1),
	Vector2i(2, -2),
	Vector2i(-2, 7),
	Vector2i(-1, -2),
]

var failures: Array[String] = []
var exact_geometry_cases := 0
var color_samples := 0
var max_color_error := 0.0
var gdscript_usec: Array[int] = []
var native_usec: Array[int] = []


func _fail(message: String) -> void:
	if not failures.has(message):
		failures.append(message)


func _cache_width(heights: PackedInt32Array) -> int:
	var width: int = roundi(sqrt(float(heights.size())))
	if width * width != heights.size():
		return CHUNK_SIZE + PADDING * 2
	return width


func _column_height(heights: PackedInt32Array, local_x: int, local_z: int) -> int:
	var width := _cache_width(heights)
	return int(heights[(local_z + PADDING) * width + local_x + PADDING])


func _key(x: int, y: int, z: int) -> String:
	return "%d,%d,%d" % [x, y, z]


func _synthetic_overrides(coord: Vector2i, heights: PackedInt32Array, variant: int) -> Dictionary:
	if variant == 0:
		return {}
	var origin_x := coord.x * CHUNK_SIZE
	var origin_z := coord.y * CHUNK_SIZE
	var result: Dictionary = {}
	var h_a := _column_height(heights, 4, 4)
	var h_b := _column_height(heights, 7, 6)
	# Mining-style surface deletion.
	result[_key(origin_x + 4, h_a, origin_z + 4)] = BASE_MESHER.BLOCK_AIR
	# Placement-style solid block above the current surface.
	result[_key(origin_x + 7, h_b + 1, origin_z + 6)] = BASE_MESHER.BLOCK_STONE
	if variant >= 2:
		# Explicit decoration overrides exercise log/leaves and dictionary parsing.
		result[_key(origin_x + 8, h_b + 2, origin_z + 6)] = BASE_MESHER.BLOCK_LOG
		result[_key(origin_x + 9, h_b + 2, origin_z + 6)] = BASE_MESHER.BLOCK_LEAVES
	return result


func _max_color_component_error(a: Color, b: Color) -> float:
	return maxf(
		maxf(absf(a.r - b.r), absf(a.g - b.g)),
		maxf(absf(a.b - b.b), absf(a.a - b.a))
	)


func _compare_case(label: String, old_mesh: Dictionary, new_mesh: Dictionary) -> void:
	if int(old_mesh.get("face_count", -1)) != int(new_mesh.get("face_count", -2)):
		_fail("%s face_count differs: gd=%d native=%d" % [
			label,
			int(old_mesh.get("face_count", -1)),
			int(new_mesh.get("face_count", -2)),
		])
		return
	var old_vertices: PackedVector3Array = old_mesh.get("vertices", PackedVector3Array())
	var new_vertices: PackedVector3Array = new_mesh.get("vertices", PackedVector3Array())
	var old_normals: PackedVector3Array = old_mesh.get("normals", PackedVector3Array())
	var new_normals: PackedVector3Array = new_mesh.get("normals", PackedVector3Array())
	var old_indices: PackedInt32Array = old_mesh.get("indices", PackedInt32Array())
	var new_indices: PackedInt32Array = new_mesh.get("indices", PackedInt32Array())
	if old_vertices != new_vertices:
		_fail("%s vertices differ" % label)
		return
	if old_normals != new_normals:
		_fail("%s normals differ" % label)
		return
	if old_indices != new_indices:
		_fail("%s indices differ" % label)
		return
	var old_colors: PackedColorArray = old_mesh.get("colors", PackedColorArray())
	var new_colors: PackedColorArray = new_mesh.get("colors", PackedColorArray())
	if old_colors.size() != new_colors.size():
		_fail("%s color array size differs" % label)
		return
	for i in range(old_colors.size()):
		var error := _max_color_component_error(old_colors[i], new_colors[i])
		max_color_error = maxf(max_color_error, error)
		color_samples += 1
		if error > COLOR_TOLERANCE:
			_fail("%s color[%d] differs by %.9f" % [label, i, error])
			return
	exact_geometry_cases += 1


func _mean(values: Array[int]) -> float:
	var total := 0
	for value in values:
		total += value
	return float(total) / maxf(float(values.size()), 1.0)


func _p95(values: Array[int]) -> int:
	var sorted_values := values.duplicate()
	sorted_values.sort()
	if sorted_values.is_empty():
		return 0
	var index := clampi(ceili(float(sorted_values.size()) * 0.95) - 1, 0, sorted_values.size() - 1)
	return int(sorted_values[index])


func _init() -> void:
	if not ClassDB.class_exists(NATIVE_CLASS):
		_fail("TeknikVoxelMesher native class is not loaded")
	else:
		var native_mesher: Object = ClassDB.instantiate(NATIVE_CLASS)
		if native_mesher == null:
			_fail("TeknikVoxelMesher could not be instantiated")
		else:
			var runtime = SHIPPING_RUNTIME.new()
			for coord in COORDS:
				var cache: Dictionary = runtime._build_column_caches(coord)
				var heights: PackedInt32Array = cache.get("heights", PackedInt32Array())
				var biomes: PackedByteArray = cache.get("biomes", PackedByteArray())
				for variant in range(3):
					var overrides := _synthetic_overrides(coord, heights, variant)
					var mesh_height := mini(
						SHIPPING_DATA.OVERHAUL_WORLD_HEIGHT,
						STAGE2_RUNTIME._effective_mesh_height(coord, heights, overrides) + 2
					)
					var started := Time.get_ticks_usec()
					var gd_mesh: Dictionary = BASE_MESHER.build(
						coord,
						heights,
						overrides,
						CHUNK_SIZE,
						mesh_height,
						SHIPPING_DATA.SEA_LEVEL,
						biomes
					)
					gdscript_usec.append(Time.get_ticks_usec() - started)
					started = Time.get_ticks_usec()
					var native_variant: Variant = native_mesher.call(
						"build",
						coord,
						heights,
						overrides,
						CHUNK_SIZE,
						mesh_height,
						SHIPPING_DATA.SEA_LEVEL,
						biomes
					)
					native_usec.append(Time.get_ticks_usec() - started)
					if not native_variant is Dictionary:
						_fail("Native mesher returned non-Dictionary for %s variant=%d" % [coord, variant])
						continue
					_compare_case("coord=%s variant=%d" % [coord, variant], gd_mesh, native_variant as Dictionary)
			runtime.free()

	var report := {
		"cases": COORDS.size() * 3,
		"exact_geometry_cases": exact_geometry_cases,
		"color_samples": color_samples,
		"max_color_error": max_color_error,
		"color_tolerance": COLOR_TOLERANCE,
		"gdscript_mean_ms": _mean(gdscript_usec) / 1000.0,
		"gdscript_p95_ms": float(_p95(gdscript_usec)) / 1000.0,
		"native_mean_ms": _mean(native_usec) / 1000.0,
		"native_p95_ms": float(_p95(native_usec)) / 1000.0,
		"p95_speedup": float(_p95(gdscript_usec)) / maxf(float(_p95(native_usec)), 1.0),
		"failures": failures,
	}
	print("NATIVE_VOXEL_MESHER_EQUIVALENCE_JSON=%s" % JSON.stringify(report))
	if failures.is_empty() and exact_geometry_cases == COORDS.size() * 3:
		print("NATIVE_VOXEL_MESHER_EQUIVALENCE_PASS")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)
