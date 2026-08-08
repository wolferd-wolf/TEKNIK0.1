extends SceneTree

const AUDIT_DATA := preload("res://tests/world_overhaul_stage13_audit_data.gd")
const DATA := preload("res://scripts/world/playable_world_stage13_data.gd")
const CACHE := preload("res://scripts/world/playable_world_stage13_generation_cache_fast.gd")
const MAP := preload("res://scripts/ui/world_map_overlay.gd")

const CHUNK_SIZE := 12
const PADDING := 2
const WIDTH := 16
const FIELD_STRIDE := 6
const AUDIT_CHUNK_RADIUS := 48
const FIXED_SEEDS := [734921, 19088743, 11235813]
const MODIFIER_NAMES := ["none", "hill", "plateau", "mountain", "valley"]
const P95_LIMIT_USEC := 1000
const WARMUPS := 4
const REPEATS := 20
const SCREENSHOT_CENTER := Vector2i(83, 56)
const SCREENSHOT_MAP_HALF_PIXELS := 24
const SCREENSHOT_MAP_SPACING := 2

var failures: Array[String] = []


func _init() -> void:
	var aggregate := _new_accumulator()
	var per_seed: Array = []
	for seed_variant in FIXED_SEEDS:
		var raw := _audit_seed(int(seed_variant))
		per_seed.append(_summarize(raw))
		_merge(aggregate, raw)
	var aggregate_report := _summarize(aggregate)
	var shipping_sampler = DATA.new()
	var screenshot := _screenshot_report(shipping_sampler)
	var benchmark := _benchmark(shipping_sampler)
	_gate_contract(aggregate_report, aggregate, screenshot)
	if int(benchmark["p95_usec"]) >= P95_LIMIT_USEC:
		_fail("Stage 13 shipping generation exceeded 1.0 ms p95: %d usec" % int(benchmark["p95_usec"]))
	var report := {
		"source_model": "Stage 13 shipping cache; three-seed modifier distribution plus physical slope verification from real cached heights",
		"fixed_seeds": FIXED_SEEDS,
		"audit_extent_blocks_per_seed": AUDIT_CHUNK_RADIUS * 2 * CHUNK_SIZE,
		"columns_scanned_per_seed": AUDIT_CHUNK_RADIUS * 2 * CHUNK_SIZE * AUDIT_CHUNK_RADIUS * 2 * CHUNK_SIZE,
		"shared_flat_terrain_max": DATA.STAGE13_FLAT_TERRAIN_MAX,
		"compat_hill_min_alias": DATA.STAGE13_HILL_STRUCTURE_MIN,
		"world_height": DATA.OVERHAUL_WORLD_HEIGHT,
		"per_seed": per_seed,
		"aggregate": aggregate_report,
		"screenshot_x83_z56": screenshot,
		"benchmark": benchmark,
		"generation_p95_limit_usec": P95_LIMIT_USEC,
		"failures": failures,
	}
	print("PLAINS_OPEN_TERRAIN_GATE_JSON=" + JSON.stringify(report))
	if failures.is_empty():
		print("PLAINS_OPEN_TERRAIN_GATE_PASS")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func _new_accumulator() -> Dictionary:
	var slope_histogram: Array[int] = []
	var interior_slope_histogram: Array[int] = []
	for _index in range(DATA.OVERHAUL_WORLD_HEIGHT + 1):
		slope_histogram.append(0)
		interior_slope_histogram.append(0)
	return {
		"land": 0,
		"plains": 0,
		"modifiers": [0, 0, 0, 0, 0],
		"plains_modifiers": [0, 0, 0, 0, 0],
		"direct_modifier_mismatches": 0,
		"direct_height_samples": 0,
		"direct_height_mismatches": 0,
		"none_columns": 0,
		"none_slope_histogram": slope_histogram,
		"none_max_slope": 0,
		"interior_none_columns": 0,
		"interior_none_slope_histogram": interior_slope_histogram,
		"interior_none_max_slope": 0,
	}


