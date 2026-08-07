extends SceneTree

const WORLD_DATA := preload("res://scripts/world/playable_world_data.gd")
const WORLD_MAP_OVERLAY := preload("res://scripts/ui/world_map_overlay.gd")

const SAMPLE_SPACING_BLOCKS := 2
const LINE_HALF_BLOCKS := 2048
# Holdout transects were not used to choose the production parameters.
const HOLDOUT_OFFSETS: Array[int] = [-1844, -1326, -874, -446, -54, 338, 794, 1258, 1714]

const LEGACY_TEMPERATURE_FREQUENCY := 0.0024
const LEGACY_MOISTURE_FREQUENCY := 0.0028
const LEGACY_PATCH_SIZE := 12
const SELECTED_TEMPERATURE_FREQUENCY := 0.0012
const SELECTED_MOISTURE_FREQUENCY := 0.0014
const SELECTED_PATCH_SIZE := 24

const MIN_EXPECTED_BOUNDARY_DISTANCE_BLOCKS := 100.0
const MIN_MEDIAN_RUN_BLOCKS := 28.0
const MIN_P75_RUN_BLOCKS := 80.0
const MIN_UNINTERRUPTED_64_RATIO := 0.48
const MIN_BIOME_RATIO := 0.08

var failures: Array[String] = []


func _init() -> void:
	var data = WORLD_DATA.new()
	_validate_contract(data)

	var shipping := _analyze_shipping(data)
	var legacy := _analyze_variant(
		data,
		LEGACY_TEMPERATURE_FREQUENCY,
		LEGACY_MOISTURE_FREQUENCY,
		LEGACY_PATCH_SIZE
	)
	var frequency_only := _analyze_variant(
		data,
		SELECTED_TEMPERATURE_FREQUENCY,
		SELECTED_MOISTURE_FREQUENCY,
		LEGACY_PATCH_SIZE
	)
	var patch_only := _analyze_variant(
		data,
		LEGACY_TEMPERATURE_FREQUENCY,
		LEGACY_MOISTURE_FREQUENCY,
		SELECTED_PATCH_SIZE
	)

	var shipping_failures := _zone_failures(shipping)
	var legacy_failures := _zone_failures(legacy)
	var frequency_only_failures := _zone_failures(frequency_only)
	var patch_only_failures := _zone_failures(patch_only)
	for failure in shipping_failures:
		_fail("Shipping large-zone gate failed: %s" % failure)
	if legacy_failures.is_empty():
		_fail("New zone-size gate does not catch the previous 0.0024/0.0028 + 12-block implementation")
	if frequency_only_failures.is_empty():
		_fail("Frequency reduction alone unexpectedly satisfies the large-zone contract")
	if patch_only_failures.is_empty():
		_fail("Patch increase alone unexpectedly satisfies the large-zone contract")

	var report := {
		"sampling_contract": {
			"spacing_blocks": SAMPLE_SPACING_BLOCKS,
			"shipping_map_spacing_blocks": WORLD_MAP_OVERLAY.MAP_SAMPLE_SPACING,
			"holdout_offset_count": HOLDOUT_OFFSETS.size(),
			"total_transects": HOLDOUT_OFFSETS.size() * 2,
			"line_span_blocks": LINE_HALF_BLOCKS * 2,
			"points_per_transect": int((LINE_HALF_BLOCKS * 2) / SAMPLE_SPACING_BLOCKS) + 1,
			"tuning_offsets_reused": false,
		},
		"terrain_scope_preserved": {
			"temperature_frequency": data.temperature_noise.frequency,
			"moisture_frequency": data.moisture_noise.frequency,
			"expected_temperature_frequency": LEGACY_TEMPERATURE_FREQUENCY,
			"expected_moisture_frequency": LEGACY_MOISTURE_FREQUENCY,
		},
		"production_biome_contract": {
			"temperature_frequency": data.biome_temperature_noise.frequency,
			"moisture_frequency": data.biome_moisture_noise.frequency,
			"patch_size_blocks": WORLD_DATA.BIOME_BLEND_PATCH_SIZE,
		},
		"thresholds": {
			"min_expected_boundary_distance_blocks": MIN_EXPECTED_BOUNDARY_DISTANCE_BLOCKS,
			"min_median_run_blocks": MIN_MEDIAN_RUN_BLOCKS,
			"min_p75_run_blocks": MIN_P75_RUN_BLOCKS,
			"min_uninterrupted_64_ratio": MIN_UNINTERRUPTED_64_RATIO,
			"min_biome_ratio": MIN_BIOME_RATIO,
		},
		"shipping": shipping,
		"legacy_current_counterfactual": legacy,
		"frequency_only_counterfactual": frequency_only,
		"patch_only_counterfactual": patch_only,
		"shipping_failures": shipping_failures,
		"legacy_failures": legacy_failures,
		"frequency_only_failures": frequency_only_failures,
		"patch_only_failures": patch_only_failures,
		"legacy_would_fail_new_gate": not legacy_failures.is_empty(),
		"frequency_only_would_fail_new_gate": not frequency_only_failures.is_empty(),
		"patch_only_would_fail_new_gate": not patch_only_failures.is_empty(),
	}
	print("BIOME_ZONE_SIZE_GATE_JSON=%s" % JSON.stringify(report))
	if failures.is_empty():
		print("BIOME_ZONE_SIZE_GATE_PASS")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func _validate_contract(data) -> void:
	if WORLD_MAP_OVERLAY.MAP_SAMPLE_SPACING != SAMPLE_SPACING_BLOCKS:
		_fail("Zone-size gate must sample at the shipping 2-block map resolution")
	# Terrain-height climate must stay exactly at the accepted pre-fix scale.
	if not is_equal_approx(float(data.temperature_noise.frequency), LEGACY_TEMPERATURE_FREQUENCY):
		_fail("Terrain temperature frequency changed outside biome-zone scope")
	if not is_equal_approx(float(data.moisture_noise.frequency), LEGACY_MOISTURE_FREQUENCY):
		_fail("Terrain moisture frequency changed outside biome-zone scope")
	# Only the biome resolver gets the slower climate scale.
	if not is_equal_approx(float(data.biome_temperature_noise.frequency), SELECTED_TEMPERATURE_FREQUENCY):
		_fail("Biome temperature frequency is not the diagnosed 0.0012")
	if not is_equal_approx(float(data.biome_moisture_noise.frequency), SELECTED_MOISTURE_FREQUENCY):
		_fail("Biome moisture frequency is not the diagnosed 0.0014")
	if WORLD_DATA.BIOME_BLEND_PATCH_SIZE != SELECTED_PATCH_SIZE:
		_fail("Biome blend patch is not the diagnosed 24 blocks")


