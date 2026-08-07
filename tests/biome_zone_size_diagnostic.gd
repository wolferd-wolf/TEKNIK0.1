extends SceneTree

const WORLD_DATA := preload("res://scripts/world/playable_world_data.gd")
const WORLD_MAP_OVERLAY := preload("res://scripts/ui/world_map_overlay.gd")

const SAMPLE_SPACING_BLOCKS := 2
const LINE_HALF_BLOCKS := 2048
const TRANSECT_OFFSETS: Array[int] = [-1536, -1024, -512, -128, 128, 512, 1024, 1536]
const RETENTION_DISTANCES: Array[int] = [32, 64, 96, 128]

const CANDIDATES: Array[Dictionary] = [
	{"name": "current", "temperature_frequency": 0.0024, "moisture_frequency": 0.0028, "patch_size": 12},
	{"name": "frequency_75pct", "temperature_frequency": 0.0018, "moisture_frequency": 0.0021, "patch_size": 12},
	{"name": "frequency_50pct", "temperature_frequency": 0.0012, "moisture_frequency": 0.0014, "patch_size": 12},
	{"name": "patch_24_only", "temperature_frequency": 0.0024, "moisture_frequency": 0.0028, "patch_size": 24},
	{"name": "patch_48_only", "temperature_frequency": 0.0024, "moisture_frequency": 0.0028, "patch_size": 48},
	{"name": "frequency_75pct_patch_24", "temperature_frequency": 0.0018, "moisture_frequency": 0.0021, "patch_size": 24},
	{"name": "frequency_50pct_patch_24", "temperature_frequency": 0.0012, "moisture_frequency": 0.0014, "patch_size": 24},
	{"name": "frequency_50pct_patch_48", "temperature_frequency": 0.0012, "moisture_frequency": 0.0014, "patch_size": 48},
]

var failures: Array[String] = []


func _init() -> void:
	var data = WORLD_DATA.new()
	_validate_sampling_contract()
	var equivalence := _validate_current_model_equivalence(data)
	if int(equivalence["mismatches"]) != 0:
		_fail("Parameterized diagnostic does not reproduce the shipping current biome resolver")

	var reports: Array[Dictionary] = []
	for candidate in CANDIDATES:
		var started_usec := Time.get_ticks_usec()
		var report := _analyze_candidate(data, candidate)
		report["elapsed_ms"] = float(Time.get_ticks_usec() - started_usec) / 1000.0
		reports.append(report)

	var output := {
		"purpose": "diagnose biome macro-zone size before production tuning",
		"sampling": {
			"spacing_blocks": SAMPLE_SPACING_BLOCKS,
			"shipping_map_spacing_blocks": WORLD_MAP_OVERLAY.MAP_SAMPLE_SPACING,
			"line_min_block": -LINE_HALF_BLOCKS,
			"line_max_block": LINE_HALF_BLOCKS,
			"line_span_blocks": LINE_HALF_BLOCKS * 2,
			"horizontal_transects": TRANSECT_OFFSETS.size(),
			"vertical_transects": TRANSECT_OFFSETS.size(),
			"total_transects": TRANSECT_OFFSETS.size() * 2,
			"points_per_transect": int((LINE_HALF_BLOCKS * 2) / SAMPLE_SPACING_BLOCKS) + 1,
		},
		"shipping_current": {
			"temperature_frequency": data.temperature_noise.frequency,
			"moisture_frequency": data.moisture_noise.frequency,
			"patch_size": WORLD_DATA.BIOME_BLEND_PATCH_SIZE,
		},
		"model_equivalence": equivalence,
		"candidates": reports,
	}
	print("BIOME_ZONE_DIAGNOSTIC_JSON=%s" % JSON.stringify(output))
	if failures.is_empty():
		print("BIOME_ZONE_DIAGNOSTIC_PASS")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func _validate_sampling_contract() -> void:
	if WORLD_MAP_OVERLAY.MAP_SAMPLE_SPACING != SAMPLE_SPACING_BLOCKS:
		_fail("Diagnostic spacing must match the shipping map/player-visible 2-block sampling scale")
	if LINE_HALF_BLOCKS % SAMPLE_SPACING_BLOCKS != 0:
		_fail("Transect extent must be divisible by sampling spacing")


func _validate_current_model_equivalence(data) -> Dictionary:
	var temperature := _make_climate_noise(WORLD_DATA.WORLD_SEED ^ 0x68bc21eb, 0.0024)
	var moisture := _make_climate_noise(WORLD_DATA.WORLD_SEED ^ 0x02e5be93, 0.0028)
	var mismatches := 0
	var probes := 0
	for center in [Vector2i(0, 0), Vector2i(512, 512), Vector2i(-512, 256), Vector2i(1024, -768)]:
		for dz in range(-128, 129, 16):
			for dx in range(-128, 129, 16):
				var x: int = center.x + dx
				var z: int = center.y + dz
				var modeled := _resolve_biome(data, temperature, moisture, WORLD_DATA.BIOME_BLEND_PATCH_SIZE, x, z)
				var shipping := data.biome_at(x, z)
				probes += 1
				if modeled != shipping:
					mismatches += 1
	return {"probes": probes, "mismatches": mismatches}


