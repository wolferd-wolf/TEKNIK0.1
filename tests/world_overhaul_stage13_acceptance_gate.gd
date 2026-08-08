extends SceneTree

const AUDIT_DATA := preload("res://tests/world_overhaul_stage13_audit_data.gd")
const SHIPPING_DATA := preload("res://scripts/world/playable_world_stage11_water_biome_data.gd")
const GENERATION_CACHE := preload("res://scripts/world/playable_world_stage10_generation_cache_fast.gd")

const CHUNK_SIZE := 12
const PADDING := 2
const CACHE_WIDTH := CHUNK_SIZE + PADDING * 2
const FIELD_STRIDE := 6
const AUDIT_CHUNK_RADIUS := 48
const REGION_SAMPLE_STEP := 4
const MAP_SIZE := 192
const MAP_STEP := 4
const MAP_ORIGIN := Vector2i(-384, -384)
const FIXED_SEEDS := [734921, 19088743, 11235813]
const COMMON_BIOME_MIN_PERCENT := 1.0

var failures: Array[String] = []


func _init() -> void:
	var report := {
		"fixed_seeds": FIXED_SEEDS,
		"audit_extent_blocks": AUDIT_CHUNK_RADIUS * 2 * CHUNK_SIZE,
		"region_sample_step": REGION_SAMPLE_STEP,
		"shipping_seed_equivalence": {},
		"seeds": [],
		"aggregate": {},
		"maps": [],
		"failures": failures,
	}

	report["shipping_seed_equivalence"] = _check_shipping_seed_equivalence()
	var aggregate_counts: Dictionary = {}
	var aggregate_land := 0
	var aggregate_total := 0
	var aggregate_ocean := 0
	var aggregate_river := 0
	var aggregate_lakes := 0
	var aggregate_mountains := 0

	for seed_value in FIXED_SEEDS:
		var seed_report: Dictionary = _audit_seed(int(seed_value))
		report["seeds"].append(seed_report)
		aggregate_land += int(seed_report.get("land_columns", 0))
		aggregate_total += int(seed_report.get("sampled_columns", 0))
		aggregate_ocean += int(seed_report.get("ocean_columns", 0))
		aggregate_river += int(seed_report.get("river_columns", 0))
		aggregate_lakes += int(seed_report.get("lake_count", 0))
		aggregate_mountains += int(seed_report.get("mountain_columns", 0))
		var counts: Dictionary = seed_report.get("biome_counts", {})
		for name in counts.keys():
			aggregate_counts[name] = int(aggregate_counts.get(name, 0)) + int(counts[name])

	var aggregate_biome_percent: Dictionary = {}
	for name in aggregate_counts.keys():
		aggregate_biome_percent[name] = _percent(int(aggregate_counts[name]), aggregate_land)

	report["aggregate"] = {
		"sampled_columns": aggregate_total,
		"land_columns": aggregate_land,
		"biome_counts": aggregate_counts,
		"biome_percent_of_land": aggregate_biome_percent,
		"ocean_percent": _percent(aggregate_ocean, aggregate_total),
		"river_percent": _percent(aggregate_river, aggregate_total),
		"lake_count": aggregate_lakes,
		"mountain_percent_of_land": _percent(aggregate_mountains, aggregate_land),
	}

	_check_common_biome_coverage(aggregate_biome_percent)
	if aggregate_ocean <= 0:
		_fail("Statistical audit found no ocean columns")
	if aggregate_river <= 0:
		_fail("Statistical audit found no river columns")
	if aggregate_lakes <= 0:
		_fail("Statistical audit found no accepted lakes")

	report["maps"] = _generate_diagnostic_maps()
	_write_report(report)
	var json := JSON.stringify(report)
	print("WORLD_OVERHAUL_STAGE13_JSON=" + json)
	if failures.is_empty():
		print("WORLD_OVERHAUL_STAGE13_PASS")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func _check_shipping_seed_equivalence() -> Dictionary:
	var shipping = SHIPPING_DATA.new()
	var audit = AUDIT_DATA.new()
	audit.configure_audit_seed(audit.WORLD_SEED)
	var chunks := [Vector2i(-7, -5), Vector2i(0, 0), Vector2i(11, -9), Vector2i(23, 17)]
	var arrays_compared := 0
	for coord in chunks:
		var expected: Dictionary = GENERATION_CACHE.build(coord, shipping)
		var actual: Dictionary = GENERATION_CACHE.build(coord, audit)
		for key in ["world_fields", "heights", "biomes", "stage7_water_types", "stage9_terrain_modifiers"]:
			arrays_compared += 1
			if expected.get(key) != actual.get(key):
				_fail("Diagnostic seed adapter changed shipping output for %s at %s" % [key, coord])
	return {
		"chunks": chunks.size(),
		"arrays_compared": arrays_compared,
		"seed": audit.WORLD_SEED,
	}


