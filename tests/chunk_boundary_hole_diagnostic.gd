extends SceneTree

const ShippingData = preload("res://scripts/world/playable_world_carpathian_data.gd")
const ShippingCache = preload("res://scripts/world/playable_world_carpathian_generation_cache_fast.gd")
const ShippingStage12Cache = preload("res://scripts/world/playable_world_stage12_cache_fast.gd")
const ShippingMesher = preload("res://scripts/world/playable_world_stage12_mesher.gd")
const Stage10Mesher = preload("res://scripts/world/playable_world_stage10_mesher.gd")
const Stage6Mesher = preload("res://scripts/world/playable_world_stage6_mesher.gd")
const BaseMesher = preload("res://scripts/world/playable_world_mesher.gd")
const FrozenStage11Runtime = preload("res://scripts/world/playable_world_stage11_generation_runtime.gd")
const Stage2Runtime = preload("res://scripts/world/playable_world_stage2_generation_runtime.gd")

const CHUNK_SIZE := 12
const PROBES := [
	{"label":"corner_-13_95", "cell":Vector2i(-13, 95)},
	{"label":"z_edge_-20_95", "cell":Vector2i(-20, 95)},
	{"label":"z_edge_-5_-13", "cell":Vector2i(-5, -13)},
]

var failures: Array[String] = []
var expected_exposed_faces := 0
var missing_exposed_faces := 0
var phantom_tree_neighbors := 0
var suppression_terrain_air := 0
var details_printed := 0
var data_ref

func _fail(message: String) -> void:
	failures.append(message)
	push_error(message)

func _key(cell: Vector3i) -> String:
	return "%d,%d,%d" % [cell.x, cell.y, cell.z]

func _face_key(center: Vector3, normal: Vector3) -> String:
	return "%.1f,%.1f,%.1f|%.0f,%.0f,%.0f" % [center.x,center.y,center.z,normal.x,normal.y,normal.z]

func _shipping_state(coord: Vector2i) -> Dictionary:
	var caches: Dictionary = ShippingCache.build(coord, data_ref)
	var heights: PackedInt32Array = caches.get("heights", PackedInt32Array())
	var biomes: PackedByteArray = caches.get("biomes", PackedByteArray())
	var water_types: PackedByteArray = caches.get("stage7_water_types", PackedByteArray())
	var modifiers: PackedByteArray = caches.get("stage9_terrain_modifiers", PackedByteArray())
	var expression: Dictionary = ShippingStage12Cache.build_expression_codes(caches, data_ref)
	var transitions: PackedByteArray = expression.get("transition_codes", PackedByteArray())
	var hydrology: PackedByteArray = expression.get("hydrology_codes", PackedByteArray())
	var blocked: PackedInt32Array = FrozenStage11Runtime._stage6_blocked_tree_columns(coord,caches,data_ref)
	var width: int = roundi(sqrt(float(heights.size())))
	var padding: int = maxi(floori(float(width-CHUNK_SIZE)*0.5),1)
	var origin := Vector3i(coord.x*CHUNK_SIZE,0,coord.y*CHUNK_SIZE)

	# Exact Stage 12 set passed into Stage 6 suppression.
	var mask := PackedByteArray()
	mask.resize(heights.size())
	for value in blocked:
		var i: int = int(value)
		if i >= 0 and i < mask.size(): mask[i] = 1
	for cz in range(1,width-1):
		for cx in range(1,width-1):
			var i := cz*width+cx
			var wx := origin.x+cx-padding
			var wz := origin.z+cz-padding
			if Stage10Mesher._legacy_tree_origin(wx,wz,int(heights[i]),int(biomes[i]),data_ref.OVERHAUL_WORLD_HEIGHT,data_ref.SEA_LEVEL,data_ref):
				mask[i] = 1
	var count := 0
	for value in mask:
		if int(value) != 0: count += 1
	var combined := PackedInt32Array()
	combined.resize(count)
	var p := 0
	for i in range(mask.size()):
		if mask[i] != 0:
			combined[p] = i
			p += 1
	var suppression: Dictionary = Stage6Mesher._suppression_overrides(coord,heights,biomes,{},CHUNK_SIZE,data_ref.OVERHAUL_WORLD_HEIGHT,data_ref.SEA_LEVEL,combined)
	for key_value in suppression.keys():
		if int(suppression[key_value]) != BaseMesher.BLOCK_AIR: continue
		var parts := String(key_value).split(",")
		if parts.size() != 3: continue
		var cell := Vector3i(int(parts[0]),int(parts[1]),int(parts[2]))
		var cx := cell.x-origin.x+padding
		var cz := cell.z-origin.z+padding
		if cx < 0 or cx >= width or cz < 0 or cz >= width: continue
		var height := int(heights[cz*width+cx])
		if cell.y <= height:
			suppression_terrain_air += 1
			if details_printed < 12:
				print("SUPPRESSION_ERASES_TERRAIN chunk=%s cell=%s height=%d direct=%d" % [coord,cell,height,int(data_ref.get_block(cell))])
				details_printed += 1

	var mesh_height: int = mini(data_ref.OVERHAUL_WORLD_HEIGHT,Stage2Runtime._effective_mesh_height(coord,heights,{})+2)
	var mesh: Dictionary = ShippingMesher.build(coord,heights,{},CHUNK_SIZE,mesh_height,data_ref.SEA_LEVEL,biomes,water_types,modifiers,transitions,hydrology,data_ref,blocked)
	return {"coord":coord,"origin":origin,"width":width,"padding":padding,"heights":heights,"biomes":biomes,"water":water_types,"modifiers":modifiers,"transitions":transitions,"hydrology":hydrology,"suppression":suppression,"mesh":mesh}

