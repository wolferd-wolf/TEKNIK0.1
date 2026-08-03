extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = BoxMesh.new()
	root.add_child(mesh_instance)
	await process_frame
	print("DUMMY_BOX_MESH_PRE_FREE")
	mesh_instance.queue_free()
	await process_frame
	await process_frame
	print("DUMMY_BOX_MESH_POST_FREE")
	quit(0)
