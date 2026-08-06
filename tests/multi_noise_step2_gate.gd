extends SceneTree

const WORLD_DATA := preload("res://scripts/world/playable_world_data.gd")
const CHUNK_SIZE := 12
const CACHE_PADDING := 2
const CACHE_WIDTH := CHUNK_SIZE + CACHE_PADDING * 2
const WARMUP_REPETITIONS := 4
const MEASURED_REPETITIONS := 20
const GRID_MIN := -256
const GRID_MAX := 256
const GRID_STEP := 4
const GRID_SIZE := 129
const DIAGNOSTIC_PANEL_SIZE := 256
const DIAGNOSTIC_WIDTH := DIAGNOSTIC_PANEL_SIZE * 2
const DIAGNOSTIC_HEIGHT := DIAGNOSTIC_PANEL_SIZE
const DIAGNOSTIC_WORLD_SCALE := 3.0
const DIAGNOSTIC_PATH := "res://artifacts/multi-noise-step2-domain-warp.png"

var failures: Array[String] = []


class Step1UnwarpedSampler:
	extends RefCounted

	const WORLD_SEED := 734921
	const WORLD_HEIGHT := 30

	var continentalness_noise := FastNoiseLite.new()
	var terrain_shape_noise := FastNoiseLite.new()
	var temperature_noise := FastNoiseLite.new()
	var moisture_noise := FastNoiseLite.new()

	func _init() -> void:
		continentalness_noise.seed = WORLD_SEED
		continentalness_noise.frequency = 0.011
		continentalness_noise.fractal_octaves = 4
		continentalness_noise.fractal_gain = 0.48
		continentalness_noise.fractal_lacunarity = 2.05

		terrain_shape_noise.seed = WORLD_SEED ^ 0x5f3759df
		terrain_shape_noise.frequency = 0.0035
		terrain_shape_noise.fractal_octaves = 2

		temperature_noise.seed = WORLD_SEED ^ 0x68bc21eb
		temperature_noise.frequency = 0.0024
		temperature_noise.fractal_octaves = 3
		temperature_noise.fractal_gain = 0.5
		temperature_noise.fractal_lacunarity = 2.0

		moisture_noise.seed = WORLD_SEED ^ 0x02e5be93
		moisture_noise.frequency = 0.0028
		moisture_noise.fractal_octaves = 3
		moisture_noise.fractal_gain = 0.5
		moisture_noise.fractal_lacunarity = 2.0

	func sample_column_noise(x: int, z: int) -> Vector4:
		var world_x := float(x)
		var world_z := float(z)
		return Vector4(
			continentalness_noise.get_noise_2d(world_x, world_z),
			terrain_shape_noise.get_noise_2d(world_x, world_z),
			temperature_noise.get_noise_2d(world_x, world_z),
			moisture_noise.get_noise_2d(world_x, world_z)
		)

	func terrain_height(x: int, z: int) -> int:
		var samples := sample_column_noise(x, z)
		return clampi(roundi(10.0 + samples.x * 6.4 + samples.y * 3.0), 3, WORLD_HEIGHT - 3)


func _init() -> void:
	var warped = WORLD_DATA.new()
	var unwarped := Step1UnwarpedSampler.new()

	_validate_source_contract()
	_validate_warp_configuration(warped)
	_validate_determinism(warped)
	_validate_world_coordinate_continuity(warped)
	_validate_height_bounds(warped)
	var distortion_metrics := _measure_domain_warp_effect(warped, unwarped)
	_write_diagnostic_image(warped, unwarped)
	var benchmark := _run_benchmark(warped, unwarped)

	if failures.is_empty():
		print("MULTI_NOISE_STEP2_DISTORTION_JSON=%s" % JSON.stringify(distortion_metrics))
		print("MULTI_NOISE_STEP2_BENCHMARK_JSON=%s" % JSON.stringify(benchmark))
		print("MULTI_NOISE_STEP2_DIAGNOSTIC=%s" % ProjectSettings.globalize_path(DIAGNOSTIC_PATH))
		print("MULTI_NOISE_STEP2_GATE_PASS")
		quit(0)
		return

	for failure in failures:
		push_error(failure)
	quit(1)


