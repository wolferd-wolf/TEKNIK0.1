extends RefCounted
class_name TextureGenerator

const SIZE := 32
const REGISTRY = preload("res://resources/textures/texture_block_registry.tres")
static var _texture_cache: Dictionary = {}

static func generate(block_type: String, seed: int) -> ImageTexture:
    var key := "%s:%d" % [block_type, seed]
    if _texture_cache.has(key): return _texture_cache[key]
    var config: TextureBlockConfig = REGISTRY.get_config(block_type)
    var texture := ImageTexture.create_from_image(_generate_image(config, seed))
    _texture_cache[key] = texture
    return texture

static func get_block_types() -> Array[String]: return REGISTRY.get_block_types()

static func _generate_image(c: TextureBlockConfig, seed: int) -> Image:
    var image := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
    if c == null or c.palette.is_empty(): image.fill(Color.MAGENTA); return image
    match c.material_style:
        "grass": _grass(image,c,seed)
        "soil": _soil(image,c,seed)
        "rock": _rock(image,c,seed)
        "sand": _sand(image,c,seed)
        "wood_grain": _wood(image,c,seed)
        "foliage": _foliage(image,c,seed)
        _: _generic(image,c,seed)
    if c.overlay_mode == "vein": _veins(image,c,seed)
    elif c.overlay_mode == "speckle": _speckles(image,c,seed)
    return image

static func _soil(im: Image,c: TextureBlockConfig,s:int)->void:
    im.fill(_p(c,1)); var a:=_p(c,0); var b:=_p(c,2); var h:=_p(c,3)
    _cluster(im,5,6,8,5,a,s+11,.72); _cluster(im,18,7,6,4,b,s+23,.68); _cluster(im,27,14,5,4,a,s+37,.70)
    _cluster(im,9,18,7,5,b,s+41,.70); _cluster(im,21,23,8,5,a,s+53,.72); _cluster(im,10,28,5,3,b,s+67,.68)
    for i in range(11):
        var x:=2+int(_hash(i,71,s+101)*28.0); var y:=2+int(_hash(i,89,s+103)*28.0)
        _cluster(im,x,y,1+i%2,1+(i+1)%2,h if i%4==0 else (a if i%3==0 else b),s+120+i,.58)

static func _rock(im: Image,c: TextureBlockConfig,s:int)->void:
    im.fill(_p(c,1)); var dark:=_p(c,0); var mid:=_p(c,1); var light:=_p(c,2); var hi:=_p(c,3)
    var plates=[[5,5,6,5],[15,5,6,4],[25,6,7,5],[8,15,7,6],[19,15,7,6],[29,17,4,6],[4,26,6,5],[14,26,7,4],[25,27,6,4]]
    for i in range(plates.size()):
        var q:Array=plates[i]; var x:int=q[0]; var y:int=q[1]; var w:int=q[2]; var h:int=q[3]
        _cluster(im,x+1,y+1,w,h,dark,s+201+i*17,.64); _cluster(im,x,y,w-1,h-1,light if i%3 else mid,s+241+i*17,.70)
        if i%2==0: _cluster(im,x-1,y-1,2,1,hi,s+281+i*17,.52)
    for i in range(7):
        _crack(im,2+int(_hash(i,301,s)*27.0),3+int(_hash(i,331,s)*25.0),2+i%3,1 if i%2 else -1,dark,s+351+i)

static func _wood(im: Image,c: TextureBlockConfig,s:int)->void:
    im.fill(_p(c,1)); var dark:=_p(c,0); var mid:=_p(c,1); var light:=_p(c,2); var hi:=_p(c,3)
    for band in range(6):
        var x0:=2+band*5+int(_hash(band,401,s)*3.0)
        for y in range(SIZE):
            var x:=x0+int(round(sin(y*.27+band*1.7+_hash(band,407,s)*5.0)*1.3))
            if x<0 or x>=SIZE: continue
            im.set_pixel(x,y,dark)
            if x+1<SIZE: im.set_pixel(x+1,y,mid)
            if y%3==0 and x+2<SIZE and _hash(x,y,s+421)>.55: im.set_pixel(x+2,y,hi)
    for i in range(3):
        var x:=6+int(_hash(i,451,s)*20.0); var y:=5+int(_hash(i,463,s)*22.0)
        _cluster(im,x,y,3,2,dark,s+471+i,.62)
        if x+3<SIZE: im.set_pixel(x+3,y,light)

static func _grass(im: Image,c: TextureBlockConfig,s:int)->void:
    im.fill(_p(c,1)); var dark:=_p(c,0); var base:=_p(c,2); var hi:=_p(c,3)
    _cluster(im,7,7,7,6,base,s+501,.70); _cluster(im,23,8,7,7,dark,s+517,.68); _cluster(im,12,21,8,6,base,s+533,.72); _cluster(im,27,25,5,5,dark,s+547,.66)
    for i in range(8): _blades(im,2+int(_hash(i,571,s)*28.0),3+int(_hash(i,593,s)*26.0),hi if i%3 else base,s+611+i)

static func _foliage(im: Image,c: TextureBlockConfig,s:int)->void:
    im.fill(_p(c,1)); var dark:=_p(c,0); var base:=_p(c,2); var hi:=_p(c,3)
    _cluster(im,7,8,7,6,dark,s+701,.70); _cluster(im,20,7,8,7,base,s+719,.70); _cluster(im,12,21,8,7,_p(c,1),s+733,.72); _cluster(im,27,24,6,5,dark,s+751,.68)
    for i in range(6): _cluster(im,3+int(_hash(i,771,s)*26.0),3+int(_hash(i,789,s)*26.0),2+i%2,2,hi if i%3==0 else base,s+801+i,.58)