func _audit_seed(seed_value: int) -> Dictionary:
	var sampler = AUDIT_DATA.new()
	sampler.configure_audit_seed(seed_value)
	var deterministic_a: Dictionary = GENERATION_CACHE.build(Vector2i(7, -11), sampler)
	var deterministic_b: Dictionary = GENERATION_CACHE.build(Vector2i(7, -11), sampler)
	for key in ["world_fields", "heights", "biomes", "stage7_water_types", "stage9_terrain_modifiers"]:
		if deterministic_a.get(key) != deterministic_b.get(key):
			_fail("Seed %d is not deterministic for %s" % [seed_value, key])

	var world_min := -AUDIT_CHUNK_RADIUS * CHUNK_SIZE
	var world_max := AUDIT_CHUNK_RADIUS * CHUNK_SIZE - 1
	var region_width := int((world_max - world_min + 1) / REGION_SAMPLE_STEP)
	var region_grid := PackedInt32Array()
	region_grid.resize(region_width * region_width)
	region_grid.fill(-1)

	var biome_counts: Dictionary = {}
	for biome_id in [sampler.BIOME_PLAINS, sampler.BIOME_FOREST, sampler.BIOME_DESERT, sampler.BIOME_DENSE_FOREST, sampler.BIOME_DRY_GRASSLAND, sampler.BIOME_COLD_FOREST]:
		biome_counts[sampler.biome_name(biome_id)] = 0

	var height_hist := PackedInt32Array()
	height_hist.resize(15)
	var slope_hist := PackedInt32Array()
	slope_hist.resize(6)
	var sampled_columns := 0
	var land_columns := 0
	var ocean_columns := 0
	var river_columns := 0
	var lake_columns := 0
	var pond_columns := 0
	var mountain_columns := 0
	var water_validation_counts := [0, 0, 0, 0, 0]

	for chunk_z in range(-AUDIT_CHUNK_RADIUS, AUDIT_CHUNK_RADIUS):
		for chunk_x in range(-AUDIT_CHUNK_RADIUS, AUDIT_CHUNK_RADIUS):
			var coord := Vector2i(chunk_x, chunk_z)
			var cache: Dictionary = GENERATION_CACHE.build(coord, sampler)
			var heights: PackedInt32Array = cache["heights"]
			var biomes: PackedByteArray = cache["biomes"]
			var waters: PackedByteArray = cache["stage7_water_types"]
			var modifiers: PackedByteArray = cache["stage9_terrain_modifiers"]
			for local_z in range(CHUNK_SIZE):
				var cache_z := local_z + PADDING
				var world_z := chunk_z * CHUNK_SIZE + local_z
				for local_x in range(CHUNK_SIZE):
					var cache_x := local_x + PADDING
					var world_x := chunk_x * CHUNK_SIZE + local_x
					var index := cache_z * CACHE_WIDTH + cache_x
					var height := int(heights[index])
					var water := int(waters[index])
					var biome := int(biomes[index])
					var modifier := int(modifiers[index])
					sampled_columns += 1
					if height < 3 or height >= sampler.OVERHAUL_WORLD_HEIGHT:
						_fail("Seed %d produced invalid terrain height %d at (%d,%d)" % [seed_value, height, world_x, world_z])
					height_hist[mini(height / 10, 14)] += 1
					var slope := 0
					slope = maxi(slope, absi(int(heights[index - 1]) - height))
					slope = maxi(slope, absi(int(heights[index + 1]) - height))
					slope = maxi(slope, absi(int(heights[index - CACHE_WIDTH]) - height))
					slope = maxi(slope, absi(int(heights[index + CACHE_WIDTH]) - height))
					slope_hist[mini(slope, 5)] += 1

					match water:
						sampler.WATER_OCEAN:
							ocean_columns += 1
						sampler.WATER_RIVER:
							river_columns += 1
						sampler.WATER_LAKE:
							lake_columns += 1
						sampler.WATER_POND:
							pond_columns += 1
						_:
							land_columns += 1
							var biome_name: String = sampler.biome_name(biome)
							biome_counts[biome_name] = int(biome_counts.get(biome_name, 0)) + 1
							if modifier == sampler.TERRAIN_MODIFIER_MOUNTAIN:
								mountain_columns += 1

					if water != sampler.WATER_NONE and water >= 0 and water < water_validation_counts.size() and water_validation_counts[water] < 12:
						var info: Vector2i = sampler.water_info_at(world_x, world_z)
						water_validation_counts[water] += 1
						if info.x != water:
							_fail("Seed %d cache/direct water type mismatch at (%d,%d)" % [seed_value, world_x, world_z])
						if info.y <= height or info.y >= sampler.OVERHAUL_WORLD_HEIGHT:
							_fail("Seed %d produced invalid water level %d over terrain %d at (%d,%d)" % [seed_value, info.y, height, world_x, world_z])

					if posmod(world_x - world_min, REGION_SAMPLE_STEP) == 0 and posmod(world_z - world_min, REGION_SAMPLE_STEP) == 0:
						var gx := int((world_x - world_min) / REGION_SAMPLE_STEP)
						var gz := int((world_z - world_min) / REGION_SAMPLE_STEP)
						if gx >= 0 and gx < region_width and gz >= 0 and gz < region_width:
							region_grid[gz * region_width + gx] = biome if water == sampler.WATER_NONE else -1

	var lake_count := _count_lakes(sampler, world_min, world_max)
	var pond_count := _count_ponds(sampler, world_min, world_max)
	var biome_percent: Dictionary = {}
	for name in biome_counts.keys():
		biome_percent[name] = _percent(int(biome_counts[name]), land_columns)

	return {
		"seed": seed_value,
		"sampled_columns": sampled_columns,
		"land_columns": land_columns,
		"biome_counts": biome_counts,
		"biome_percent_of_land": biome_percent,
		"region_sizes": _region_stats(region_grid, region_width, sampler),
		"terrain_height_histogram": _height_histogram_dict(height_hist),
		"slope_histogram": _slope_histogram_dict(slope_hist),
		"ocean_columns": ocean_columns,
		"ocean_percent": _percent(ocean_columns, sampled_columns),
		"river_columns": river_columns,
		"river_percent": _percent(river_columns, sampled_columns),
		"lake_columns": lake_columns,
		"pond_columns": pond_columns,
		"lake_count": lake_count,
		"pond_count": pond_count,
		"mountain_columns": mountain_columns,
		"mountain_percent_of_land": _percent(mountain_columns, land_columns),
		"water_validation_counts": water_validation_counts,
	}


