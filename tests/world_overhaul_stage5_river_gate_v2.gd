extends SceneTree

const DATA := preload("res://scripts/world/playable_world_stage5_generation_data.gd")
const STAGE4 := preload("res://scripts/world/playable_world_generation_data.gd")
const RUNTIME := preload("res://scripts/world/playable_world_generation_runtime.gd")
const WATER := preload("res://scripts/world/localized_water_bodies.gd")
const SIZE := 12
const PAD := 2
const CW := 16
const LIMIT := 1000
const START := -512
const FINISH := 512
const STEP := 4
const GW := 257
var failures: Array[String] = []

func _init() -> void:
	var d = DATA.new()
	var s4 = STAGE4.new()
	var r = RUNTIME.new()
	var field := _field(d)
	var audit := _audit(d, s4)
	var rc := Vector2i(int(audit["chunk_x"]), int(audit["chunk_z"]))
	var eq := _equivalence(r, d, rc)
	var water := _water(d, rc)
	var bench := _bench(r)
	if int(bench["p95_usec"]) >= LIMIT:
		_fail("Stage 5 generation exceeded 1.0 ms p95: %d usec" % int(bench["p95_usec"]))
	r.free()
	var report := {"field":field,"audit":audit,"equivalence":eq,"water":water,"benchmark":bench,"failures":failures}
	print("WORLD_OVERHAUL_STAGE5_JSON=%s" % JSON.stringify(report))
	if failures.is_empty():
		print("WORLD_OVERHAUL_STAGE5_PASS")
		quit(0)
		return
	for f: String in failures: push_error(f)
	quit(1)

func _field(d) -> Dictionary:
	var src := FileAccess.get_file_as_string("res://scripts/world/playable_world_stage5_cache_fast.gd")
	if DATA.WATER_RIVER == DATA.WATER_NONE or DATA.WATER_RIVER == DATA.WATER_OCEAN: _fail("River water type is not distinct")
	if src.contains("FastNoiseLite.new"): _fail("Stage 5 cache added FastNoiseLite")
	if not src.contains("river_lattice_values") or not src.contains("river_active_min"): _fail("Stage 5 cache lost meander-node/active-interval optimization")
	if src.contains("river_signal.resize") or src.contains("river_nodes"): _fail("Stage 5 cache persists redundant river arrays")
	if int(d.water_type_at(6,6)) != DATA.WATER_NONE: _fail("Default spawn is in water")
	var max_delta := 0.0
	var max_width_delta := 0.0
	var channel := 0
	var valley := 0
	for z: int in range(-384,385,8):
		for x: int in range(-384,385,8):
			var v := float(d.stage5_river_signal(x,z))
			max_delta = maxf(max_delta,maxf(absf(float(d.stage5_river_signal(x+1,z))-v),absf(float(d.stage5_river_signal(x,z+1))-v)))
			var c: float = d.continentalness_noise.get_noise_2d(float(x),float(z))
			var st: Vector2 = d.stage5_river_strengths_from_signal(c,v)
			if st.x >= DATA.STAGE5_CHANNEL_WATER_CUTOFF: channel += 1
			if st.y > 0.10: valley += 1
			var ec: float = d.continentalness_noise.get_noise_2d(float(x+1),float(z))
			max_width_delta = maxf(max_width_delta,absf(float(d.stage5_river_width_scale(ec))-float(d.stage5_river_width_scale(c))))
	if max_delta > 1.10: _fail("River block-distance field changes by more than 1.10 blocks per adjacent block")
	if max_width_delta > 0.04: _fail("River width changes too abruptly")
	if channel < 40 or valley < channel*2: _fail("River/valley field coverage is too weak")
	return {"max_neighbor_distance_blocks":max_delta,"max_width_delta":max_width_delta,"channel_samples":channel,"valley_samples":valley}

