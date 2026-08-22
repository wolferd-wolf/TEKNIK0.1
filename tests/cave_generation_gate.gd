extends SceneTree

## Cave generation gate (build plan step 9).
## Verifies the carve integration end to end:
##  - determinism of the per-chunk carve map
##  - contract guards: min-y clamp, water safety margin, surface depth rule,
##    mesh-height cap
##  - gameplay truth (get_block) agrees with the mesh carve map
##  - seam consistency: adjacent chunk maps agree on overlapping world cells
##  - surface-carved columns are reported as blocked tree columns

const RUNTIME := preload("res://scripts/world/playable_world_generation_runtime.gd")
const DATA := preload("res://scripts/world/playable_world_carpathian_data.gd")
const CAVE_REF := preload("res://scripts/world/cave_field_reference.gd")

const PROBE_CHUNKS: Array[Vector2i] = [
	Vector2i(0, 0), Vector2i(1, 0), Vector2i(-3, 2), Vector2i(7, -4), Vector2i(13, 5),
]

var failures: Array[String] = []
var checks := 0


func _fail(message: String) -> void:
	checks += 1
	if failures.size() < 8 and not failures.has(message):
		failures.append(message)


func _expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		_fail(message)


func _init() -> void:
	var data = DATA.new()
	var cache_builder = RUNTIME.SHIPPING_GENERATION_CACHE
	var total_carved := 0
	var total_seam_matches := 0

	for coord in PROBE_CHUNKS:
		var caches: Dictionary = cache_builder.build(coord, data)
		var heights: PackedInt32Array = caches.get("heights", PackedInt32Array())
		var water_types: PackedByteArray = caches.get("stage7_water_types", PackedByteArray())
		var mesh_height: int = mini(
			DATA.OVERHAUL_WORLD_HEIGHT,
			RUNTIME.STAGE12_STAGE2_RUNTIME_BASE._effective_mesh_height(coord, heights, {}) + 2
		)
		var info: Dictionary = data.cave_data_for_chunk(coord, caches, mesh_height)
		var overrides: Dictionary = info.get("overrides", {})
		var blocked: PackedInt32Array = info.get("blocked_columns", PackedInt32Array())
		total_carved += overrides.size()

		# 1. Determinism.
		var info_again: Dictionary = data.cave_data_for_chunk(coord, caches, mesh_height)
		_expect(
			info_again.get("overrides", {}).hash() == overrides.hash(),
			"carve map not deterministic at %s" % [coord]
		)

		# 2. Contract guards over every carved cell.
		var width := roundi(sqrt(float(heights.size())))
		var min_x := coord.x * 12 - 2
		var min_z := coord.y * 12 - 2
		for key in overrides:
			var parts: PackedStringArray = String(key).split(",")
			if parts.size() != 3:
				_fail("bad override key %s" % [key])
				continue
			if int(overrides[key]) != data.BLOCK_AIR:
				continue # ore placement, not a carve; checked by ore_generation_gate
			var wx := int(parts[0])
			var wy := int(parts[1])
			var wz := int(parts[2])
			_expect(wy >= 2, "carve below min-y at %s" % [key])
			var cx := wx - min_x
			var cz := wz - min_z
			var idx := cz * width + cx
			if idx < 0 or idx >= heights.size():
				_fail("override outside padded cache at %s" % [key])
				continue
			var h := int(heights[idx])
			var water_column: bool = int(water_types[idx]) != data.WATER_NONE
			_expect(wy <= mini(h, mesh_height - 1), "carve above cap at %s" % [key])
			if water_column:
				_expect(wy <= h - 8, "water margin violated at %s" % [key])
			if h - wy < 4:
				var entrance_ok: bool = (
					not water_column
					and h > DATA.SEA_LEVEL + 3
					and CAVE_REF.entrance_value(wx, wy, wz) > CAVE_REF.ENTRANCE_THRESHOLD
				)
				_expect(entrance_ok, "shallow carve without entrance at %s" % [key])

		# 3. get_block agreement on a deterministic cell sample.
		var sample_count := 0
		for cz in range(2, width - 2, 3):
			for cx in range(2, width - 2, 3):
				var wx := min_x + cx
				var wz := min_z + cz
				var h := int(heights[cz * width + cx])
				var y := 2
				while y <= mini(h, 40) and sample_count < 4096:
					var key2 := "%d,%d,%d" % [wx, y, wz]
					var map_value := int(overrides[key2]) if overrides.has(key2) else -1
					var block_id: int = data.get_block(Vector3i(wx, y, wz))
					if map_value == data.BLOCK_AIR and block_id != data.BLOCK_AIR:
						_fail("carve map says air, get_block says %d at %d,%d,%d" % [block_id, wx, y, wz])
					if map_value >= data.BLOCK_COAL_ORE and block_id != map_value:
						_fail("ore map says %d, get_block says %d at %d,%d,%d" % [map_value, block_id, wx, y, wz])
					if map_value < 0 and block_id == data.BLOCK_AIR and y <= h:
						_fail("get_block carved outside map at %d,%d,%d" % [wx, y, wz])
					sample_count += 1
					y += 1

		# 4. Seam consistency: this chunk's padded ring overlaps the neighbor's
		# core; the pure field must agree on every shared carved cell.
		var neighbor_caches: Dictionary = cache_builder.build(Vector2i(coord.x + 1, coord.y), data)
		var neighbor_info: Dictionary = data.cave_data_for_chunk(
			Vector2i(coord.x + 1, coord.y), neighbor_caches, mesh_height
		)
		var neighbor_overrides: Dictionary = neighbor_info.get("overrides", {})
		# Every neighbor carve inside this chunk's padded domain must match
		# ours exactly (pure world-coordinate field => no one-sided carves).
		var seam_matches := 0
		for key in neighbor_overrides:
			var parts2: PackedStringArray = String(key).split(",")
			if parts2.size() != 3:
				continue
			var nwx := int(parts2[0])
			var nwz := int(parts2[2])
			if nwx >= min_x and nwx < min_x + width and nwz >= min_z and nwz < min_z + width:
				_expect(overrides.has(key), "seam mismatch (neighbor carved, we did not): %s" % [key])
				seam_matches += 1
		for key in overrides:
			var parts3: PackedStringArray = String(key).split(",")
			if parts3.size() != 3:
				continue
			var cwx := int(parts3[0])
			var cwz := int(parts3[2])
			if cwx >= min_x + 12 and cwx < min_x + width and cwz >= min_z and cwz < min_z + width:
				_expect(neighbor_overrides.has(key), "seam mismatch (we carved, neighbor did not): %s" % [key])
		total_seam_matches += seam_matches

		# 5. Surface-carved columns are blocked for trees.
		for cz2 in range(width):
			for cx2 in range(width):
				var idx2 := cz2 * width + cx2
				var h2 := int(heights[idx2])
				if h2 < 2:
					continue
				var wx2 := min_x + cx2
				var wz2 := min_z + cz2
				var surf_key := "%d,%d,%d" % [wx2, h2, wz2]
				if overrides.has(surf_key) and int(overrides[surf_key]) == data.BLOCK_AIR:
					_expect(blocked.has(idx2), "surface carve not blocked for trees at %d,%d" % [wx2, wz2])

	_expect(total_seam_matches > 0, "no seam overlap sampled across all probe chunks")

	print("CAVE_GENERATION_GATE_JSON=", JSON.stringify({
		"gate": "cave_generation",
		"chunks": PROBE_CHUNKS.size(),
		"carved_cells": total_carved,
		"seam_matches": total_seam_matches,
		"checks": checks,
		"failures": failures,
	}))
	if failures.is_empty():
		print("CAVE_GENERATION_GATE_PASS")
	else:
		print("CAVE_GENERATION_GATE_FAIL")
	quit(0 if failures.is_empty() else 1)