func _analyze_shipping(data) -> Dictionary:
	var run_samples: Array[int] = []
	var biome_counts := _new_biome_counts()
	var total_points := 0
	var line_count := 0
	for offset in HOLDOUT_OFFSETS:
		for horizontal in [true, false]:
			var line := _sample_shipping_line(data, bool(horizontal), offset)
			_accumulate_line(line, run_samples, biome_counts)
			total_points += int(line["points"])
			line_count += 1
	return _metrics(run_samples, biome_counts, total_points, line_count)


func _analyze_variant(data, temperature_frequency: float, moisture_frequency: float, patch_size: int) -> Dictionary:
	var temperature := _make_climate_noise(WORLD_DATA.WORLD_SEED ^ 0x68bc21eb, temperature_frequency)
	var moisture := _make_climate_noise(WORLD_DATA.WORLD_SEED ^ 0x02e5be93, moisture_frequency)
	var run_samples: Array[int] = []
	var biome_counts := _new_biome_counts()
	var total_points := 0
	var line_count := 0
	for offset in HOLDOUT_OFFSETS:
		for horizontal in [true, false]:
			var line := _sample_variant_line(data, temperature, moisture, patch_size, bool(horizontal), offset)
			_accumulate_line(line, run_samples, biome_counts)
			total_points += int(line["points"])
			line_count += 1
	var result := _metrics(run_samples, biome_counts, total_points, line_count)
	result["temperature_frequency"] = temperature_frequency
	result["moisture_frequency"] = moisture_frequency
	result["patch_size_blocks"] = patch_size
	return result


func _sample_shipping_line(data, horizontal: bool, offset: int) -> Dictionary:
	return _sample_line(func(x: int, z: int) -> int: return data.biome_at(x, z), horizontal, offset)