func _audit(d,s4) -> Dictionary:
	var rivers := PackedByteArray(); rivers.resize(GW*GW)
	var oceans := PackedByteArray(); oceans.resize(GW*GW)
	var river_count := 0
	var ocean_count := 0
	var mountain := 0
	var mountain_carve := 0
	var joins := 0
	var max_carve := 0
	var chosen := Vector2i.ZERO
	var found := false
	var gz := 0
	for z: int in range(START,FINISH+1,STEP):
		var gx := 0
		for x: int in range(START,FINISH+1,STEP):
			var f: Vector4 = d.sample_world_fields(x,z)
			var p := int(d.build_provisional_terrain(f))
			var h4 := int(s4.finalize_height(s4.apply_water_topology(f,p,x,z)))
			var ocean := int(s4.water_type_from_fields(f,h4)) == DATA.WATER_OCEAN
			var rv := float(d.stage5_river_signal(x,z))
			var st: Vector2 = d.stage5_river_strengths_from_signal(f.x,rv)
			var h5 := int(d.finalize_height(d.stage5_shape_height_from_signal(f.x,h4,rv)))
			var river := (not ocean) and st.x >= DATA.STAGE5_CHANNEL_WATER_CUTOFF
			var idx := gz*GW+gx
			if ocean:
				oceans[idx]=1; ocean_count+=1
			elif river:
				rivers[idx]=1; river_count+=1
				var carve := h4-h5; max_carve=maxi(max_carve,carve)
				if p>=48: mountain+=1; mountain_carve+=carve
				if not found and f.x>=DATA.STAGE4_COAST_INLAND_END and h5+1>DATA.SEA_LEVEL+1:
					chosen=Vector2i(floori(float(x)/SIZE),floori(float(z)/SIZE)); found=true
				if f.x<DATA.STAGE4_COAST_INLAND_END:
					for o: Vector2i in [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]:
						if bool(s4.is_ocean_column(x+o.x,z+o.y)): joins+=1; break
			gx+=1
		gz+=1
	var comps := _components(rivers,oceans)
	if river_count<128 or river_count>=int(GW*GW*0.20): _fail("River coverage outside accepted range")
	if mountain<8 or (mountain>0 and float(mountain_carve)/mountain<4.0): _fail("Mountain rivers do not create material valleys")
	if max_carve>DATA.STAGE5_MAX_VALLEY_CARVE+DATA.STAGE5_CHANNEL_DEPTH: _fail("River carve exceeded safety cap")
	if joins<4: _fail("Too few river/ocean joins")
	if int(comps["long"])<2 or int(comps["short"])>0: _fail("River corridors are fragmented")
	if not found: _fail("No inland river chunk above sea level")
	return {"sampled":GW*GW,"river_columns":river_count,"river_ratio":float(river_count)/(GW*GW),"ocean_columns":ocean_count,"mountain_river_columns":mountain,"maximum_carve":max_carve,"river_ocean_joins":joins,"components":comps,"chunk_x":chosen.x,"chunk_z":chosen.y}

func _components(rivers: PackedByteArray, oceans: PackedByteArray) -> Dictionary:
	var seen:=PackedByteArray(); seen.resize(rivers.size())
	var count:=0; var long:=0; var short:=0; var max_span:=0
	for start: int in range(rivers.size()):
		if rivers[start]==0 or seen[start]!=0: continue
		count+=1; var q:Array[int]=[start]; seen[start]=1; var cur:=0
		var minx:=GW; var maxx:=-1; var minz:=GW; var maxz:=-1; var edge:=false; var ocean_touch:=false
		while cur<q.size():
			var cell:=q[cur]; cur+=1; var x:=cell%GW; var z:=int(cell/GW)
			minx=mini(minx,x); maxx=maxi(maxx,x); minz=mini(minz,z); maxz=maxi(maxz,z)
			if x==0 or z==0 or x==GW-1 or z==GW-1: edge=true
			for o:Vector2i in [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]:
				var nx:=x+o.x; var nz:=z+o.y
				if nx<0 or nz<0 or nx>=GW or nz>=GW: continue
				var ni:=nz*GW+nx
				if oceans[ni]!=0: ocean_touch=true
				if rivers[ni]!=0 and seen[ni]==0: seen[ni]=1; q.append(ni)
		var span:=maxi(maxx-minx+1,maxz-minz+1)*STEP; max_span=maxi(max_span,span)
		if span>=96: long+=1
		if span<=SIZE and not edge and not ocean_touch: short+=1
	return {"count":count,"long":long,"short":short,"max_span_blocks":max_span}