func _audit_seed(seed_value: int) -> Dictionary:
	var sampler = AUDIT_DATA.new()
	sampler.configure_audit_seed(seed_value)
	var acc := _new_accumulator()
	for chunk_z in range(-AUDIT_CHUNK_RADIUS, AUDIT_CHUNK_RADIUS):
		for chunk_x in range(-AUDIT_CHUNK_RADIUS, AUDIT_CHUNK_RADIUS):
			var coord := Vector2i(chunk_x, chunk_z)
			var cache: Dictionary = CACHE.build(coord, sampler)
			var fields: PackedFloat32Array = cache["world_fields"]
			var heights: PackedInt32Array = cache["heights"]
			var biomes: PackedByteArray = cache["biomes"]
			var waters: PackedByteArray = cache["stage7_water_types"]
			var modifiers: PackedByteArray = cache["stage9_terrain_modifiers"]
			for local_z in range(CHUNK_SIZE):
				var cache_z := local_z + PADDING
				for local_x in range(CHUNK_SIZE):
					var cache_x := local_x + PADDING
					var index := cache_z * WIDTH + cache_x
					if int(waters[index]) != sampler.WATER_NONE:
						continue
					var field := index * FIELD_STRIDE
					var continentalness := float(fields[field])
					var structure := float(fields[field + 1])
					var modifier := int(modifiers[index])
					var direct_modifier := sampler.stage9_terrain_modifier_from_fields(
						continentalness, structure, sampler.WATER_NONE
					)
					if direct_modifier != modifier:
						acc["direct_modifier_mismatches"] = int(acc["direct_modifier_mismatches"]) + 1
					var modifier_counts: Array = acc["modifiers"]
					modifier_counts[modifier] = int(modifier_counts[modifier]) + 1
					acc["land"] = int(acc["land"]) + 1
					if int(biomes[index]) == sampler.BIOME_PLAINS:
						var plains_counts: Array = acc["plains_modifiers"]
						plains_counts[modifier] = int(plains_counts[modifier]) + 1
						acc["plains"] = int(acc["plains"]) + 1

					var world_x := chunk_x * CHUNK_SIZE + local_x
					var world_z := chunk_z * CHUNK_SIZE + local_z
					if posmod((world_x * 31) ^ (world_z * 17), 97) == 0:
						acc["direct_height_samples"] = int(acc["direct_height_samples"]) + 1
						if int(heights[index]) != int(sampler.terrain_height(world_x, world_z)):
							acc["direct_height_mismatches"] = int(acc["direct_height_mismatches"]) + 1

					if modifier != sampler.TERRAIN_MODIFIER_NONE:
						continue
					var center_height := int(heights[index])
					var slope := 0
					slope = maxi(slope, absi(int(heights[index - 1]) - center_height))
					slope = maxi(slope, absi(int(heights[index + 1]) - center_height))
					slope = maxi(slope, absi(int(heights[index - WIDTH]) - center_height))
					slope = maxi(slope, absi(int(heights[index + WIDTH]) - center_height))
					slope = clampi(slope, 0, DATA.OVERHAUL_WORLD_HEIGHT)
					acc["none_columns"] = int(acc["none_columns"]) + 1
					var slope_hist: Array = acc["none_slope_histogram"]
					slope_hist[slope] = int(slope_hist[slope]) + 1
					acc["none_max_slope"] = maxi(int(acc["none_max_slope"]), slope)
					var touches_water: bool = (
						int(waters[index - 1]) != sampler.WATER_NONE
						or int(waters[index + 1]) != sampler.WATER_NONE
						or int(waters[index - WIDTH]) != sampler.WATER_NONE
						or int(waters[index + WIDTH]) != sampler.WATER_NONE
					)
					if not touches_water:
						acc["interior_none_columns"] = int(acc["interior_none_columns"]) + 1
						var interior_hist: Array = acc["interior_none_slope_histogram"]
						interior_hist[slope] = int(interior_hist[slope]) + 1
						acc["interior_none_max_slope"] = maxi(int(acc["interior_none_max_slope"]), slope)
	return acc