func _count_lakes(sampler, world_min: int, world_max: int) -> int:
	var spacing: int = sampler.STAGE6_LAKE_CELL_SPACING
	var min_cell := floori(float(world_min) / float(spacing)) - 1
	var max_cell := floori(float(world_max) / float(spacing)) + 1
	var count := 0
	for cell_z in range(min_cell, max_cell + 1):
		for cell_x in range(min_cell, max_cell + 1):
			var feature: Dictionary = sampler.stage6_lake_candidate(cell_x, cell_z)
			if feature.is_empty():
				continue
			var x := int(feature["center_x"])
			var z := int(feature["center_z"])
			if x >= world_min and x <= world_max and z >= world_min and z <= world_max:
				count += 1
	return count


func _count_ponds(sampler, world_min: int, world_max: int) -> int:
	var spacing: int = sampler.STAGE6_POND_CELL_SPACING
	var min_cell := floori(float(world_min) / float(spacing)) - 1
	var max_cell := floori(float(world_max) / float(spacing)) + 1
	var count := 0
	for cell_z in range(min_cell, max_cell + 1):
		for cell_x in range(min_cell, max_cell + 1):
			var feature: Dictionary = sampler.stage6_pond_candidate(cell_x, cell_z)
			if feature.is_empty():
				continue
			var x := int(feature["center_x"])
			var z := int(feature["center_z"])
			if x >= world_min and x <= world_max and z >= world_min and z <= world_max:
				count += 1
	return count