func _validate_source_contract() -> void:
	if int(WORLD_DATA.NOISE_SAMPLES_PER_COLUMN) != 4:
		_fail("Base noise sample count must remain exactly four")
	if int(WORLD_DATA.DOMAIN_WARPED_LAYER_COUNT) != 4:
		_fail("All four Stage 1 layers must be domain warped")

	var source := FileAccess.get_file_as_string("res://scripts/world/playable_world_data.gd")
	var init_start := source.find("func _init()")
	var configure_start := source.find("func _configure_domain_warp", init_start)
	var sample_start := source.find("func sample_column_noise", configure_start)
	var height_start := source.find("func terrain_height", sample_start)
	var block_start := source.find("func get_block", height_start)
	if init_start < 0 or configure_start < 0 or sample_start < 0 or height_start < 0 or block_start < 0:
		_fail("Unable to isolate Step 2 production functions")
		return

	var init_body := source.substr(init_start, configure_start - init_start)
	var configure_body := source.substr(configure_start, sample_start - configure_start)
	var sample_body := source.substr(sample_start, height_start - sample_start)
	var height_body := source.substr(height_start, block_start - height_start)

	if _count_occurrences(init_body, "_configure_domain_warp(") != 4:
		_fail("Exactly four production noise layers must receive domain-warp configuration")
	if _count_occurrences(configure_body, "domain_warp_enabled = true") != 1:
		_fail("Domain warp must be enabled through the shared production configuration")
	if _count_occurrences(sample_body, ".get_noise_2d(") != 4:
		_fail("Sampling must remain one base API call for each of the four layers")
	if _count_occurrences(height_body, "sample_column_noise(") != 1:
		_fail("terrain_height must sample the four-layer vector exactly once")
	if height_body.contains("samples.z") or height_body.contains("samples.w"):
		_fail("Step 2 must not introduce temperature/moisture biome selection early")
	if source.contains("func get_biome") or source.contains("func select_biome"):
		_fail("Biome selection belongs to Step 3, not Step 2")


func _validate_warp_configuration(data) -> void:
	var layers: Array[FastNoiseLite] = [
		data.continentalness_noise,
		data.terrain_shape_noise,
		data.temperature_noise,
		data.moisture_noise,
	]
	for layer_index in range(layers.size()):
		var layer: FastNoiseLite = layers[layer_index]
		if not layer.domain_warp_enabled:
			_fail("Noise layer %d did not enable domain warp" % layer_index)
		if layer.domain_warp_type != FastNoiseLite.DOMAIN_WARP_SIMPLEX_REDUCED:
			_fail("Noise layer %d used an unexpected warp algorithm" % layer_index)
		if layer.domain_warp_fractal_type != FastNoiseLite.DOMAIN_WARP_FRACTAL_PROGRESSIVE:
			_fail("Noise layer %d did not use progressive fractal warping" % layer_index)
		if not is_equal_approx(layer.domain_warp_amplitude, WORLD_DATA.DOMAIN_WARP_AMPLITUDE):
			_fail("Noise layer %d used the wrong warp amplitude" % layer_index)
		if not is_equal_approx(layer.domain_warp_frequency, WORLD_DATA.DOMAIN_WARP_FREQUENCY):
			_fail("Noise layer %d used the wrong warp frequency" % layer_index)
		if layer.domain_warp_fractal_octaves != WORLD_DATA.DOMAIN_WARP_FRACTAL_OCTAVES:
			_fail("Noise layer %d used the wrong warp octave count" % layer_index)
		if not is_equal_approx(layer.domain_warp_fractal_gain, WORLD_DATA.DOMAIN_WARP_FRACTAL_GAIN):
			_fail("Noise layer %d used the wrong warp gain" % layer_index)
		if not is_equal_approx(layer.domain_warp_fractal_lacunarity, WORLD_DATA.DOMAIN_WARP_FRACTAL_LACUNARITY):
			_fail("Noise layer %d used the wrong warp lacunarity" % layer_index)