func _sample_variant_line(data, temperature: FastNoiseLite, moisture: FastNoiseLite, patch_size: int, horizontal: bool, offset: int) -> Dictionary:
	return _sample_line(func(x: int, z: int) -> int:
		return _resolve_variant(data, temperature, moisture, patch_size, x, z), horizontal, offset)


func _sample_line(resolver: Callable, horizontal: bool, offset: int) -> Dictionary:
	var point_count := int((LINE_HALF_BLOCKS * 2) / SAMPLE_SPACING_BLOCKS) + 1
	var values := PackedByteArray()
	values.resize(point_count)
	var biome_counts := _new_biome_counts()
	for index in range(point_count):
		var varying := -LINE_HALF_BLOCKS + index * SAMPLE_SPACING_BLOCKS
		var x := varying if horizontal else offset
		var z := offset if horizontal else varying
		var biome := int(resolver.call(x, z))
		values[index] = biome
		biome_counts[biome] += 1

	var runs: Array[int] = []
	if not values.is_empty():
		var current := int(values[0])
		var run_size := 1
		for index in range(1, values.size()):
			var biome := int(values[index])
			if biome == current:
				run_size += 1
			else:
				runs.append(run_size)
				current = biome
				run_size = 1
		runs.append(run_size)
	return {"points": point_count, "runs": runs, "biome_counts": biome_counts}


func _accumulate_line(line: Dictionary, run_samples: Array[int], biome_counts: PackedInt64Array) -> void:
	for run_size in line["runs"]:
		run_samples.append(int(run_size))
	var line_counts: PackedInt64Array = line["biome_counts"]
	for biome in range(WORLD_DATA.BIOME_COUNT):
		biome_counts[biome] += line_counts[biome]


func _metrics(run_samples: Array[int], biome_counts: PackedInt64Array, total_points: int, line_count: int) -> Dictionary:
	var run_blocks: Array[float] = []
	var run_sample_sum := 0
	var boundary_distance_numerator := 0.0
	var successful_64_directions := 0
	var required_64_steps := ceili(64.0 / float(SAMPLE_SPACING_BLOCKS))
	for sample_count in run_samples:
		run_sample_sum += sample_count
		run_blocks.append(float(sample_count * SAMPLE_SPACING_BLOCKS))
		boundary_distance_numerator += float(sample_count) * float(maxi(0, sample_count - 1)) * float(SAMPLE_SPACING_BLOCKS) * 0.5
		successful_64_directions += 2 * maxi(0, sample_count - required_64_steps)
	run_blocks.sort()
	var counts: Array[int] = []
	var ratios: Array[float] = []
	for biome in range(WORLD_DATA.BIOME_COUNT):
		counts.append(int(biome_counts[biome]))
		ratios.append(float(biome_counts[biome]) / float(maxi(1, total_points)))
	var transitions := maxi(0, run_samples.size() - line_count)
	var adjacency_edges := maxi(1, total_points - line_count)
	return {
		"sampled_points": total_points,
		"run_count": run_samples.size(),
		"mean_same_biome_run_blocks": float(run_sample_sum * SAMPLE_SPACING_BLOCKS) / float(maxi(1, run_samples.size())),
		"median_same_biome_run_blocks": _percentile(run_blocks, 0.50),
		"p75_same_biome_run_blocks": _percentile(run_blocks, 0.75),
		"p90_same_biome_run_blocks": _percentile(run_blocks, 0.90),
		"p95_same_biome_run_blocks": _percentile(run_blocks, 0.95),
		"expected_one_way_boundary_distance_blocks": boundary_distance_numerator / float(maxi(1, total_points)),
		"uninterrupted_64_block_travel_ratio": float(successful_64_directions) / float(maxi(1, total_points * 2)),
		"transition_ratio_2block_adjacency": float(transitions) / float(adjacency_edges),
		"biome_counts": counts,
		"biome_ratios": ratios,
	}


