extends SceneTree

const CHUNK_SCRIPT := preload("res://scripts/world/chunk.gd")
const ITERATIONS := 32


func _initialize() -> void:
	call_deferred("_run")


func _air_lookup(_world_coord: Vector3i) -> int:
	return 0


func _run() -> void:
	var chunk := CHUNK_SCRIPT.new()
	chunk.configure(Vector3i.ZERO)
	root.add_child(chunk)
	await process_frame

	print("NULL_MESH_DIAG_AIR_BEGIN iterations=%d" % ITERATIONS)
	for _iteration in range(ITERATIONS):
		chunk.rebuild_mesh(Callable(self, "_air_lookup"))
	print("NULL_MESH_DIAG_AIR_END")

	chunk.set_block(Vector3i(0, 0, 0), chunk.BLOCK_STONE)
	print("NULL_MESH_DIAG_SOLID_BEGIN iterations=%d" % ITERATIONS)
	for _iteration in range(ITERATIONS):
		chunk.rebuild_mesh(Callable(self, "_air_lookup"))
	print("NULL_MESH_DIAG_SOLID_END")

	chunk.set_block(Vector3i(0, 0, 0), chunk.BLOCK_AIR)
	print("NULL_MESH_DIAG_CLEARED_BEGIN iterations=%d" % ITERATIONS)
	for _iteration in range(ITERATIONS):
		chunk.rebuild_mesh(Callable(self, "_air_lookup"))
	print("NULL_MESH_DIAG_CLEARED_END")

	quit(0)
