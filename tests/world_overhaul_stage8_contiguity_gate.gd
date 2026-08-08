extends SceneTree

const DATA := preload("res://scripts/world/playable_world_stage8_biome_data.gd")
const CACHE := preload("res://scripts/world/playable_world_stage8_cache_fast.gd")

const CHUNK_SIZE := 12
const PADDING := 2
const WIDTH := 16
const MAP_SPACING := 2
const MAP_DIAMETER := 49
const HALF_MAP := 24
const TINY_MAX_CELLS := 2
const MICRO_MAX_CELLS := 8
const MAX_TRANSITION_RATIO := 0.12
const MAX_TINY_CELL_RATIO := 0.02
const MAX_MICRO_CELL_RATIO := 0.08
const MAX_COMPONENTS_PER_1000 := 20.0
const MIN_AREA_WEIGHTED_COMPONENT := 80.0
const MIN_LARGEST_COMPONENT := 300

const VIEW_CENTERS: Array[Vector2i] = [
	Vector2i(0, 0),
	Vector2i(157, -16),
	Vector2i(512, 512),
	Vector2i(-512, 256),
]

var failures: Array[String] = []
var data
var chunk_cache: Dictionary = {}


func _init() -> void:
	data = DATA.new()
	var aggregate_counts := PackedInt32Array()
	aggregate_counts.resize(DATA.STAGE8_MAX_BIOME_ID + 1)
	var total_points := 0
	var total_edges := 0
	var total_transitions := 0
	var total_components := 0
	var total_tiny_cells := 0
	var total_micro_cells := 0
	var component_square_sum := 0
	var largest_component := 0
	var views: Array[Dictionary] = []

	for center: Vector2i in VIEW_CENTERS:
		var report: Dictionary = _audit_view(center)
		views.append(report)
		total_points += int(report["points"])
		total_edges += int(report["edges"])
		total_transitions += int(report["transitions"])
		total_components += int(report["component_count"])
		total_tiny_cells += int(report["tiny_cells"])
		total_micro_cells += int(report["micro_cells"])
		component_square_sum += int(report["component_square_sum"])
		largest_component = maxi(largest_component, int(report["largest_component_cells"]))
		var counts: Array = report["biome_counts"]
		for biome_id in range(counts.size()):
			aggregate_counts[biome_id] += int(counts[biome_id])

	var transition_ratio := float(total_transitions) / float(maxi(total_edges, 1))
	var tiny_ratio := float(total_tiny_cells) / float(maxi(total_points, 1))
	var micro_ratio := float(total_micro_cells) / float(maxi(total_points, 1))
	var components_per_1000 := float(total_components) * 1000.0 / float(maxi(total_points, 1))
	var area_weighted := float(component_square_sum) / float(maxi(total_points, 1))
	if transition_ratio > MAX_TRANSITION_RATIO:
		_fail("Stage 8 2-block transition ratio %.6f exceeds %.6f" % [transition_ratio, MAX_TRANSITION_RATIO])
	if tiny_ratio > MAX_TINY_CELL_RATIO:
		_fail("Stage 8 tiny-cell ratio %.6f exceeds %.6f" % [tiny_ratio, MAX_TINY_CELL_RATIO])
	if micro_ratio > MAX_MICRO_CELL_RATIO:
		_fail("Stage 8 micro-cell ratio %.6f exceeds %.6f" % [micro_ratio, MAX_MICRO_CELL_RATIO])
	if components_per_1000 > MAX_COMPONENTS_PER_1000:
		_fail("Stage 8 components per 1000 points %.3f exceeds %.3f" % [components_per_1000, MAX_COMPONENTS_PER_1000])
	if area_weighted < MIN_AREA_WEIGHTED_COMPONENT:
		_fail("Stage 8 area-weighted component %.3f is below %.3f cells" % [area_weighted, MIN_AREA_WEIGHTED_COMPONENT])
	if largest_component < MIN_LARGEST_COMPONENT:
		_fail("Stage 8 largest component %d is below %d cells" % [largest_component, MIN_LARGEST_COMPONENT])

	var active_seen := 0
	var count_report: Array[int] = []
	for biome_id in range(aggregate_counts.size()):
		var count := int(aggregate_counts[biome_id])
		count_report.append(count)
		if count > 0 and biome_id != DATA.BIOME_ROCKY:
			active_seen += 1
	if aggregate_counts[DATA.BIOME_ROCKY] != 0:
		_fail("Stage 8 minimap audit still contains legacy Rocky cells")
	# The four fixed map windows are regional-quality samples, not the broad
	# distribution audit. They should still expose several ecologies rather than
	# collapsing the world to one or two labels.
	if active_seen < 4:
		_fail("Stage 8 minimap audit saw fewer than four active ecologies")

	var report := {
		"sampling_contract": {
			"map_spacing_blocks": MAP_SPACING,
			"map_pixel_diameter": MAP_DIAMETER,
			"view_count": VIEW_CENTERS.size(),
			"sampled_points": total_points,
		},
		"thresholds": {
			"max_transition_ratio": MAX_TRANSITION_RATIO,
			"max_tiny_cell_ratio": MAX_TINY_CELL_RATIO,
			"max_micro_cell_ratio": MAX_MICRO_CELL_RATIO,
			"max_components_per_1000": MAX_COMPONENTS_PER_1000,
			"min_area_weighted_component_cells": MIN_AREA_WEIGHTED_COMPONENT,
			"min_largest_component_cells": MIN_LARGEST_COMPONENT,
		},
		"shipping_stage8": {
			"biome_counts_by_id": count_report,
			"active_ecologies_seen": active_seen,
			"component_count": total_components,
			"components_per_1000_points": components_per_1000,
			"transition_ratio": transition_ratio,
			"tiny_cell_ratio": tiny_ratio,
			"micro_cell_ratio": micro_ratio,
			"area_weighted_component_cells": area_weighted,
			"largest_component_cells": largest_component,
			"views": views,
		},
		"failures": failures,
	}
	print("WORLD_OVERHAUL_STAGE8_CONTIGUITY_JSON=%s" % JSON.stringify(report))
	if failures.is_empty():
		print("WORLD_OVERHAUL_STAGE8_CONTIGUITY_PASS")
		quit(0)
		return
	for failure: String in failures:
		push_error(failure)
	quit(1)


