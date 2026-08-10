extends Node3D

const TextureGenerator = preload("res://scripts/textures/texture_generator.gd")
const PREVIEW_SEED := 734921
const BLOCK_IDS := [
	"grass",
	"dirt",
	"stone",
	"sand",
	"log",
	"leaves",
	"iron_ore",
]
const LABELS := {
	"grass": "Grass",
	"dirt": "Dirt",
	"stone": "Stone",
	"sand": "Sand",
	"log": "Wood",
	"leaves": "Leaves",
	"iron_ore": "Iron Ore",
}

func _ready() -> void:
	_build_environment()
	_build_camera()
	_build_blocks()

func _build_environment() -> void:
	var world := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.035, 0.04, 0.05)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.72, 0.76, 0.84)
	environment.ambient_light_energy = 0.8
	world.environment = environment
	add_child(world)

	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-48.0, -28.0, 0.0)
	key.light_energy = 1.25
	key.shadow_enabled = true
	add_child(key)

	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-20.0, 145.0, 0.0)
	fill.light_energy = 0.35
	add_child(fill)

	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(18.0, 10.0)
	var ground_material := StandardMaterial3D.new()
	ground_material.albedo_color = Color(0.055, 0.06, 0.07)
	ground_material.roughness = 1.0
	plane.material = ground_material
	ground.mesh = plane
	ground.position = Vector3(0.0, -1.35, 0.0)
	add_child(ground)

func _build_camera() -> void:
	var camera := Camera3D.new()
	camera.position = Vector3(0.0, 5.8, 14.5)
	camera.fov = 38.0
	camera.current = true
	add_child(camera)
	camera.look_at(Vector3(0.0, 0.0, 0.0), Vector3.UP)

func _build_blocks() -> void:
	var positions := [
		Vector3(-4.8, 0.0, 0.0),
		Vector3(-1.6, 0.0, 0.0),
		Vector3(1.6, 0.0, 0.0),
		Vector3(4.8, 0.0, 0.0),
		Vector3(-3.2, -2.7, -0.4),
		Vector3(0.0, -2.7, -0.4),
		Vector3(3.2, -2.7, -0.4),
	]
	for i in range(BLOCK_IDS.size()):
		_create_block(BLOCK_IDS[i], positions[i])

func _create_block(block_id: String, position: Vector3) -> void:
	var instance := MeshInstance3D.new()
	instance.name = "%sBlock" % LABELS[block_id]
	var cube := BoxMesh.new()
	cube.size = Vector3(2.65, 2.65, 2.65)
	var material := StandardMaterial3D.new()
	material.albedo_texture = TextureGenerator.generate(block_id, PREVIEW_SEED)
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	material.roughness = 1.0
	material.metallic = 0.0
	cube.material = material
	instance.mesh = cube
	instance.position = position
	instance.rotation_degrees.y = -8.0
	add_child(instance)
	var label := Label3D.new()
	label.text = LABELS[block_id]
	label.position = position + Vector3(0.0, 1.9, 0.0)
	label.font_size = 32
	label.modulate = Color(0.95, 0.95, 0.95)
	label.outline_size = 8
	label.no_depth_test = true
	add_child(label)