func _merge(target: Dictionary, source: Dictionary) -> void:
	for key in ["land", "plains", "direct_modifier_mismatches", "direct_height_samples", "direct_height_mismatches", "none_columns", "interior_none_columns"]:
		target[key] = int(target[key]) + int(source[key])
	for key in ["none_max_slope", "interior_none_max_slope"]:
		target[key] = maxi(int(target[key]), int(source[key]))
	for key in ["modifiers", "plains_modifiers", "none_slope_histogram", "interior_none_slope_histogram"]:
		var target_values: Array = target[key]
		var source_values: Array = source[key]
		for index in range(target_values.size()):
			target_values[index] = int(target_values[index]) + int(source_values[index])


func _summarize(acc: Dictionary) -> Dictionary:
	var land := int(acc["land"])
	var plains := int(acc["plains"])
	var none_columns := int(acc["none_columns"])
	var interior_none := int(acc["interior_none_columns"])
	return {
		"land_columns": land,
		"plains_columns": plains,
		"plains_percent_of_land": _pct(plains, land),
		"global_modifier_percent": _mods(acc["modifiers"], land),
		"plains_modifier_percent": _mods(acc["plains_modifiers"], plains),
		"direct_modifier_mismatches": int(acc["direct_modifier_mismatches"]),
		"direct_height_samples": int(acc["direct_height_samples"]),
		"direct_height_mismatches": int(acc["direct_height_mismatches"]),
		"none_columns": none_columns,
		"none_slope_zero_percent": _hist_percent_at(acc["none_slope_histogram"], 0, none_columns),
		"none_slope_le1_percent": _hist_percent_through(acc["none_slope_histogram"], 1, none_columns),
		"none_slope_p95": _hist_percentile(acc["none_slope_histogram"], none_columns, 0.95),
		"none_max_slope": int(acc["none_max_slope"]),
		"interior_none_columns": interior_none,
		"interior_none_slope_zero_percent": _hist_percent_at(acc["interior_none_slope_histogram"], 0, interior_none),
		"interior_none_slope_le1_percent": _hist_percent_through(acc["interior_none_slope_histogram"], 1, interior_none),
		"interior_none_slope_p95": _hist_percentile(acc["interior_none_slope_histogram"], interior_none, 0.95),
		"interior_none_max_slope": int(acc["interior_none_max_slope"]),
	}


func _screenshot_report(sampler) -> Dictionary:
	var coord := Vector2i(
		floori(float(SCREENSHOT_CENTER.x) / float(CHUNK_SIZE)),
		floori(float(SCREENSHOT_CENTER.y) / float(CHUNK_SIZE))
	)
	var cache: Dictionary = CACHE.build(coord, sampler)
	var local_x := SCREENSHOT_CENTER.x - coord.x * CHUNK_SIZE
	var local_z := SCREENSHOT_CENTER.y - coord.y * CHUNK_SIZE
	var index := (local_z + PADDING) * WIDTH + (local_x + PADDING)
	var heights: PackedInt32Array = cache["heights"]
	var fields: PackedFloat32Array = cache["world_fields"]
	var waters: PackedByteArray = cache["stage7_water_types"]
	var modifiers: PackedByteArray = cache["stage9_terrain_modifiers"]
	var center_height := int(heights[index])
	var center_slope := 0
	center_slope = maxi(center_slope, absi(int(heights[index - 1]) - center_height))
	center_slope = maxi(center_slope, absi(int(heights[index + 1]) - center_height))
	center_slope = maxi(center_slope, absi(int(heights[index - WIDTH]) - center_height))
	center_slope = maxi(center_slope, absi(int(heights[index + WIDTH]) - center_height))

	var local_min := 2147483647
	var local_max := -2147483648
	for pixel_z in range(-SCREENSHOT_MAP_HALF_PIXELS, SCREENSHOT_MAP_HALF_PIXELS + 1):
		for pixel_x in range(-SCREENSHOT_MAP_HALF_PIXELS, SCREENSHOT_MAP_HALF_PIXELS + 1):
			var x := SCREENSHOT_CENTER.x + pixel_x * SCREENSHOT_MAP_SPACING
			var z := SCREENSHOT_CENTER.y + pixel_z * SCREENSHOT_MAP_SPACING
			if sampler.water_info_at(x, z).x != sampler.WATER_NONE:
				continue
			var height := int(sampler.terrain_height(x, z))
			local_min = mini(local_min, height)
			local_max = maxi(local_max, height)
	if local_min > local_max:
		local_min = sampler.SEA_LEVEL
		local_max = sampler.SEA_LEVEL
	var local_low_shade := MAP.local_elevation_shade(local_min, local_min, local_max)
	var local_high_shade := MAP.local_elevation_shade(local_max, local_min, local_max)
	var legal_span := maxf(1.0, float(sampler.OVERHAUL_WORLD_HEIGHT - sampler.SEA_LEVEL - 1))
	var legacy_low := lerpf(0.82, 1.14, clampf(float(local_min - sampler.SEA_LEVEL) / legal_span, 0.0, 1.0))
	var legacy_high := lerpf(0.82, 1.14, clampf(float(local_max - sampler.SEA_LEVEL) / legal_span, 0.0, 1.0))
	return {
		"coord": SCREENSHOT_CENTER,
		"chunk": coord,
		"direct_height": int(sampler.terrain_height(SCREENSHOT_CENTER.x, SCREENSHOT_CENTER.y)),
		"cache_height": center_height,
		"cache_water_type": int(waters[index]),
		"modifier": sampler.terrain_modifier_name(int(modifiers[index])),
		"terrain_structure": float(fields[index * FIELD_STRIDE + 1]),
		"cached_local_slope": center_slope,
		"map_dry_height_min": local_min,
		"map_dry_height_max": local_max,
		"map_dry_height_range": local_max - local_min,
		"legacy_world_ceiling_elevation_shade_span": legacy_high - legacy_low,
		"new_local_elevation_shade_span": local_high_shade - local_low_shade,
		"local_vs_legacy_shade_span_ratio": (local_high_shade - local_low_shade) / maxf(0.000001, legacy_high - legacy_low),
	}


