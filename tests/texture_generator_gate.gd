extends SceneTree
const TextureGenerator = preload("res://scripts/textures/texture_generator.gd")
const SEED := 734921
func _init() -> void:
	var failures:Array[String]=[]
	var blocks=TextureGenerator.get_block_types()
	for block_id in blocks:
		var a:Image=TextureGenerator.generate(block_id,SEED).get_image(); var b:Image=TextureGenerator.generate(block_id,SEED).get_image()
		if a.get_width()!=16 or a.get_height()!=16: failures.append("WRONG_SIZE %s"%block_id)
		if a.get_data()!=b.get_data(): failures.append("NON_DETERMINISTIC %s"%block_id)
	var same_seed=TextureGenerator.generate("dirt",SEED).get_image().get_data(); var other_seed=TextureGenerator.generate("dirt",SEED+1).get_image().get_data()
	if same_seed==other_seed: failures.append("SEED_HAS_NO_EFFECT dirt")
	var ore=TextureGenerator.generate("iron_ore",SEED).get_image(); var speckles:=0
	for y in range(16):
		for x in range(16):
			var c=ore.get_pixel(x,y)
			if c.r>0.58 and c.g<0.5: speckles+=1
	if speckles<4 or speckles>32: failures.append("ORE_SPECKLE_COUNT=%d"%speckles)
	var preview:=Image.create(64,32,false,Image.FORMAT_RGBA8); preview.fill(Color(0.08,0.08,0.08,1))
	for i in range(blocks.size()): preview.blit_rect(TextureGenerator.generate(blocks[i],SEED).get_image(),Rect2i(0,0,16,16),Vector2i((i%4)*16,(i/4)*16))
	var dir=ProjectSettings.globalize_path("res://artifacts"); DirAccess.make_dir_recursive_absolute(dir); preview.resize(512,256,Image.INTERPOLATE_NEAREST); preview.save_png(dir+"/texture_generator_preview.png")
	if failures.is_empty():
		print("TEXTURE_GENERATOR_GATE_PASS"); print("DETERMINISM_PASS blocks=%d seed=%d"%[blocks.size(),SEED]); print("SEED_VARIATION_PASS"); print("ORE_SPECKLES=%d"%speckles); quit(0)
	for failure in failures: push_error(failure)
	quit(1)