func _analyze_candidate(data, candidate: Dictionary) -> Dictionary:
	var temperature := _make_climate_noise(
		WORLD_DATA.WORLD_SEED ^ 0x68bc21eb,
		float(candidate["temperature_frequency"])
	)
	var moisture := _make_climate_noise(
		WORLD_DATA.WORLD_SEED ^ 0x02e5be93,
		float(candidate["moisture_frequency"])
	)
	var patch_size := int(candidate["patch_size"])
	var run_samples: Array[int] = []
	var total_points := 0
	var biome_counts := PackedInt64Array()
	biome_counts.resize(WORLD_DATA.BIOME_COUNT)
	var line_count := 0

	for offset in TRANSECT_OFFSETS:
		var horizontal := _sample_line(data, temperature, moisture, patch_size, true, offset)
		_accumulate_line(horizontal, run_samples, biome_counts)
		total_points += int(horizontal["points"])
		line_count += 1
		var vertical := _sample_line(data, temperature, moisture, patch_size, false, offset)
		_accumulate_line(vertical, run_samples, biome_counts)
		total_points += int(vertical["points"])
		line_count += 1

	var run_blocks: Array[float] = []
	var run_sample_sum := 0
	var boundary_distance_numerator := 0.0
	for sample_count in run_samples:
		run_sample_sum += sample_count
		run_blocks.append(float(sample_count * SAMPLE_SPACING_BLOCKS))
		boundary_distance_numerator += (
			float(sample_count) * float(maxi(0, sample_count - 1))
			* float(SAMPLE_SPACING_BLOCKS) * 0.5
		)
	run_blocks.sort()

	var retention := {}
	for distance in RETENTION_DISTANCES:
		var required_steps := ceili(float(distance) / float(SAMPLE_SPACING_BLOCKS))
		var successful_directions := 0
		for sample_count in run_samples:
			successful_directions += 2 * maxi(0, sample_count - required_steps)
		retention[str(distance)] = float(successful_directions) / float(maxi(1, total_points * 2))

	var counts: Array[int] = []
	var ratios: Array[float] = []
	for biome in range(WORLD_DATA.BIOME_COUNT):
		counts.append(int(biome_counts[biome]))
		ratios.append(float(biome_counts[biome]) / float(maxi(1, total_points)))

	var transitions := maxi(0, run_samples.size() - line_count)
	var adjacency_edges := maxi(1, total_points - line_count)
	return {
		"name": str(candidate["name"]),
		"temperature_frequency": float(candidate["temperature_frequency"]),
		"moisture_frequency": float(candidate["moisture_frequency"]),
		"patch_size_blocks": patch_size,
		"sampled_points": total_points,
		"run_count": run_samples.size(),
		"mean_same_biome_run_blocks": float(run_sample_sum * SAMPLE_SPACING_BLOCKS) / float(maxi(1, run_samples.size())),
		"median_same_biome_run_blocks": _percentile(run_blocks, 0.50),
		"p75_same_biome_run_blocks": _percentile(run_blocks, 0.75),
		"p90_same_biome_run_blocks": _percentile(run_blocks, 0.90),
		"p95_same_biome_run_blocks": _percentile(run_blocks, 0.95),
		"expected_one_way_boundary_distance_blocks": boundary_distance_numerator / float(maxi(1, total_points)),
		"uninterrupted_travel_ratio": retention,
		"transition_ratio_2block_adjacency": float(transitions) / float(adjacency_edges),
		"biome_counts": counts,
		"biome_ratios": ratios,
	}


func _sample_line(data, temperature: FastNoiseLite, moisture: FastNoiseLite, patch_size: int, horizontal: bool, offset: int) -> Dictionary:
	var values := PackedByteArray()
	var point_count := int((LINE_HALF_BLOCKS * 2) / SAMPLE_SPACING_BLOCKS) + 1
	values.resize(point_count)
	var biome_counts := PackedInt64Array()
	biome_counts.resize(WORLD_DATA.BIOME_COUNT)
	for index in range(point_count):
		var varying := -LINE_HALF_BLOCKS + index * SAMPLE_SPACING_BLOCKS
		var x := varying if horizontal else offset
		var z := offset if horizontal else varying
		var biome := _resolve_biome(data, temperature, moisture, patch_size, x, z)
		values[index] = biome
		biome_counts[biome] += 1

	var runs: Array[int] = []
	if point_count > 0:
		var current := int(values[0])
		var run_size := 1
		for index in range(1, point_count):
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


func _resolve_biome(data, temperature: FastNoiseLite, moisture: FastNoiseLite, patch_size: int, x: int, z: int) -> int:
	var temperature_value := temperature.get_noise_2d(float(x), float(z))
	var moisture_value := moisture.get_noise_2d(float(x), float(z))
	var weights: Vector4 = data.biome_weights_from_climate(temperature_value, moisture_value)
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
	noise.domain_warp_amplitude = 36.0
	noise.domain_warp_frequency = 0.004
	noise.domain_warp_fractal_type = FastNoiseLite.DOMAIN_WARP_FRACTAL_PROGRESSIVE
	noise.domain_warp_fractal_octaves = 2
	noise.domain_warp_fractal_gain = 0.5
	noise.domain_warp_fractal_lacunarity = 2.0
	return noise


func _blend_selector(patch_x: int, patch_z: int) -> float:
	var hash_value := (patch_x * 73856093) ^ (patch_z * 19349663) ^ (WORLD_DATA.WORLD_SEED * 83492791)
	hash_value = absi(hash_value)
	return float(hash_value % 1000003) / 1000003.0


func _percentile(sorted_values: Array[float], percentile: float) -> float:
	if sorted_values.is_empty():
		return 0.0
	var index := clampi(ceili(percentile * float(sorted_values.size())) - 1, 0, sorted_values.size() - 1)
	return sorted_values[index]


func _fail(message: String) -> void:
	if not failures.has(message):
		failures.append(message)