func _region_stats(grid: PackedInt32Array, width: int, sampler) -> Dictionary:
	var visited := PackedByteArray()
	visited.resize(grid.size())
	var sizes_by_biome: Dictionary = {}
	for index in range(grid.size()):
		if visited[index] != 0 or grid[index] < 0:
			continue
		var biome := int(grid[index])
		var queue := PackedInt32Array()
		queue.append(index)
		visited[index] = 1
		var qpos := 0
		var component_size := 0
		while qpos < queue.size():
			var current := int(queue[qpos])
			qpos += 1
			component_size += 1
			var x := current % width
			var z := int(current / width)
			if x > 0:
				_region_push_neighbor(current - 1, biome, grid, visited, queue)
			if x + 1 < width:
				_region_push_neighbor(current + 1, biome, grid, visited, queue)
			if z > 0:
				_region_push_neighbor(current - width, biome, grid, visited, queue)
			if z + 1 < width:
				_region_push_neighbor(current + width, biome, grid, visited, queue)
		var name: String = sampler.biome_name(biome)
		if not sizes_by_biome.has(name):
			sizes_by_biome[name] = []
		sizes_by_biome[name].append(component_size)

	var result: Dictionary = {}
	for name in sizes_by_biome.keys():
		var values: Array = sizes_by_biome[name]
		var total := 0
		var maximum := 0
		for value in values:
			total += int(value)
			maximum = maxi(maximum, int(value))
		result[name] = {
			"components": values.size(),
			"mean_sampled_cells": float(total) / float(values.size()),
			"max_sampled_cells": maximum,
			"max_approx_area_blocks2": maximum * REGION_SAMPLE_STEP * REGION_SAMPLE_STEP,
		}
	return result


func _region_push_neighbor(index: int, biome: int, grid: PackedInt32Array, visited: PackedByteArray, queue: PackedInt32Array) -> void:
	if visited[index] != 0 or int(grid[index]) != biome:
		return
	visited[index] = 1
	queue.append(index)


func _height_histogram_dict(hist: PackedInt32Array) -> Dictionary:
	var result: Dictionary = {}
	for i in range(hist.size()):
		result["%d-%d" % [i * 10, i * 10 + 9]] = int(hist[i])
	return result


func _slope_histogram_dict(hist: PackedInt32Array) -> Dictionary:
	return {
		"0": int(hist[0]),
		"1": int(hist[1]),
		"2": int(hist[2]),
		"3": int(hist[3]),
		"4": int(hist[4]),
		"5+": int(hist[5]),
	}


func _check_common_biome_coverage(percentages: Dictionary) -> void:
	for name in ["plains", "forest", "dry_grassland"]:
		var value := float(percentages.get(name, 0.0))
		if value < COMMON_BIOME_MIN_PERCENT:
			_fail("Common biome %s fell below %.2f%% aggregate coverage: %.3f%%" % [name, COMMON_BIOME_MIN_PERCENT, value])
	for name in ["plains", "forest", "desert", "dense_forest", "dry_grassland", "cold_forest"]:
		if float(percentages.get(name, 0.0)) <= 0.0:
			_fail("Active biome %s disappeared from the multi-seed audit" % name)


func _generate_diagnostic_maps() -> Array:
	var sampler = AUDIT_DATA.new()
	sampler.configure_audit_seed(sampler.WORLD_SEED)
	var continental := Image.create(MAP_SIZE, MAP_SIZE, false, Image.FORMAT_RGB8)
	var terrain := Image.create(MAP_SIZE, MAP_SIZE, false, Image.FORMAT_RGB8)
	var mountain := Image.create(MAP_SIZE, MAP_SIZE, false, Image.FORMAT_RGB8)
	var river := Image.create(MAP_SIZE, MAP_SIZE, false, Image.FORMAT_RGB8)
	var water := Image.create(MAP_SIZE, MAP_SIZE, false, Image.FORMAT_RGB8)
	var temperature := Image.create(MAP_SIZE, MAP_SIZE, false, Image.FORMAT_RGB8)
	var moisture := Image.create(MAP_SIZE, MAP_SIZE, false, Image.FORMAT_RGB8)
	var biome := Image.create(MAP_SIZE, MAP_SIZE, false, Image.FORMAT_RGB8)
	var caches: Dictionary = {}

	for py in range(MAP_SIZE):
		var world_z := MAP_ORIGIN.y + py * MAP_STEP
		for px in range(MAP_SIZE):
			var world_x := MAP_ORIGIN.x + px * MAP_STEP
			var sample: Dictionary = _cached_sample(sampler, caches, world_x, world_z)
			var c := float(sample["continentalness"])
			var structure := float(sample["structure"])
			var temp := float(sample["temperature"])
			var moist := float(sample["moisture"])
			var h := int(sample["height"])
			var w := int(sample["water"])
			var b := int(sample["biome"])
			var c01 := clampf((c + 1.0) * 0.5, 0.0, 1.0)
			var h01 := clampf(float(h) / float(sampler.OVERHAUL_WORLD_HEIGHT - 1), 0.0, 1.0)
			var m01 := clampf(sampler.stage7_mountain_strength(structure), 0.0, 1.0)
			var t01 := clampf((temp + 1.0) * 0.5, 0.0, 1.0)
			var wet01 := clampf((moist + 1.0) * 0.5, 0.0, 1.0)
			continental.set_pixel(px, py, Color(c01, c01, c01))
			terrain.set_pixel(px, py, Color(h01, h01, h01))
			mountain.set_pixel(px, py, Color(m01, m01, m01))
			river.set_pixel(px, py, Color(0.1, 0.65, 1.0) if w == sampler.WATER_RIVER else Color(0.03, 0.03, 0.03))
			water.set_pixel(px, py, _water_color(w, sampler))
			temperature.set_pixel(px, py, Color(t01, 0.15, 1.0 - t01))
			moisture.set_pixel(px, py, Color(0.45 * (1.0 - wet01), 0.35 + 0.35 * wet01, wet01))
			biome.set_pixel(px, py, _biome_color(b, w, sampler))

	var out_dir := "res://artifacts/stage13"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))
	var maps := {
		"continentalness": continental,
		"terrain_height": terrain,
		"mountain_strength": mountain,
		"river_mask": river,
		"water_type": water,
		"temperature": temperature,
		"moisture": moisture,
		"final_biome": biome,
	}
	var paths: Array = []
	for name in maps.keys():
		var path := "%s/%s.png" % [out_dir, name]
		var error := maps[name].save_png(path)
		if error != OK:
			_fail("Failed to save Stage 13 diagnostic map %s: %s" % [name, error])
		paths.append(path)
	return paths