func _validate_determinism(data) -> void:
	for z in range(-96, 97, 11):
		for x in range(-96, 97, 7):
			var first_samples: Vector4 = data.sample_column_noise(x, z)
			var second_samples: Vector4 = data.sample_column_noise(x, z)
			if not first_samples.is_equal_approx(second_samples):
				_fail("Warped samples were not deterministic at (%d,%d)" % [x, z])
			var first_height: int = data.terrain_height(x, z)
			var second_height: int = data.terrain_height(x, z)
			if first_height != second_height:
				_fail("Warped height was not deterministic at (%d,%d)" % [x, z])


func _validate_world_coordinate_continuity(data) -> void:
	var origin_samples := _build_sample_cache(data, Vector2i.ZERO)
	var east_samples := _build_sample_cache(data, Vector2i(1, 0))
	var south_samples := _build_sample_cache(data, Vector2i(0, 1))
	var negative_samples := _build_sample_cache(data, Vector2i(-1, -1))

	for local_z in range(CHUNK_SIZE):
		var from_origin: Vector4 = _sample_cache_value(origin_samples, CHUNK_SIZE, local_z)
		var from_east: Vector4 = _sample_cache_value(east_samples, 0, local_z)
		var direct: Vector4 = data.sample_column_noise(CHUNK_SIZE, local_z)
		if not from_origin.is_equal_approx(from_east) or not from_east.is_equal_approx(direct):
			_fail("Warped east boundary restarted or misaligned at z=%d" % local_z)

	for local_x in range(CHUNK_SIZE):
		var from_origin: Vector4 = _sample_cache_value(origin_samples, local_x, CHUNK_SIZE)
		var from_south: Vector4 = _sample_cache_value(south_samples, local_x, 0)
		var direct: Vector4 = data.sample_column_noise(local_x, CHUNK_SIZE)
		if not from_origin.is_equal_approx(from_south) or not from_south.is_equal_approx(direct):
			_fail("Warped south boundary restarted or misaligned at x=%d" % local_x)

	for local_z in range(CHUNK_SIZE):
		var cached: Vector4 = _sample_cache_value(negative_samples, 0, local_z)
		var direct: Vector4 = data.sample_column_noise(-CHUNK_SIZE, -CHUNK_SIZE + local_z)
		if not cached.is_equal_approx(direct):
			_fail("Warped negative-coordinate cache mismatch at local z=%d" % local_z)


func _validate_height_bounds(data) -> void:
	for chunk_z in range(-6, 7):
		for chunk_x in range(-6, 7):
			var cache := _build_height_cache(data, Vector2i(chunk_x, chunk_z))
			if cache.size() != CACHE_WIDTH * CACHE_WIDTH:
				_fail("Unexpected warped height-cache size at chunk (%d,%d)" % [chunk_x, chunk_z])
				continue
			for height in cache:
				if height < 3 or height > WORLD_DATA.WORLD_HEIGHT - 3:
					_fail("Warped height %d escaped valid bounds at chunk (%d,%d)" % [height, chunk_x, chunk_z])
					return


