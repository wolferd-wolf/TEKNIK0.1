extends Node3D

const TextureGenerator = preload("res://scripts/textures/texture_generator.gd")
const PREVIEW_SEED := 734921
const BLOCK_IDS := ["grass", "dirt", "stone", "sand", "log", "leaves", "iron_ore"]
const LABELS := {"grass":"Grass Block", "dirt":"Dirt", "stone":"Stone", "sand":"Sand", "log":"Oak Log", "leaves":"Leaves", "iron_ore":"Iron Ore"}

func _ready() -> void:
	_build_environment()
	_build_camera()
	_build_blocks()

func _build_environment() -> void:
	var world := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.055, 0.06, 0.07)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.72, 0.76, 0.84)
	env.ambient_light_energy = 0.75
	world.environment = env
	add_child(world)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-52.0, -32.0, 0.0)
	key.light_energy = 1.25
	key.shadow_enabled = true
	add_child(key)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-18.0, 140.0, 0.0)
	fill.light_energy = 0.30
	add_child(fill)

func _build_camera() -> void:
	var camera := Camera3D.new()
	camera.position = Vector3(0.0, 3.2, 18.5)
	camera.fov = 39.0
	camera.current = true
	add_child(camera)
	camera.look_at(Vector3(0.0, -1.0, 0.0), Vector3.UP)

func _build_blocks() -> void:
	var positions := [Vector3(-6.4, 0.0, 0.0), Vector3(-2.1, 0.0, 0.0), Vector3(2.1, 0.0, 0.0), Vector3(6.4, 0.0, 0.0), Vector3(-4.3, -4.1, 0.0), Vector3(0.0, -4.1, 0.0), Vector3(4.3, -4.1, 0.0)]
	for i in range(BLOCK_IDS.size()): _create_block(BLOCK_IDS[i], positions[i])

func _create_block(block_id: String, position: Vector3) -> void:
	var root := Node3D.new(); root.position = position; add_child(root)
	var set := TextureGenerator.generate_set(block_id, PREVIEW_SEED)
	_add_face(root, set["top"], Vector3(0, 1.3, 0), Vector3(-90, 0, 0))
	_add_face(root, set["bottom"], Vector3(0, -1.3, 0), Vector3(90, 0, 0))
	_add_face(root, set["side"], Vector3(0, 0, 1.3), Vector3.ZERO)
	_add_face(root, set["side"], Vector3(0, 0, -1.3), Vector3(0, 180, 0))
	_add_face(root, set["side"], Vector3(1.3, 0, 0), Vector3(0, 90, 0))
	_add_face(root, set["side"], Vector3(-1.3, 0, 0), Vector3(0, -90, 0))
	var label := Label3D.new(); label.text = LABELS[block_id]; label.font_size = 32; label.modulate = Color(0.96, 0.96, 0.96); label.outline_size = 8; label.position = Vector3(0, 1.95, 0); label.billboard = BaseMaterial3D.BILLBOARD_ENABLED; root.add_child(label)

func _add_face(root: Node3D, texture: Texture2D, position: Vector3, rotation: Vector3) -> void:
	var face := MeshInstance3D.new()
	var mesh := QuadMesh.new(); mesh.size = Vector2(2.6, 2.6)
	var material := StandardMaterial3D.new(); material.albedo_texture = texture; material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST; material.roughness = 1.0; material.metallic = 0.0
	mesh.material = material; face.mesh = mesh; face.position = position; face.rotation_degrees = rotation; root.add_child(face)