func _cached_sample(sampler, caches: Dictionary, x: int, z: int) -> Dictionary:
	var chunk_x := floori(float(x) / float(CHUNK_SIZE))
	var chunk_z := floori(float(z) / float(CHUNK_SIZE))
	var key := "%d:%d" % [chunk_x, chunk_z]
	if not caches.has(key):
		caches[key] = GENERATION_CACHE.build(Vector2i(chunk_x, chunk_z), sampler)
	var cache: Dictionary = caches[key]
	var local_x := x - chunk_x * CHUNK_SIZE + PADDING
	var local_z := z - chunk_z * CHUNK_SIZE + PADDING
	var index := local_z * CACHE_WIDTH + local_x
	var fields: PackedFloat32Array = cache["world_fields"]
	var field := index * FIELD_STRIDE
	return {
		"continentalness": float(fields[field]),
		"structure": float(fields[field + 1]),
		"temperature": float(fields[field + 2]),
		"moisture": float(fields[field + 3]),
		"height": int(cache["heights"][index]),
		"biome": int(cache["biomes"][index]),
		"water": int(cache["stage7_water_types"][index]),
	}


func _water_color(water_type: int, sampler) -> Color:
	match water_type:
		sampler.WATER_OCEAN:
			return Color(0.05, 0.20, 0.85)
		sampler.WATER_RIVER:
			return Color(0.05, 0.75, 1.0)
		sampler.WATER_LAKE:
			return Color(0.10, 0.40, 0.95)
		sampler.WATER_POND:
			return Color(0.20, 0.70, 0.90)
		_:
			return Color(0.12, 0.30, 0.10)


func _biome_color(biome: int, water_type: int, sampler) -> Color:
	if water_type != sampler.WATER_NONE:
		return Color(0.05, 0.15, 0.35)
	match biome:
		sampler.BIOME_PLAINS:
			return Color(0.55, 0.82, 0.32)
		sampler.BIOME_FOREST:
			return Color(0.16, 0.50, 0.16)
		sampler.BIOME_DESERT:
			return Color(0.90, 0.75, 0.38)
		sampler.BIOME_DENSE_FOREST:
			return Color(0.05, 0.30, 0.10)
		sampler.BIOME_DRY_GRASSLAND:
			return Color(0.68, 0.64, 0.28)
		sampler.BIOME_COLD_FOREST:
			return Color(0.32, 0.55, 0.48)
		_:
			return Color(1.0, 0.0, 1.0)


func _write_report(report: Dictionary) -> void:
	var out_dir := "res://artifacts/stage13"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))
	var file := FileAccess.open(out_dir + "/world-overhaul-stage13-audit.json", FileAccess.WRITE)
	if file == null:
		_fail("Failed to create Stage 13 JSON evidence")
		return
	file.store_string(JSON.stringify(report, "  "))
	file.close()


func _percent(value: int, total: int) -> float:
	if total <= 0:
		return 0.0
	return float(value) * 100.0 / float(total)


func _fail(message: String) -> void:
	if not failures.has(message):
		failures.append(message)