func _measure_domain_warp_effect(data, unwarped: Step1UnwarpedSampler) -> Dictionary:
	var total_points := GRID_SIZE * GRID_SIZE
	var changed_layers := PackedInt32Array()
	changed_layers.resize(4)
	var height_changes := 0
	var climate_quadrant_changes := 0
	var absolute_continuous_height_delta := 0.0
	var maximum_continuous_height_delta := 0.0
	var unwarped_crossings := 0
	var warped_crossings := 0

	var previous_unwarped_temperature := PackedFloat32Array()
	var previous_unwarped_moisture := PackedFloat32Array()
	var previous_warped_temperature := PackedFloat32Array()
	var previous_warped_moisture := PackedFloat32Array()
	previous_unwarped_temperature.resize(GRID_SIZE)
	previous_unwarped_moisture.resize(GRID_SIZE)
	previous_warped_temperature.resize(GRID_SIZE)
	previous_warped_moisture.resize(GRID_SIZE)

	for row in range(GRID_SIZE):
		var z := GRID_MIN + row * GRID_STEP
		var left_unwarped_temperature := 0.0
		var left_unwarped_moisture := 0.0
		var left_warped_temperature := 0.0
		var left_warped_moisture := 0.0
		for column in range(GRID_SIZE):
			var x := GRID_MIN + column * GRID_STEP
			var baseline: Vector4 = unwarped.sample_column_noise(x, z)
			var warped: Vector4 = data.sample_column_noise(x, z)

			if absf(warped.x - baseline.x) > 0.000001:
				changed_layers[0] += 1
			if absf(warped.y - baseline.y) > 0.000001:
				changed_layers[1] += 1
			if absf(warped.z - baseline.z) > 0.000001:
				changed_layers[2] += 1
			if absf(warped.w - baseline.w) > 0.000001:
				changed_layers[3] += 1

			var baseline_height_value := _continuous_height(baseline)
			var warped_height_value := _continuous_height(warped)
			var height_delta := absf(warped_height_value - baseline_height_value)
			absolute_continuous_height_delta += height_delta
			maximum_continuous_height_delta = maxf(maximum_continuous_height_delta, height_delta)
			if data.terrain_height(x, z) != unwarped.terrain_height(x, z):
				height_changes += 1

			var baseline_quadrant := _climate_quadrant(baseline.z, baseline.w)
			var warped_quadrant := _climate_quadrant(warped.z, warped.w)
			if baseline_quadrant != warped_quadrant:
				climate_quadrant_changes += 1

			if column > 0:
				unwarped_crossings += _sign_crossing(left_unwarped_temperature, baseline.z)
				unwarped_crossings += _sign_crossing(left_unwarped_moisture, baseline.w)
				warped_crossings += _sign_crossing(left_warped_temperature, warped.z)
				warped_crossings += _sign_crossing(left_warped_moisture, warped.w)
			if row > 0:
				unwarped_crossings += _sign_crossing(previous_unwarped_temperature[column], baseline.z)
				unwarped_crossings += _sign_crossing(previous_unwarped_moisture[column], baseline.w)
				warped_crossings += _sign_crossing(previous_warped_temperature[column], warped.z)
				warped_crossings += _sign_crossing(previous_warped_moisture[column], warped.w)

			left_unwarped_temperature = baseline.z
			left_unwarped_moisture = baseline.w
			left_warped_temperature = warped.z
			left_warped_moisture = warped.w
			previous_unwarped_temperature[column] = baseline.z
			previous_unwarped_moisture[column] = baseline.w
			previous_warped_temperature[column] = warped.z
			previous_warped_moisture[column] = warped.w

	var changed_layer_ratios: Array[float] = []
	for layer_index in range(4):
		var ratio := float(changed_layers[layer_index]) / float(total_points)
		changed_layer_ratios.append(ratio)
		if ratio < 0.95:
			_fail("Domain warp changed only %.2f%% of layer %d samples" % [ratio * 100.0, layer_index])

	var height_change_ratio := float(height_changes) / float(total_points)
	var climate_quadrant_change_ratio := float(climate_quadrant_changes) / float(total_points)
	var mean_absolute_height_delta := absolute_continuous_height_delta / float(total_points)
	var contour_retention_ratio := 0.0
	if unwarped_crossings > 0:
		contour_retention_ratio = float(warped_crossings) / float(unwarped_crossings)

	if height_change_ratio < 0.15:
		_fail("Domain warp changed too few rounded terrain heights: %.2f%%" % [height_change_ratio * 100.0])
	if climate_quadrant_change_ratio < 0.02:
		_fail("Domain warp moved too few future climate regions: %.2f%%" % [climate_quadrant_change_ratio * 100.0])
	if mean_absolute_height_delta < 0.10:
		_fail("Domain warp produced negligible continuous height displacement: %.4f" % mean_absolute_height_delta)
	if unwarped_crossings <= 0 or warped_crossings <= 0:
		_fail("Climate contour crossing measurement produced no usable boundaries")
	elif contour_retention_ratio < 0.70:
		_fail("Domain warp collapsed climate contour structure to %.2f%% of baseline" % [contour_retention_ratio * 100.0])

	return {
		"grid": {
			"minimum_world_coordinate": GRID_MIN,
			"maximum_world_coordinate": GRID_MAX,
			"step": GRID_STEP,
			"points": total_points,
		},
		"changed_layer_counts": [changed_layers[0], changed_layers[1], changed_layers[2], changed_layers[3]],
		"changed_layer_ratios": changed_layer_ratios,
		"rounded_height_change_count": height_changes,
		"rounded_height_change_ratio": height_change_ratio,
		"climate_quadrant_change_count": climate_quadrant_changes,
		"climate_quadrant_change_ratio": climate_quadrant_change_ratio,
		"mean_absolute_continuous_height_delta": mean_absolute_height_delta,
		"maximum_continuous_height_delta": maximum_continuous_height_delta,
		"unwarped_climate_contour_crossings": unwarped_crossings,
		"warped_climate_contour_crossings": warped_crossings,
		"contour_retention_ratio": contour_retention_ratio,
	}