static func _sand(im: Image,c: TextureBlockConfig,s:int)->void:
    im.fill(_p(c,1))
    for i in range(9):
        var x:=2+int(_hash(i,841,s)*28.0); var y:=2+int(_hash(i,859,s)*28.0)
        _cluster(im,x,y,2+i%2,1+i%2,_p(c,2) if i%3 else _p(c,0),s+877+i,.60)

static func _generic(im: Image,c: TextureBlockConfig,s:int)->void:
    im.fill(_p(c,1))
    for i in range(7):
        _cluster(im,3+int(_hash(i,901,s)*26.0),3+int(_hash(i,919,s)*26.0),3+i%3,2+(i+1)%3,_p(c,i%c.palette.size()),s+937+i,.62)

static func _cluster(im: Image,cx:int,cy:int,rx:int,ry:int,col:Color,s:int,bias:float)->void:
    rx=maxi(rx,1); ry=maxi(ry,1)
    for row in range(-ry,ry+1):
        var span=maxi(1,int(round(float(rx)*(1.0-absf(float(row)/ry)*.55))))
        var off=int(_hash(row+101,cy+103,s)*3.0)-1
        for colx in range(-span,span+1):
            var x:int=cx+colx+off; var y:int=cy+row
            if x<0 or x>=SIZE or y<0 or y>=SIZE: continue
            if absf(float(colx)/span)>.68 and _hash(x,y,s+17)>bias: continue
            im.set_pixel(x,y,col)

static func _crack(im:Image,x:int,y:int,length:int,dir:int,col:Color,s:int)->void:
    var cx:=x; var cy:=y
    for step in range(length):
        if cx>=0 and cx<SIZE and cy>=0 and cy<SIZE: im.set_pixel(cx,cy,col)
        cx+=1
        if _hash(step,y,s)>.45: cy+=dir

static func _blades(im:Image,cx:int,cy:int,col:Color,s:int)->void:
    for i in range(3):
        var x:=cx+i-1; var n:=2+int(_hash(i,cy,s)*3.0)
        for j in range(n):
            var y:=cy-j
            if x>=0 and x<SIZE and y>=0 and y<SIZE: im.set_pixel(x,y,col)

static func _speckles(im:Image,c:TextureBlockConfig,s:int)->void:
    if c.overlay_palette.is_empty(): return
    var count:=maxi(4,int(round(1024.0*c.overlay_density*.12)))
    for i in range(count):
        var x:=int(_hash(i,991,s+c.overlay_seed_offset)*SIZE); var y:=int(_hash(i,997,s+c.overlay_seed_offset+31)*SIZE)
        im.set_pixel(x,y,c.overlay_palette[int(_hash(i,1009,s)*c.overlay_palette.size())])

static func _veins(im:Image,c:TextureBlockConfig,s:int)->void:
    if c.overlay_palette.is_empty(): return
    var mask:=PackedByteArray(); mask.resize(SIZE*SIZE)
    for id in range(maxi(c.overlay_cluster_count,1)):
        var cs:=s+c.overlay_seed_offset+id*104729; var x:=int(_hash(id,17,cs)*SIZE); var y:=int(_hash(id,53,cs+97)*SIZE); var angle:=_hash(id,89,cs+193)*TAU
        for step in range(maxi(c.overlay_vein_length,2)):
            angle+=(_hash(step,id,cs+313)-.5)*.7; x+=int(round(cos(angle))); y+=int(round(sin(angle))); _vein_stamp(mask,x,y,maxi(c.overlay_vein_width,1),cs+step*17)
            if step>2 and _hash(step,id,cs+617)<c.overlay_density*.10:
                var branch:=angle+(PI*.5 if _hash(step,id,cs+911)>.5 else -PI*.5)
                for b in range(2,5): _vein_stamp(mask,x+int(round(cos(branch)*b)),y+int(round(sin(branch)*b)),maxi(c.overlay_vein_width,1),cs+b*31)
    for y in range(SIZE):
        for x in range(SIZE):
            if mask[y*SIZE+x]!=0: im.set_pixel(x,y,c.overlay_palette[int(_hash(x+7,y-13,s+c.overlay_seed_offset+4243)*c.overlay_palette.size())])

static func _vein_stamp(mask:PackedByteArray,cx:int,cy:int,w:int,s:int)->void:
    for oy in range(-w,w+1):
        for ox in range(-w,w+1):
            var x:=cx+ox; var y:=cy+oy
            if x<0 or x>=SIZE or y<0 or y>=SIZE: continue
            var d:int=abs(ox)+abs(oy); var keep:float=1.0 if d==0 else (.90 if d==1 else .30)
            if _hash(x,y,s)<keep: mask[y*SIZE+x]=1

static func _p(c:TextureBlockConfig,i:int)->Color: return c.palette[clampi(i,0,c.palette.size()-1)]
static func _hash(x:int,y:int,s:int)->float:
    var n:int=x*374761393+y*668265263+s*1442695041; n=(n^(n>>13))*1274126177; n=n^(n>>16); return float(n&0x7fffffff)/2147483647.0
