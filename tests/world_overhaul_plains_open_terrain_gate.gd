extends SceneTree

const AUDIT_DATA := preload("res://tests/world_overhaul_stage13_audit_data.gd")
const DATA := preload("res://scripts/world/playable_world_stage13_data.gd")
const CACHE := preload("res://scripts/world/playable_world_stage13_generation_cache_fast.gd")

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

var failures: Array[String] = []


func _init() -> void:
	var aggregate := _new_accumulator()
	var per_seed: Array = []
	for seed_variant in FIXED_SEEDS:
		var raw := _audit_seed(int(seed_variant))
		per_seed.append(_summarize(raw))
		_merge(aggregate, raw)
	var aggregate_report := _summarize(aggregate)
	var benchmark := _benchmark(DATA.new())
	_gate_contract(aggregate_report, aggregate)
	if int(benchmark["p95_usec"]) >= P95_LIMIT_USEC:
		_fail("Stage 13 shipping generation exceeded 1.0 ms p95: %d usec" % int(benchmark["p95_usec"]))
	var report := {
		"source_model": "Stage 13 shipping cache; exact legacy hill-threshold counterfactual on the same scanned columns",
		"fixed_seeds": FIXED_SEEDS,
		"audit_extent_blocks_per_seed": AUDIT_CHUNK_RADIUS * 2 * CHUNK_SIZE,
		"columns_scanned_per_seed": AUDIT_CHUNK_RADIUS * 2 * CHUNK_SIZE * AUDIT_CHUNK_RADIUS * 2 * CHUNK_SIZE,
		"legacy_hill_structure_min": DATA.STAGE13_LEGACY_HILL_STRUCTURE_MIN,
		"new_hill_structure_min": DATA.STAGE13_HILL_STRUCTURE_MIN,
		"world_height": DATA.OVERHAUL_WORLD_HEIGHT,
		"per_seed": per_seed,
		"aggregate": aggregate_report,
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
	return {
		"land": 0,
		"plains": 0,
		"before": [0, 0, 0, 0, 0],
		"after": [0, 0, 0, 0, 0],
		"plains_before": [0, 0, 0, 0, 0],
		"plains_after": [0, 0, 0, 0, 0],
		"direct_cache_mismatches": 0,
	}


func _audit_seed(seed_value: int) -> Dictionary:
	var sampler = AUDIT_DATA.new()
	sampler.configure_audit_seed(seed_value)
	var acc := _new_accumulator()
	for chunk_z in range(-AUDIT_CHUNK_RADIUS, AUDIT_CHUNK_RADIUS):
		for chunk_x in range(-AUDIT_CHUNK_RADIUS, AUDIT_CHUNK_RADIUS):
			var cache: Dictionary = CACHE.build(Vector2i(chunk_x, chunk_z), sampler)
			var fields: PackedFloat32Array = cache["world_fields"]
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
					var before_modifier := _legacy_modifier(sampler, continentalness, structure)
					var after_modifier := int(modifiers[index])
					var direct_modifier := sampler.stage9_terrain_modifier_from_fields(
						continentalness, structure, sampler.WATER_NONE
					)
					if direct_modifier != after_modifier:
						acc["direct_cache_mismatches"] = int(acc["direct_cache_mismatches"]) + 1
					var before_counts: Array = acc["before"]
					var after_counts: Array = acc["after"]
					acc["land"] = int(acc["land"]) + 1
					before_counts[before_modifier] = int(before_counts[before_modifier]) + 1
					after_counts[after_modifier] = int(after_counts[after_modifier]) + 1
					if int(biomes[index]) != sampler.BIOME_PLAINS:
						continue
					var plains_before: Array = acc["plains_before"]
					var plains_after: Array = acc["plains_after"]
					acc["plains"] = int(acc["plains"]) + 1
					plains_before[before_modifier] = int(plains_before[before_modifier]) + 1
					plains_after[after_modifier] = int(plains_after[after_modifier]) + 1
	return acc


func _legacy_modifier(sampler, continentalness: float, structure: float) -> int:
	if structure >= sampler.STAGE9_MOUNTAIN_STRUCTURE_MIN:
		if sampler.stage9_valley_strength(continentalness, structure) >= sampler.STAGE9_VALLEY_STRENGTH_MIN:
			return sampler.TERRAIN_MODIFIER_VALLEY
		return sampler.TERRAIN_MODIFIER_MOUNTAIN
	if structure >= sampler.STAGE9_PLATEAU_STRUCTURE_MIN:
		return sampler.TERRAIN_MODIFIER_PLATEAU
	if structure >= sampler.STAGE13_LEGACY_HILL_STRUCTURE_MIN:
		return sampler.TERRAIN_MODIFIER_HILL
	return sampler.TERRAIN_MODIFIER_NONE


func _merge(target: Dictionary, source: Dictionary) -> void:
	target["land"] = int(target["land"]) + int(source["land"])
	target["plains"] = int(target["plains"]) + int(source["plains"])
	target["direct_cache_mismatches"] = int(target["direct_cache_mismatches"]) + int(source["direct_cache_mismatches"])
	for key in ["before", "after", "plains_before", "plains_after"]:
		var target_counts: Array = target[key]
		var source_counts: Array = source[key]
		for index in range(5):
			target_counts[index] = int(target_counts[index]) + int(source_counts[index])


func _summarize(acc: Dictionary) -> Dictionary:
	var land := int(acc["land"])
	var plains := int(acc["plains"])
	var before: Array = acc["before"]
	var after: Array = acc["after"]
	var plains_before: Array = acc["plains_before"]
	var plains_after: Array = acc["plains_after"]
	return {
		"land_columns": land,
		"plains_columns": plains,
		"plains_percent_of_land": _pct(plains, land),
		"before_global_percent": _mods(before, land),
		"after_global_percent": _mods(after, land),
		"before_plains_percent": _mods(plains_before, plains),
		"after_plains_percent": _mods(plains_after, plains),
		"global_reclassified_hill_to_none_columns": int(after[0]) - int(before[0]),
		"plains_reclassified_hill_to_none_columns": int(plains_after[0]) - int(plains_before[0]),
		"direct_cache_mismatches": int(acc["direct_cache_mismatches"]),
	}


func _mods(counts: Array, total: int) -> Dictionary:
	var result := {}
	for index in range(5):
		result[MODIFIER_NAMES[index]] = _pct(int(counts[index]), total)
	return result


func _gate_contract(report: Dictionary, aggregate: Dictionary) -> void:
	if int(DATA.OVERHAUL_WORLD_HEIGHT) != 150:
		_fail("World height changed; expected 150, got %d" % int(DATA.OVERHAUL_WORLD_HEIGHT))
	if absf(float(CACHE.HILL_START) - float(DATA.STAGE13_HILL_STRUCTURE_MIN)) > 0.000001:
		_fail("Stage 13 direct and fast-cache hill thresholds diverged")
	if absf(float(DATA.STAGE13_LEGACY_HILL_STRUCTURE_MIN) - (-0.28)) > 0.000001:
		_fail("Legacy hill threshold no longer matches the diagnosed -0.28 baseline")
	if int(report["direct_cache_mismatches"]) != 0:
		_fail("Stage 13 direct/cache modifier mismatch count: %d" % int(report["direct_cache_mismatches"]))
	var before_global: Dictionary = report["before_global_percent"]
	var after_global: Dictionary = report["after_global_percent"]
	var before_plains: Dictionary = report["before_plains_percent"]
	var after_plains: Dictionary = report["after_plains_percent"]
	if not _between(float(before_global["none"]), 21.5, 22.5):
		_fail("Legacy global none share no longer reproduces diagnosis: %.3f%%" % float(before_global["none"]))
	if not _between(float(before_global["hill"]), 51.3, 52.5):
		_fail("Legacy global hill share no longer reproduces diagnosis: %.3f%%" % float(before_global["hill"]))
	if not _between(float(before_plains["none"]), 23.2, 24.4):
		_fail("Legacy Plains none share no longer reproduces diagnosis: %.3f%%" % float(before_plains["none"]))
	if not _between(float(before_plains["hill"]), 52.7, 53.9):
		_fail("Legacy Plains hill share no longer reproduces diagnosis: %.3f%%" % float(before_plains["hill"]))
	if not _between(float(after_global["none"]), 35.0, 45.0):
		_fail("New global none share missed 35-45%% target: %.3f%%" % float(after_global["none"]))
	if not _between(float(after_plains["none"]), 35.0, 45.0):
		_fail("New Plains none share missed 35-45%% target: %.3f%%" % float(after_plains["none"]))
	if float(after_global["hill"]) >= float(before_global["hill"]):
		_fail("Global hill share did not decrease")
	if float(after_plains["hill"]) >= float(before_plains["hill"]):
		_fail("Plains hill share did not decrease")
	var before: Array = aggregate["before"]
	var after: Array = aggregate["after"]
	var plains_before: Array = aggregate["plains_before"]
	var plains_after: Array = aggregate["plains_after"]
	for modifier in [2, 3, 4]:
		if int(before[modifier]) != int(after[modifier]):
			_fail("Global %s count changed; reduction must come from hill" % MODIFIER_NAMES[modifier])
		if int(plains_before[modifier]) != int(plains_after[modifier]):
			_fail("Plains %s count changed; reduction must come from hill" % MODIFIER_NAMES[modifier])
	var global_none_gain := int(after[0]) - int(before[0])
	var global_hill_loss := int(before[1]) - int(after[1])
	var plains_none_gain := int(plains_after[0]) - int(plains_before[0])
	var plains_hill_loss := int(plains_before[1]) - int(plains_after[1])
	if global_none_gain <= 0 or global_none_gain != global_hill_loss:
		_fail("Global distribution did not transfer exactly from hill to none")
	if plains_none_gain <= 0 or plains_none_gain != plains_hill_loss:
		_fail("Plains distribution did not transfer exactly from hill to none")


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


func _between(value: float, minimum: float, maximum: float) -> bool:
	return value >= minimum and value <= maximum


func _pct(value: int, total: int) -> float:
	return float(value) * 100.0 / float(total) if total > 0 else 0.0


func _fail(message: String) -> void:
	if not failures.has(message):
		failures.append(message)