func _write_diagnostic_image(data, unwarped: Step1UnwarpedSampler) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://artifacts"))
	var image := Image.create(DIAGNOSTIC_WIDTH, DIAGNOSTIC_HEIGHT, false, Image.FORMAT_RGB8)
	for pixel_y in range(DIAGNOSTIC_HEIGHT):
		var world_z := roundi((float(pixel_y) - float(DIAGNOSTIC_HEIGHT) * 0.5) * DIAGNOSTIC_WORLD_SCALE)
		for pixel_x in range(DIAGNOSTIC_WIDTH):
			var panel_x := pixel_x % DIAGNOSTIC_PANEL_SIZE
			var world_x := roundi((float(panel_x) - float(DIAGNOSTIC_PANEL_SIZE) * 0.5) * DIAGNOSTIC_WORLD_SCALE)
			var samples := Vector4()
			if pixel_x < DIAGNOSTIC_PANEL_SIZE:
				samples = unwarped.sample_column_noise(world_x, world_z)
			else:
				samples = data.sample_column_noise(world_x, world_z)
			image.set_pixel(pixel_x, pixel_y, _diagnostic_color(samples))
	for pixel_y in range(DIAGNOSTIC_HEIGHT):
		image.set_pixel(DIAGNOSTIC_PANEL_SIZE - 1, pixel_y, Color.WHITE)
		image.set_pixel(DIAGNOSTIC_PANEL_SIZE, pixel_y, Color.WHITE)
	var save_error := image.save_png(DIAGNOSTIC_PATH)
	if save_error != OK:
		_fail("Unable to save Step 2 domain-warp diagnostic image: error %d" % save_error)


func _diagnostic_color(samples: Vector4) -> Color:
	var temperature := clampf(samples.z * 0.5 + 0.5, 0.0, 1.0)
	var moisture := clampf(samples.w * 0.5 + 0.5, 0.0, 1.0)
	var height_value := clampf((_continuous_height(samples) - 3.0) / float(WORLD_DATA.WORLD_HEIGHT - 6), 0.0, 1.0)
	return Color(
		0.15 + temperature * 0.75,
		0.15 + moisture * 0.75,
		0.15 + height_value * 0.75
	)


