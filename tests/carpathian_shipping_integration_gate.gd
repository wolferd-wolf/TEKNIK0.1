extends SceneTree

const ShippingData = preload("res://scripts/world/playable_world_carpathian_data.gd")
const ShippingCache = preload("res://scripts/world/playable_world_carpathian_generation_cache_fast.gd")
const CHUNK_SIZE := 12
const PADDING := 2
const WIDTH := CHUNK_SIZE + PADDING * 2
const SCREENSHOT_X := 83
const SCREENSHOT_Z := 56


func _init() -> void:
	if not ClassDB.class_exists(&"TeknikCarpathianSampler"):
		push_error("TeknikCarpathianSampler was not loaded")
		quit(1)
		return
	var data = ShippingData.new()
	if not data.carpathian_enabled():
		push_error("Shipping Carpathian adapter did not activate")
		quit(1)
		return

	var coord := Vector2i(
		floori(float(SCREENSHOT_X) / float(CHUNK_SIZE)),
		floori(float(SCREENSHOT_Z) / float(CHUNK_SIZE))
	)
	var cache: Dictionary = ShippingCache.build(coord, data)
	if cache.is_empty():
		push_error("Shipping Carpathian cache returned empty")
		quit(1)
		return
	var heights: PackedInt32Array = cache.get("heights", PackedInt32Array())
	var water_types: PackedByteArray = cache.get("stage7_water_types", PackedByteArray())
	if heights.size() != WIDTH * WIDTH or water_types.size() != WIDTH * WIDTH:
		push_error("Shipping Carpathian cache dimensions are invalid")
		quit(1)
		return

	var min_x: int = coord.x * CHUNK_SIZE - PADDING
	var min_z: int = coord.y * CHUNK_SIZE - PADDING
	var height_mismatches := 0
	var water_mismatches := 0
	for local_z in range(PADDING, PADDING + CHUNK_SIZE):
		for local_x in range(PADDING, PADDING + CHUNK_SIZE):
			var world_x: int = min_x + local_x
			var world_z: int = min_z + local_z
			var index: int = local_z * WIDTH + local_x
			var direct_height: int = data.terrain_height(world_x, world_z)
			var direct_water: int = data.water_type_at(world_x, world_z)
			if direct_height != heights[index]:
				height_mismatches += 1
			if direct_water != int(water_types[index]):
				water_mismatches += 1
	if height_mismatches != 0 or water_mismatches != 0:
		push_error("Carpathian direct/cache mismatch")
		print("CARPATHIAN_SHIPPING_MISMATCH heights=%d water=%d" % [
			height_mismatches, water_mismatches
		])
		quit(1)
		return

	var sx: int = SCREENSHOT_X - min_x
	var sz: int = SCREENSHOT_Z - min_z
	var screenshot_index: int = sz * WIDTH + sx
	var screenshot_height: int = heights[screenshot_index]
	var screenshot_direct: int = data.terrain_height(SCREENSHOT_X, SCREENSHOT_Z)
	var screenshot_block: int = data.get_block(Vector3i(
		SCREENSHOT_X, screenshot_height, SCREENSHOT_Z
	))
	if screenshot_direct != screenshot_height or screenshot_block == data.BLOCK_AIR:
		push_error("Screenshot-coordinate physical terrain verification failed")
		quit(1)
		return
	print("CARPATHIAN_SHIPPING_X83_Z56 height=%d water=%d top_block=%d" % [
		screenshot_height, water_types[screenshot_index], screenshot_block
	])

	# Verify the shipping seed is not relying on the 138-block safety clamp over
	# a large 2048x2048 reference window sampled every 8 blocks.
	var native: Object = ClassDB.instantiate(&"TeknikCarpathianSampler")
	native.call("set_seed", data.WORLD_SEED)
	var raw: PackedInt32Array = native.call("generate_grid", -1024, -1024, 256, 256, 8)
	var clipped := 0
	var shifted_min := 999999
	var shifted_max := -999999
	for value in raw:
		var shifted: int = int(value) + data.CARPATHIAN_HEIGHT_OFFSET
		shifted_min = mini(shifted_min, shifted)
		shifted_max = maxi(shifted_max, shifted)
		if shifted > data.STAGE2_SAFE_TERRAIN_TOP:
			clipped += 1
	var clipped_pct := 100.0 * float(clipped) / float(raw.size())
	print("CARPATHIAN_SHIPPING_RANGE min=%d max=%d clipped=%d clipped_pct=%.6f" % [
		shifted_min, shifted_max, clipped, clipped_pct
	])
	if clipped_pct > 0.10:
		push_error("Shipping seed clips too much Carpathian terrain")
		quit(1)
		return

	# Benchmark the actual one-pass shipping cache, not just the native sampler.
	var timings := PackedFloat64Array()
	for warmup in range(4):
		ShippingCache.build(Vector2i(warmup * 3, -warmup * 2), data)
	for rep in range(40):
		var started := Time.get_ticks_usec()
		var measured: Dictionary = ShippingCache.build(
			Vector2i(rep * 3 + 11, rep * -2 - 7), data
		)
		var elapsed := Time.get_ticks_usec() - started
		if measured.is_empty():
			push_error("Measured Carpathian shipping cache returned empty")
			quit(1)
			return
		timings.append(float(elapsed) / 1000.0)
	timings.sort()
	var total := 0.0
	for value in timings:
		total += value
	var p95_index := mini(
		timings.size() - 1,
		int(ceil(float(timings.size()) * 0.95)) - 1
	)
	var p95: float = timings[p95_index]
	print("CARPATHIAN_SHIPPING_CACHE_MS min=%.4f mean=%.4f p95=%.4f max=%.4f samples=%d" % [
		timings[0], total / float(timings.size()), p95,
		timings[timings.size() - 1], timings.size()
	])
	if p95 >= 1.0:
		push_error("Carpathian shipping cache missed the 1.0 ms p95 target")
		quit(1)
		return

	print("CARPATHIAN_SHIPPING_INTEGRATION_PASS direct_cache_height_mismatches=0 direct_cache_water_mismatches=0")
	quit(0)
