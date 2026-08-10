extends SceneTree

const PREVIEW_SCENE = preload("res://scenes/texture_block_preview_3d.tscn")
const OUTPUT_PATH := "artifacts/texture_block_preview_3d.png"

func _init() -> void:
	get_root().size = Vector2i(1280, 720)
	var preview := PREVIEW_SCENE.instantiate()
	get_root().add_child(preview)
	await process_frame
	await process_frame
	await process_frame
	var image := get_root().get_texture().get_image()
	if image.is_empty():
		push_error("TEXTURE_BLOCK_PREVIEW_CAPTURE_EMPTY")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("artifacts"))
	var error := image.save_png(OUTPUT_PATH)
	if error != OK:
		push_error("TEXTURE_BLOCK_PREVIEW_CAPTURE_FAILED=%d" % error)
		quit(1)
		return
	print("TEXTURE_BLOCK_PREVIEW_PASS")
	print("TEXTURE_BLOCK_PREVIEW_OUTPUT=%s" % OUTPUT_PATH)
	quit(0)