func _equivalence(r,d,rc:Vector2i) -> Dictionary:
	var compared:=0; var river_cols:=0
	for c:Vector2i in [Vector2i.ZERO,Vector2i(3,-2),Vector2i(-7,5),rc]:
		var a:Dictionary=r._build_column_caches(c); var b:Dictionary=r._build_column_caches(c)
		if a["heights"]!=b["heights"] or a.has("river_signal"): _fail("Stage 5 cache nondeterministic or persists river array")
		var h:PackedInt32Array=a["heights"]; var ox:=c.x*SIZE; var oz:=c.y*SIZE
		for lz:int in range(-PAD,SIZE+PAD):
			for lx:int in range(-PAD,SIZE+PAD):
				var i:=(lz+PAD)*CW+lx+PAD; var wx:=ox+lx; var wz:=oz+lz
				if h[i]!=int(d.terrain_height(wx,wz)): _fail("Stage 5 cache/public height mismatch at (%d,%d)"%[wx,wz])
				if bool(d.is_river_column(wx,wz)): river_cols+=1
				compared+=1
	if river_cols==0: _fail("Equivalence set did not exercise river columns")
	return {"compared_columns":compared,"river_columns":river_cols}

func _water(d,rc:Vector2i) -> Dictionary:
	var wet:=0; var river:=0; var above:=0
	for z:int in range(SIZE):
		for x:int in range(SIZE):
			var info:Vector2i=d.water_info_at(rc.x*SIZE+x,rc.y*SIZE+z)
			if info.x==DATA.WATER_NONE: continue
			wet+=1
			if info.x==DATA.WATER_RIVER: river+=1; if info.y>DATA.SEA_LEVEL: above+=1
	var mesh:ArrayMesh=WATER.build_water_mesh(d,rc,SIZE)
	if mesh==null: _fail("Inland river chunk has no water mesh"); return {}
	var arr:Array=mesh.surface_get_arrays(0)
	var vertices:PackedVector3Array=arr[Mesh.ARRAY_VERTEX]
	var normals:PackedVector3Array=arr[Mesh.ARRAY_NORMAL]
	var indices:PackedInt32Array=arr[Mesh.ARRAY_INDEX]
	var top_vertices:=0
	var side_vertices:=0
	for normal:Vector3 in normals:
		if normal.y>0.9: top_vertices+=1
		elif absf(normal.y)<0.1: side_vertices+=1
	if top_vertices!=wet*4: _fail("River water top-face count mismatch")
	if indices.size()<wet*6 or indices.size()%6!=0: _fail("River water voxel index topology is invalid")
	if side_vertices==0: _fail("River water mesh has no exposed voxel side faces")
	var maxy:float=-999999.0
	for v:Vector3 in vertices: maxy=maxf(maxy,v.y)
	if river==0 or above==0 or maxy<=float(DATA.SEA_LEVEL)+0.5: _fail("River water is flattened to ocean plane")
	return {"water_cells":wet,"river_cells":river,"above_sea":above,"max_vertex_y":maxy,"top_vertices":top_vertices,"side_vertices":side_vertices}

func _bench(r) -> Dictionary:
	var coords:Array[Vector2i]=[Vector2i(-4,-2),Vector2i(-2,1),Vector2i(0,0),Vector2i(1,0),Vector2i(2,-1),Vector2i(4,2),Vector2i(8,-4),Vector2i(11,-3),Vector2i(12,-2),Vector2i(13,-2),Vector2i(14,-1),Vector2i(15,0),Vector2i(16,1),Vector2i(18,-4),Vector2i(20,2),Vector2i(-8,5)]
	for _w:int in range(4): for c:Vector2i in coords: r._build_column_caches(c)
	var times:Array[int]=[]
	for rep:int in range(20):
		for i:int in range(coords.size()):
			var c:Vector2i=coords[(i+rep)%coords.size()]; var t:=Time.get_ticks_usec(); r._build_column_caches(c); times.append(maxi(1,Time.get_ticks_usec()-t))
	times.sort(); var total:=0
	for t:int in times: total+=t
	var p:=clampi(ceili(float(times.size())*0.95)-1,0,times.size()-1)
	return {"sample_count":times.size(),"mean_usec":float(total)/times.size(),"p95_usec":times[p],"p95_ms":float(times[p])/1000.0,"minimum_usec":times[0],"maximum_usec":times[-1]}

func _fail(message:String)->void:
	if not failures.has(message): failures.append(message)
