extends SceneTree

const CHUNK_SCRIPT := preload("res://scripts/world/chunk.gd")
const ITERATIONS := 128

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run_gate")


func _fail(message: String) -> void:
	failures.append(message)
	push_error(message)


func _air_lookup(_world_coord: Vector3i) -> int:
	return 0


func _run_gate() -> void:
	var chunk := CHUNK_SCRIPT.new()
	chunk.configure(Vector3i.ZERO)
	root.add_child(chunk)
	await process_frame

	for iteration in range(ITERATIONS):
		chunk.set_block(Vector3i.ZERO, chunk.BLOCK_STONE)
		chunk.rebuild_mesh(Callable(self, "_air_lookup"))
		if chunk.mesh_instance.mesh == null:
			_fail("Solid remesh returned null at iteration %d" % iteration)
			break
		if not chunk.mesh_instance.visible:
			_fail("Solid remesh was hidden at iteration %d" % iteration)
			break
		if chunk.mesh_instance.mesh.get_surface_count() == 0:
			_fail("Solid remesh had no surface at iteration %d" % iteration)
			break
		if chunk.collision_shape.shape == null:
			_fail("Solid remesh had no collision at iteration %d" % iteration)
			break

		var retained_mesh = chunk.mesh_instance.mesh
		chunk.set_block(Vector3i.ZERO, chunk.BLOCK_AIR)
		chunk.rebuild_mesh(Callable(self, "_air_lookup"))
		if chunk.mesh_instance.visible:
			_fail("Zero-face remesh remained visible at iteration %d" % iteration)
			break
		if chunk.mesh_instance.mesh != retained_mesh:
			_fail("Zero-face remesh replaced the valid renderer mesh at iteration %d" % iteration)
			break
		if chunk.collision_shape.shape != null:
			_fail("Zero-face remesh retained collision at iteration %d" % iteration)
			break

	if failures.is_empty():
		print("NULL_MESH_REMESH_GATE_PASS")
		print("SOLID_EMPTY_REMESH_CYCLES=%d" % ITERATIONS)

	chunk.queue_free()
	await process_frame
	await process_frame

	if failures.is_empty():
		quit(0)
	else:
		print("NULL_MESH_REMESH_GATE_FAIL")
		for failure in failures:
			print("FAILURE=%s" % failure)
		quit(1)