func _run_benchmark(data, unwarped: Step1UnwarpedSampler) -> Dictionary:
	var coords: Array[Vector2i] = []
	for z in range(-2, 2):
		for x in range(-4, 4):
			coords.append(Vector2i(x, z))

	for _warmup in range(WARMUP_REPETITIONS):
		for coord in coords:
			_consume_cache(_build_height_cache(unwarped, coord))
			_consume_cache(_build_height_cache(data, coord))

	var unwarped_usec: Array[int] = []
	var warped_usec: Array[int] = []
	var unwarped_checksum := 0
	var warped_checksum := 0

	for repetition in range(MEASURED_REPETITIONS):
		for index in range(coords.size()):
			var coord: Vector2i = coords[index]
			if (repetition + index) % 2 == 0:
				var baseline_first := _measure_cache(unwarped, coord)
				unwarped_usec.append(int(baseline_first["usec"]))
				unwarped_checksum += int(baseline_first["checksum"])
				var warped_second := _measure_cache(data, coord)
				warped_usec.append(int(warped_second["usec"]))
				warped_checksum += int(warped_second["checksum"])
			else:
				var warped_first := _measure_cache(data, coord)
				warped_usec.append(int(warped_first["usec"]))
				warped_checksum += int(warped_first["checksum"])
				var baseline_second := _measure_cache(unwarped, coord)
				unwarped_usec.append(int(baseline_second["usec"]))
				unwarped_checksum += int(baseline_second["checksum"])

	var unwarped_stats := _stats(unwarped_usec)
	var warped_stats := _stats(warped_usec)
	var baseline_mean := float(unwarped_stats["mean_usec"])
	var warped_mean := float(warped_stats["mean_usec"])
	var relative_cost_percent := 0.0
	if baseline_mean > 0.0:
		relative_cost_percent = ((warped_mean / baseline_mean) - 1.0) * 100.0

	if int(warped_stats["p95_usec"]) >= 1000:
		_fail("Warped GDScript generation reached %d usec p95 on CI" % int(warped_stats["p95_usec"]))

	return {
		"runner": {
			"os_name": OS.get_name(),
			"processor_name": OS.get_processor_name(),
			"processor_count": OS.get_processor_count(),
			"godot_version": str(Engine.get_version_info().get("string", "unknown")),
		},
		"benchmark_contract": {
			"chunk_size": CHUNK_SIZE,
			"logical_columns_per_chunk": CHUNK_SIZE * CHUNK_SIZE,
			"cache_padding": CACHE_PADDING,
			"sampled_columns_per_chunk": CACHE_WIDTH * CACHE_WIDTH,
			"warmup_repetitions": WARMUP_REPETITIONS,
			"measured_repetitions": MEASURED_REPETITIONS,
			"unique_chunk_coordinates": coords.size(),
			"measured_chunks_per_path": coords.size() * MEASURED_REPETITIONS,
			"base_noise_layers_per_column": WORLD_DATA.NOISE_SAMPLES_PER_COLUMN,
			"domain_warped_layers": WORLD_DATA.DOMAIN_WARPED_LAYER_COUNT,
			"warp_amplitude": WORLD_DATA.DOMAIN_WARP_AMPLITUDE,
			"warp_frequency": WORLD_DATA.DOMAIN_WARP_FREQUENCY,
			"warp_octaves": WORLD_DATA.DOMAIN_WARP_FRACTAL_OCTAVES,
			"included_work": "height-cache allocation, world-coordinate loop, four FastNoiseLite samples, height calculation and writes",
			"excluded_work": ["meshing", "rendering", "scene-tree mutation", "collision generation", "file I/O", "world-save loading"],
		},
		"step1_unwarped_four_noise": unwarped_stats,
		"step2_domain_warped_four_noise": warped_stats,
		"relative_cost_percent": relative_cost_percent,
		"absolute_mean_cost_usec": warped_mean - baseline_mean,
		"unwarped_checksum": unwarped_checksum,
		"warped_checksum": warped_checksum,
		"raw_unwarped_usec": unwarped_usec,
		"raw_warped_usec": warped_usec,
	}


func _measure_cache(sampler, coord: Vector2i) -> Dictionary:
	var start_usec := Time.get_ticks_usec()
	var cache := _build_height_cache(sampler, coord)
	var elapsed_usec := maxi(1, Time.get_ticks_usec() - start_usec)
	return {"usec": elapsed_usec, "checksum": _consume_cache(cache)}