func _gate_contract(report: Dictionary, aggregate: Dictionary, screenshot: Dictionary) -> void:
	if int(DATA.OVERHAUL_WORLD_HEIGHT) != 150:
		_fail("World height changed; expected 150, got %d" % int(DATA.OVERHAUL_WORLD_HEIGHT))
	if absf(float(DATA.STAGE13_HILL_STRUCTURE_MIN) - float(DATA.STAGE13_FLAT_TERRAIN_MAX)) > 0.000001:
		_fail("Modifier and physical flat boundaries are no longer aliases")
	var sampler = DATA.new()
	if sampler.stage9_terrain_modifier_from_fields(0.2, DATA.STAGE13_FLAT_TERRAIN_MAX, sampler.WATER_NONE) != sampler.TERRAIN_MODIFIER_NONE:
		_fail("Exact shared boundary must still classify as none")
	if sampler.stage9_terrain_modifier_from_fields(0.2, DATA.STAGE13_FLAT_TERRAIN_MAX + 0.0001, sampler.WATER_NONE) != sampler.TERRAIN_MODIFIER_HILL:
		_fail("Terrain immediately above shared boundary must classify as hill")
	if int(report["direct_modifier_mismatches"]) != 0:
		_fail("Stage 13 direct/cache modifier mismatch count: %d" % int(report["direct_modifier_mismatches"]))
	if int(report["direct_height_mismatches"]) != 0:
		_fail("Stage 13 sampled direct/cache height mismatch count: %d/%d" % [int(report["direct_height_mismatches"]), int(report["direct_height_samples"])])
	var global_mods: Dictionary = report["global_modifier_percent"]
	var plains_mods: Dictionary = report["plains_modifier_percent"]
	if not _between(float(global_mods["none"]), 35.0, 45.0):
		_fail("Global none share missed 35-45%% target: %.3f%%" % float(global_mods["none"]))
	if not _between(float(plains_mods["none"]), 35.0, 50.0):
		_fail("Plains none share missed 35-50%% target: %.3f%%" % float(plains_mods["none"]))
	if float(report["interior_none_slope_p95"]) > 1.0:
		_fail("Interior none terrain is not physically near-flat; slope p95 %.1f" % float(report["interior_none_slope_p95"]))
	if float(report["interior_none_slope_le1_percent"]) < 95.0:
		_fail("Fewer than 95%% of interior none columns have local slope <=1: %.3f%%" % float(report["interior_none_slope_le1_percent"]))
	if float(report["none_slope_p95"]) > 2.0:
		_fail("All dry none terrain slope p95 exceeded hydrology-edge allowance: %.1f" % float(report["none_slope_p95"]))
	if int(screenshot["direct_height"]) != int(screenshot["cache_height"]):
		_fail("X83 Z56 direct/cache height mismatch: %d vs %d" % [int(screenshot["direct_height"]), int(screenshot["cache_height"])])
	if String(screenshot["modifier"]) != "none":
		_fail("X83 Z56 no longer classifies as none: %s" % String(screenshot["modifier"]))
	if int(screenshot["cached_local_slope"]) > 1:
		_fail("X83 Z56 is not physically flat in cached height data: slope %d" % int(screenshot["cached_local_slope"]))
	if float(screenshot["new_local_elevation_shade_span"]) <= float(screenshot["legacy_world_ceiling_elevation_shade_span"]) * 2.0:
		_fail("Local minimap normalization did not at least double elevation contrast")
	if float(screenshot["new_local_elevation_shade_span"]) < 0.15:
		_fail("X83 Z56 minimap local elevation contrast remains too compressed: %.4f" % float(screenshot["new_local_elevation_shade_span"]))
	if int(aggregate["none_columns"]) <= 0 or int(aggregate["interior_none_columns"]) <= 0:
		_fail("Physical none-terrain audit did not scan any eligible columns")