func _face_lookup(coord: Vector2i, mesh_data: Dictionary) -> Dictionary:
	var result := {}
	var vertices: PackedVector3Array = mesh_data.get("vertices",PackedVector3Array())
	var normals: PackedVector3Array = mesh_data.get("normals",PackedVector3Array())
	var face_count := int(mesh_data.get("face_count",0))
	var origin := Vector3(coord.x*CHUNK_SIZE,0.0,coord.y*CHUNK_SIZE)
	for face in range(face_count):
		var base := face*4
		var center := origin
		for i in range(4): center += vertices[base+i]*0.25
		result[_face_key(center,normals[base])] = true
	return result

func _cached_tree_sources(cell: Vector3i, state: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var origin: Vector3i = state["origin"]
	var width: int = state["width"]
	var padding: int = state["padding"]
	var heights: PackedInt32Array = state["heights"]
	var biomes: PackedByteArray = state["biomes"]
	var water: PackedByteArray = state["water"]
	var modifiers: PackedByteArray = state["modifiers"]
	var transitions: PackedByteArray = state["transitions"]
	var hydrology: PackedByteArray = state["hydrology"]
	for cz in range(1,width-1):
		for cx in range(1,width-1):
			var i := cz*width+cx
			if water.size() == heights.size() and int(water[i]) != int(data_ref.WATER_NONE): continue
			var wx := origin.x+cx-padding
			var wz := origin.z+cz-padding
			if absi(wx-cell.x) > 1 or absi(wz-cell.z) > 1: continue
			var surface := int(heights[i])
			var biome := int(biomes[i])
			var modifier := int(modifiers[i]) if modifiers.size() == heights.size() else int(data_ref.TERRAIN_MODIFIER_NONE)
			var transition := int(transitions[i]) if transitions.size() == heights.size() else 0
			var hydro := int(hydrology[i]) if hydrology.size() == heights.size() else int(data_ref.HYDROLOGY_MODIFIER_NONE)
			var slope: float = Stage10Mesher._cached_slope(cx,cz,heights,width)
			if not data_ref.stage11_tree_candidate_for_biome(wx,wz,surface,biome,transition,modifier,slope,hydro): continue
			var block: int = int(data_ref.stage8_tree_block_for_origin(cell,wx,wz,surface,biome))
			if block == BaseMesher.BLOCK_AIR: continue
			var direct_surface: int = int(data_ref.terrain_height(wx,wz))
			var direct_biome: int = int(data_ref.biome_at(wx,wz))
			var direct_origin: bool = bool(data_ref.is_tree_origin_for_biome(wx,wz,direct_surface,direct_biome))
			result.append({"origin":Vector3i(wx,surface,wz),"block":block,"cached_biome":biome,"cached_transition":transition,"cached_modifier":modifier,"cached_slope":slope,"cached_hydro":hydro,"direct_surface":direct_surface,"direct_biome":direct_biome,"direct_transition":int(data_ref.stage10_transition_code_at(wx,wz)),"direct_modifier":int(data_ref.stage9_terrain_modifier_at(wx,wz)),"direct_slope":float(data_ref.stage7_surface_slope_at(wx,wz,direct_surface)),"direct_hydro":int(data_ref.stage11_hydrology_modifier_at(wx,wz)),"direct_origin":direct_origin})
	return result

func _diagnose_face(lookup: Dictionary,state: Dictionary,owner: Vector3i,neighbor: Vector3i,center: Vector3,normal: Vector3,label: String) -> void:
	var owner_direct := int(data_ref.get_block(owner))
	var neighbor_direct := int(data_ref.get_block(neighbor))
	if owner_direct == BaseMesher.BLOCK_AIR or neighbor_direct != BaseMesher.BLOCK_AIR: return
	expected_exposed_faces += 1
	if lookup.has(_face_key(center,normal)): return
	missing_exposed_faces += 1
	var sources := _cached_tree_sources(neighbor,state)
	if not sources.is_empty(): phantom_tree_neighbors += 1
	print("BOUNDARY_EXPOSED_FACE_MISSING label=%s owner=%s owner_block=%d neighbor=%s direct_neighbor=%d normal=%s suppression_owner=%s suppression_neighbor=%s phantom_sources=%s" % [label,owner,owner_direct,neighbor,neighbor_direct,normal,state["suppression"].get(_key(owner),"none"),state["suppression"].get(_key(neighbor),"none"),sources])

func _check_pair(a: Vector2i,b: Vector2i,label: String) -> void:
	var a_state := _shipping_state(a)
	var b_state := _shipping_state(b)
	var a_lookup := _face_lookup(a,a_state["mesh"])
	var b_lookup := _face_lookup(b,b_state["mesh"])
	if b.x == a.x+1:
		var bx := b.x*CHUNK_SIZE
		for z in range(a.y*CHUNK_SIZE,a.y*CHUNK_SIZE+CHUNK_SIZE):
			var lh := int(data_ref.terrain_height(bx-1,z)); var rh := int(data_ref.terrain_height(bx,z))
			if lh > rh:
				for y in range(rh+1,lh+1): _diagnose_face(a_lookup,a_state,Vector3i(bx-1,y,z),Vector3i(bx,y,z),Vector3(bx,y+0.5,z+0.5),Vector3.RIGHT,label)
			elif rh > lh:
				for y in range(lh+1,rh+1): _diagnose_face(b_lookup,b_state,Vector3i(bx,y,z),Vector3i(bx-1,y,z),Vector3(bx,y+0.5,z+0.5),Vector3.LEFT,label)
	elif b.y == a.y+1:
		var bz := b.y*CHUNK_SIZE
		for x in range(a.x*CHUNK_SIZE,a.x*CHUNK_SIZE+CHUNK_SIZE):
			var nh := int(data_ref.terrain_height(x,bz-1)); var sh := int(data_ref.terrain_height(x,bz))
			if nh > sh:
				for y in range(sh+1,nh+1): _diagnose_face(a_lookup,a_state,Vector3i(x,y,bz-1),Vector3i(x,y,bz),Vector3(x+0.5,y+0.5,bz),Vector3.BACK,label)
			elif sh > nh:
				for y in range(nh+1,sh+1): _diagnose_face(b_lookup,b_state,Vector3i(x,y,bz),Vector3i(x,y,bz-1),Vector3(x+0.5,y+0.5,bz),Vector3.FORWARD,label)

func _init() -> void:
	if not ClassDB.class_exists(&"TeknikCarpathianSampler"):
		_fail("TeknikCarpathianSampler not loaded"); quit(1); return
	data_ref = ShippingData.new()
	var seen := {}
	for probe in PROBES:
		var cell: Vector2i = probe["cell"]
		var chunk := Vector2i(floori(float(cell.x)/CHUNK_SIZE),floori(float(cell.y)/CHUNK_SIZE))
		var lx := posmod(cell.x,CHUNK_SIZE); var lz := posmod(cell.y,CHUNK_SIZE)
		print("BOUNDARY_PROBE label=%s world=%s chunk=%s local=(%d,%d)" % [probe["label"],cell,chunk,lx,lz])
		if lx == CHUNK_SIZE-1:
			var b := chunk+Vector2i.RIGHT; var k := "%s>%s" % [chunk,b]
			if not seen.has(k): seen[k]=true; _check_pair(chunk,b,String(probe["label"])+"_east")
		if lz == CHUNK_SIZE-1:
			var b := chunk+Vector2i(0,1); var k := "%s>%s" % [chunk,b]
			if not seen.has(k): seen[k]=true; _check_pair(chunk,b,String(probe["label"])+"_south")
	print("BOUNDARY_TREE_TRACE expected=%d missing=%d phantom_tree_neighbors=%d suppression_terrain_air=%d" % [expected_exposed_faces,missing_exposed_faces,phantom_tree_neighbors,suppression_terrain_air])
	if missing_exposed_faces > 0 or suppression_terrain_air > 0:
		print("CHUNK_BOUNDARY_HOLE_REPRODUCED"); quit(1); return
	print("CHUNK_BOUNDARY_HOLE_NOT_REPRODUCED"); quit(0)