func _fail(message: String) -> void:
	if not failures.has(message):
		failures.append(message)


func _floor_chunk(value: int) -> int:
	return floori(float(value) / float(CHUNK_SIZE))


func _biome_at(world_x: int, world_z: int) -> int:
	var coord := Vector2i(_floor_chunk(world_x), _floor_chunk(world_z))
	if not chunk_cache.has(coord):
		chunk_cache[coord] = CACHE.build(coord, data)
	var cache: Dictionary = chunk_cache[coord]
	var biomes: PackedByteArray = cache.get("biomes", PackedByteArray())
	var local_x: int = world_x - coord.x * CHUNK_SIZE
	var local_z: int = world_z - coord.y * CHUNK_SIZE
	var index: int = (local_z + PADDING) * WIDTH + local_x + PADDING
	return int(biomes[index])


func _audit_view(center: Vector2i) -> Dictionary:
	var point_count := MAP_DIAMETER * MAP_DIAMETER
	var grid := PackedByteArray()
	grid.resize(point_count)
	var counts := PackedInt32Array()
	counts.resize(DATA.STAGE8_MAX_BIOME_ID + 1)
	var cursor := 0
	for pixel_z in range(-HALF_MAP, HALF_MAP + 1):
		for pixel_x in range(-HALF_MAP, HALF_MAP + 1):
			var biome := _biome_at(
				center.x + pixel_x * MAP_SPACING,
				center.y + pixel_z * MAP_SPACING
			)
			grid[cursor] = biome
			if biome >= 0 and biome < counts.size():
				counts[biome] += 1
			cursor += 1

	var transitions := 0
	var edges := 0
	for z in range(MAP_DIAMETER):
		for x in range(MAP_DIAMETER):
			var index := z * MAP_DIAMETER + x
			if x + 1 < MAP_DIAMETER:
				edges += 1
				if grid[index] != grid[index + 1]:
					transitions += 1
			if z + 1 < MAP_DIAMETER:
				edges += 1
				if grid[index] != grid[index + MAP_DIAMETER]:
					transitions += 1

	var visited := PackedByteArray()
	visited.resize(point_count)
	var component_count := 0
	var tiny_cells := 0
	var micro_cells := 0
	var component_square_sum := 0
	var largest_component := 0
	for start in range(point_count):
		if visited[start] != 0:
			continue
		component_count += 1
		var biome: int = int(grid[start])
		var stack: Array[int] = [start]
		visited[start] = 1
		var size := 0
		while not stack.is_empty():
			var index: int = stack.pop_back()
			size += 1
			var x := index % MAP_DIAMETER
			var z := index / MAP_DIAMETER
			if x > 0:
				_try_visit(index - 1, biome, grid, visited, stack)
			if x + 1 < MAP_DIAMETER:
				_try_visit(index + 1, biome, grid, visited, stack)
			if z > 0:
				_try_visit(index - MAP_DIAMETER, biome, grid, visited, stack)
			if z + 1 < MAP_DIAMETER:
				_try_visit(index + MAP_DIAMETER, biome, grid, visited, stack)
		largest_component = maxi(largest_component, size)
		component_square_sum += size * size
		if size <= TINY_MAX_CELLS:
			tiny_cells += size
		if size <= MICRO_MAX_CELLS:
			micro_cells += size

	var count_report: Array[int] = []
	for biome_id in range(counts.size()):
		count_report.append(int(counts[biome_id]))
	return {
		"center": [center.x, center.y],
		"points": point_count,
		"edges": edges,
		"transitions": transitions,
		"transition_ratio": float(transitions) / float(maxi(edges, 1)),
		"component_count": component_count,
		"tiny_cells": tiny_cells,
		"micro_cells": micro_cells,
		"component_square_sum": component_square_sum,
		"area_weighted_component_cells": float(component_square_sum) / float(point_count),
		"largest_component_cells": largest_component,
		"biome_counts": count_report,
	}


func _try_visit(
	index: int,
	biome: int,
	grid: PackedByteArray,
	visited: PackedByteArray,
	stack: Array[int]
) -> void:
	if visited[index] != 0 or int(grid[index]) != biome:
		return
	visited[index] = 1
	stack.append(index)