func _benchmark(data) -> Dictionary:
	var coords := [Vector2i(-4,-2),Vector2i(-2,1),Vector2i(0,0),Vector2i(1,0),Vector2i(2,-1),Vector2i(4,2),Vector2i(8,-4),Vector2i(11,-3),Vector2i(12,-2),Vector2i(13,-2),Vector2i(14,-1),Vector2i(15,0),Vector2i(16,1),Vector2i(18,-4),Vector2i(20,2),Vector2i(-8,5)]
	for _warmup in range(WARMUPS):
		for coord in coords:
			CACHE.build(coord, data)
	var times: Array[int] = []
	for repetition in range(REPEATS):
		for index in range(coords.size()):
			var coord: Vector2i = coords[(index + repetition) % coords.size()]
			var started := Time.get_ticks_usec()
			CACHE.build(coord, data)
			times.append(maxi(1, Time.get_ticks_usec() - started))
	times.sort()
	var total := 0
	for value in times:
		total += value
	var p95_index := clampi(ceili(float(times.size()) * 0.95) - 1, 0, times.size() - 1)
	return {
		"sample_count": times.size(),
		"minimum_usec": times[0],
		"maximum_usec": times[times.size() - 1],
		"mean_usec": float(total) / float(times.size()),
		"p95_usec": times[p95_index],
		"p95_ms": float(times[p95_index]) / 1000.0,
		"methodology": "16 padded chunks, 4 warmups, 20 repeats; same 320-sample Stage 13 shipping cache gate",
	}


func _mods(counts_value, total: int) -> Dictionary:
	var counts: Array = counts_value
	var result := {}
	for index in range(5):
		result[MODIFIER_NAMES[index]] = _pct(int(counts[index]), total)
	return result


func _hist_percentile(hist_value, total: int, percentile: float) -> int:
	if total <= 0:
		return 0
	var hist: Array = hist_value
	var target := ceili(float(total) * percentile)
	var cumulative := 0
	for index in range(hist.size()):
		cumulative += int(hist[index])
		if cumulative >= target:
			return index
	return hist.size() - 1


func _hist_percent_at(hist_value, index: int, total: int) -> float:
	if total <= 0:
		return 0.0
	var hist: Array = hist_value
	return _pct(int(hist[index]), total)


func _hist_percent_through(hist_value, max_index: int, total: int) -> float:
	if total <= 0:
		return 0.0
	var hist: Array = hist_value
	var count := 0
	for index in range(mini(max_index, hist.size() - 1) + 1):
		count += int(hist[index])
	return _pct(count, total)


func _between(value: float, minimum: float, maximum: float) -> bool:
	return value >= minimum and value <= maximum


func _pct(value: int, total: int) -> float:
	return float(value) * 100.0 / float(total) if total > 0 else 0.0


func _fail(message: String) -> void:
	if not failures.has(message):
		failures.append(message)