func _build_height_cache(sampler, coord: Vector2i) -> PackedInt32Array:
	var heights := PackedInt32Array()
	heights.resize(CACHE_WIDTH * CACHE_WIDTH)
	var origin_x := coord.x * CHUNK_SIZE
	var origin_z := coord.y * CHUNK_SIZE
	for local_z in range(-CACHE_PADDING, CHUNK_SIZE + CACHE_PADDING):
		for local_x in range(-CACHE_PADDING, CHUNK_SIZE + CACHE_PADDING):
			var index := (local_z + CACHE_PADDING) * CACHE_WIDTH + local_x + CACHE_PADDING
			heights[index] = sampler.terrain_height(origin_x + local_x, origin_z + local_z)
	return heights


func _build_sample_cache(data, coord: Vector2i) -> Array[Vector4]:
	var samples: Array[Vector4] = []
	samples.resize(CACHE_WIDTH * CACHE_WIDTH)
	var origin_x := coord.x * CHUNK_SIZE
	var origin_z := coord.y * CHUNK_SIZE
	for local_z in range(-CACHE_PADDING, CHUNK_SIZE + CACHE_PADDING):
		for local_x in range(-CACHE_PADDING, CHUNK_SIZE + CACHE_PADDING):
			var index := (local_z + CACHE_PADDING) * CACHE_WIDTH + local_x + CACHE_PADDING
			samples[index] = data.sample_column_noise(origin_x + local_x, origin_z + local_z)
	return samples


func _sample_cache_value(cache: Array[Vector4], local_x: int, local_z: int) -> Vector4:
	var index := (local_z + CACHE_PADDING) * CACHE_WIDTH + local_x + CACHE_PADDING
	return cache[index]


func _continuous_height(samples: Vector4) -> float:
	return 10.0 + samples.x * 6.4 + samples.y * 3.0


func _climate_quadrant(temperature: float, moisture: float) -> int:
	var temperature_bit := 1 if temperature >= 0.0 else 0
	var moisture_bit := 2 if moisture >= 0.0 else 0
	return temperature_bit | moisture_bit


func _sign_crossing(first: float, second: float) -> int:
	if (first < 0.0 and second >= 0.0) or (first >= 0.0 and second < 0.0):
		return 1
	return 0


func _consume_cache(cache: PackedInt32Array) -> int:
	var checksum := 0
	for height in cache:
		checksum += height
	return checksum


func _stats(values: Array[int]) -> Dictionary:
	var sorted := values.duplicate()
	sorted.sort()
	var count := sorted.size()
	var total := 0
	for value in sorted:
		total += value
	var mean_usec := float(total) / float(count)
	var middle := int(count / 2)
	var median_usec := float(sorted[middle])
	if count % 2 == 0:
		median_usec = (float(sorted[middle - 1]) + float(sorted[middle])) * 0.5
	var p95_index := clampi(ceili(float(count) * 0.95) - 1, 0, count - 1)
	return {
		"sample_count": count,
		"minimum_usec": sorted[0],
		"maximum_usec": sorted[count - 1],
		"mean_usec": mean_usec,
		"median_usec": median_usec,
		"p95_usec": sorted[p95_index],
		"total_usec": total,
		"minimum_ms": float(sorted[0]) / 1000.0,
		"maximum_ms": float(sorted[count - 1]) / 1000.0,
		"mean_ms": mean_usec / 1000.0,
		"median_ms": median_usec / 1000.0,
		"p95_ms": float(sorted[p95_index]) / 1000.0,
		"total_ms": float(total) / 1000.0,
	}


func _count_occurrences(text: String, needle: String) -> int:
	var count := 0
	var offset := 0
	var found := text.find(needle, offset)
	while found >= 0:
		count += 1
		offset = found + needle.length()
		found = text.find(needle, offset)
	return count


func _fail(message: String) -> void:
	failures.append(message)