func _zone_failures(metrics: Dictionary) -> Array[String]:
	var result: Array[String] = []
	if float(metrics["expected_one_way_boundary_distance_blocks"]) < MIN_EXPECTED_BOUNDARY_DISTANCE_BLOCKS:
		result.append("expected boundary distance %.3f < %.3f blocks" % [float(metrics["expected_one_way_boundary_distance_blocks"]), MIN_EXPECTED_BOUNDARY_DISTANCE_BLOCKS])
	if float(metrics["median_same_biome_run_blocks"]) < MIN_MEDIAN_RUN_BLOCKS:
		result.append("median run %.3f < %.3f blocks" % [float(metrics["median_same_biome_run_blocks"]), MIN_MEDIAN_RUN_BLOCKS])
	if float(metrics["p75_same_biome_run_blocks"]) < MIN_P75_RUN_BLOCKS:
		result.append("p75 run %.3f < %.3f blocks" % [float(metrics["p75_same_biome_run_blocks"]), MIN_P75_RUN_BLOCKS])
	if float(metrics["uninterrupted_64_block_travel_ratio"]) < MIN_UNINTERRUPTED_64_RATIO:
		result.append("64-block uninterrupted ratio %.6f < %.6f" % [float(metrics["uninterrupted_64_block_travel_ratio"]), MIN_UNINTERRUPTED_64_RATIO])
	for biome in range(WORLD_DATA.BIOME_COUNT):
		if float(metrics["biome_ratios"][biome]) < MIN_BIOME_RATIO:
			result.append("biome %d ratio %.6f < %.6f" % [biome, float(metrics["biome_ratios"][biome]), MIN_BIOME_RATIO])
	return result


func _resolve_variant(data, temperature: FastNoiseLite, moisture: FastNoiseLite, patch_size: int, x: int, z: int) -> int:
	var weights: Vector4 = data.biome_weights_from_climate(
		temperature.get_noise_2d(float(x), float(z)),
		moisture.get_noise_2d(float(x), float(z))
	)
	var patch_x := floori(float(x) / float(patch_size))
	var patch_z := floori(float(z) / float(patch_size))
	var selector := _blend_selector(patch_x, patch_z)
	var cumulative := weights.x
	if selector < cumulative:
		return WORLD_DATA.BIOME_PLAINS
	cumulative += weights.y
	if selector < cumulative:
		return WORLD_DATA.BIOME_FOREST
	cumulative += weights.z
	if selector < cumulative:
		return WORLD_DATA.BIOME_DESERT
	return WORLD_DATA.BIOME_ROCKY


func _make_climate_noise(seed_value: int, frequency: float) -> FastNoiseLite:
	var noise := FastNoiseLite.new()
	noise.seed = seed_value
	noise.frequency = frequency
	noise.fractal_octaves = 3
	noise.fractal_gain = 0.5
	noise.fractal_lacunarity = 2.0
	noise.domain_warp_enabled = true
	noise.domain_warp_type = FastNoiseLite.DOMAIN_WARP_SIMPLEX_REDUCED
	noise.domain_warp_amplitude = WORLD_DATA.DOMAIN_WARP_AMPLITUDE
	noise.domain_warp_frequency = WORLD_DATA.DOMAIN_WARP_FREQUENCY
	noise.domain_warp_fractal_type = FastNoiseLite.DOMAIN_WARP_FRACTAL_PROGRESSIVE
	noise.domain_warp_fractal_octaves = WORLD_DATA.DOMAIN_WARP_FRACTAL_OCTAVES
	noise.domain_warp_fractal_gain = WORLD_DATA.DOMAIN_WARP_FRACTAL_GAIN
	noise.domain_warp_fractal_lacunarity = WORLD_DATA.DOMAIN_WARP_FRACTAL_LACUNARITY
	return noise


func _blend_selector(patch_x: int, patch_z: int) -> float:
	var hash_value := (patch_x * 73856093) ^ (patch_z * 19349663) ^ (WORLD_DATA.WORLD_SEED * 83492791)
	hash_value = absi(hash_value)
	return float(hash_value % 1000003) / 1000003.0


func _new_biome_counts() -> PackedInt64Array:
	var result := PackedInt64Array()
	result.resize(WORLD_DATA.BIOME_COUNT)
	return result


func _percentile(sorted_values: Array[float], percentile: float) -> float:
	if sorted_values.is_empty():
		return 0.0
	var index := clampi(ceili(percentile * float(sorted_values.size())) - 1, 0, sorted_values.size() - 1)
	return sorted_values[index]


func _fail(message: String) -> void:
	if not failures.has(message):
		failures.append(message)
