# SPDX-License-Identifier: GPL-2.0-only
extends Control
## Executes original Cotopha presentation calls in source order on an 800x600 stage.
## Text, choices and persistent flags remain in player.gd / story_flow.gd.

const RELATION := {2:10, 3:50, 4:70, 5:20, 6:60, 7:40, 8:80, 9:30, 10:90, 11:15, 12:0, 99:0}
const PRIORITY := {2:52, 3:55, 4:51, 5:56, 6:54, 7:58, 8:57, 9:53, 10:60, 11:59, 12:0, 99:0}
const CHARACTER_IDS := {"CA":4,"CB":3,"CC":2,"CD":5,"CE":6,"CF":7,"CG":8,"CH":9,"CI":12,"CJ":10,"CK":11,"CL":99}
const AUTO_POS := {1:[6],2:[4,8],3:[3,6,9],4:[3,5,7,9],5:[2,4,6,8,10]}
const TONE_SHADER := """shader_type canvas_item;
uniform int tone = 0;
uniform bool dark_mode = false;
void fragment() {
    // Fragment COLOR already contains the sampled texture and vertex tint.
    vec4 c = COLOR;
    if (dark_mode) c *= texture(TEXTURE, UV);
    if (tone == 1 || tone == 3) c.rgb = vec3(dot(c.rgb, vec3(0.299,0.587,0.114)));
    if (tone == 2 || tone == 3) c.rgb = vec3(1.0)-c.rgb;
    COLOR = c;
}
"""
const TRANSITION_SHADER := """shader_type canvas_item;
uniform sampler2D mask_image;
uniform bool has_mask = false;
uniform float progress : hint_range(0.0,1.0) = 0.0;
void fragment() {
    vec4 c = texture(TEXTURE,UV);
    float alpha = 1.0-progress;
    if (has_mask) {
        float m = texture(mask_image,UV).r;
        alpha = 1.0-smoothstep(m-0.03,m+0.03,progress*1.06-0.03);
    }
    if (progress <= 0.0) alpha = 1.0;
    if (progress >= 1.0) alpha = 0.0;
    COLOR = vec4(c.rgb,c.a*alpha);
}
"""
# Transparent viewport textures contain premultiplied color. Mix complete
# foreground frames, rather than layering old actors over the new actors.
const FOREGROUND_SHADER := """shader_type canvas_item;
render_mode blend_premul_alpha;
uniform sampler2D old_frame;
uniform sampler2D mask_image;
uniform bool active = false;
uniform bool has_mask = false;
uniform float progress = 1.0;
void fragment() {
    vec4 current = texture(TEXTURE, UV);
    if (active) {
        float alpha = 1.0-progress;
        if (has_mask) {
            float m = texture(mask_image,UV).r;
            alpha = 1.0-smoothstep(m-0.03,m+0.03,progress*1.06-0.03);
        }
        if (progress <= 0.0) alpha = 1.0;
        if (progress >= 1.0) alpha = 0.0;
        current = mix(current,texture(old_frame,UV),alpha);
    }
    COLOR = current;
}
"""
const BLACK_MASK_SHADER := """shader_type canvas_item;
void fragment() { COLOR = vec4(vec3(0.0), (1.0-texture(TEXTURE, UV).r) * COLOR.a); }
"""

var reader: Control
var viewport: SubViewport
var world: Node2D
var stage: Node2D
var background: Sprite2D
var fill: ColorRect
var output: TextureRect
var background_viewport: SubViewport
var foreground_viewport: SubViewport
var effect_viewport: SubViewport
var background_output: TextureRect
var foreground_output: TextureRect
var effect_output: TextureRect
var background_overlay: Sprite2D
var foreground_overlay: Sprite2D
var display_mode := "original"
var preview_active := false
var color_preview_views: Array[SubViewport] = []
var movie_active := false
var overlay: Sprite2D
var tone_material: ShaderMaterial
var transition_material: ShaderMaterial
var sprites: Dictionary = {}
var state: Dictionary = {}
var pending: Dictionary = {}
var queued: Array = []
var transition := {"type":"", "duration":0.5}
var changed := false
var skip_requested := false
var fast_test := false
var error := ""
var jobs: Array = []
var clock := 0.0
var next_job := 0
var environment: Dictionary = {}
var music_players: Array[AudioStreamPlayer] = []
var music_index := 0
var flash: ColorRect
var flash_image: Sprite2D
var eyecatch: Dictionary = {}
var transients: Array = []
var actor_centers: Dictionary = {}
var animation_textures: Dictionary = {}


func setup(host: Control) -> void:
	reader = host
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	viewport = SubViewport.new()
	viewport.size = Vector2i(800,600)
	viewport.world_2d = World2D.new()
	viewport.canvas_cull_mask = 15
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.disable_3d = true
	add_child(viewport)
	var black_base:=ColorRect.new()
	black_base.color=Color.BLACK
	black_base.visibility_layer=2
	black_base.size=Vector2(800,600)
	black_base.z_index=-1000
	viewport.add_child(black_base)
	world = Node2D.new()
	world.visibility_layer = 3
	viewport.add_child(world)
	stage = Node2D.new()
	stage.visibility_layer = 3
	world.add_child(stage)
	tone_material = ShaderMaterial.new()
	var shader := Shader.new()
	shader.code = TONE_SHADER
	tone_material.shader = shader
	fill = ColorRect.new()
	fill.size = Vector2(800,600)
	fill.visibility_layer = 2
	fill.z_index=-100
	fill.material = tone_material
	stage.add_child(fill)
	background = Sprite2D.new()
	background.centered = false
	background.visibility_layer = 2
	background.material = tone_material
	stage.add_child(background)
	output = TextureRect.new()
	output.texture = viewport.get_texture()
	output.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	output.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	output.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(output)
	output.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay = Sprite2D.new()
	overlay.centered = false
	overlay.visibility_layer = 8
	overlay.z_index = 600
	overlay.hide()
	viewport.add_child(overlay)
	transition_material = ShaderMaterial.new()
	shader = Shader.new()
	shader.code = TRANSITION_SHADER
	transition_material.shader = shader
	overlay.material = transition_material
	background_viewport = _layer_viewport(18)
	foreground_viewport = _layer_viewport(1)
	effect_viewport = _layer_viewport(4)
	background_output = _layer_output(background_viewport,TextureRect.STRETCH_KEEP_ASPECT_COVERED)
	foreground_output = _layer_output(foreground_viewport,TextureRect.STRETCH_KEEP_ASPECT_CENTERED)
	effect_output = _layer_output(effect_viewport,TextureRect.STRETCH_KEEP_ASPECT_COVERED)
	var foreground_shader := Shader.new()
	foreground_shader.code = FOREGROUND_SHADER
	var foreground_material := ShaderMaterial.new()
	foreground_material.shader = foreground_shader
	foreground_output.material = foreground_material
	var effect_material := CanvasItemMaterial.new()
	effect_material.blend_mode = CanvasItemMaterial.BLEND_MODE_PREMULT_ALPHA
	effect_output.material = effect_material
	background_overlay = _layer_overlay(16)
	foreground_overlay = _layer_overlay(32)
	visibility_changed.connect(_refresh_compositor)
	flash = ColorRect.new()
	flash.size = Vector2(800,600)
	flash.visibility_layer = 4
	flash.z_index = 700
	flash.hide()
	viewport.add_child(flash)
	flash_image = Sprite2D.new()
	flash_image.centered = false
	flash_image.visibility_layer = 4
	flash_image.z_index = 700
	flash_image.hide()
	viewport.add_child(flash_image)
	for index in range(2):
		var audio := AudioStreamPlayer.new()
		add_child(audio)
		music_players.append(audio)
	reset()


func _layer_viewport(mask: int) -> SubViewport:
	var layer := SubViewport.new()
	layer.size = Vector2i(800,600)
	layer.world_2d = viewport.world_2d
	layer.canvas_cull_mask = mask
	layer.transparent_bg = true
	layer.disable_3d = true
	layer.gui_disable_input = true
	layer.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(layer)
	return layer


func _layer_output(layer: SubViewport, stretch: int) -> TextureRect:
	var image := TextureRect.new()
	image.texture = layer.get_texture()
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image.stretch_mode = stretch
	image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(image)
	image.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return image


func _layer_overlay(mask: int) -> Sprite2D:
	var image := Sprite2D.new()
	image.centered = false
	image.visibility_layer = mask
	image.z_index = 600
	image.material = transition_material
	image.hide()
	viewport.add_child(image)
	return image


func set_display_mode(mode: String) -> void:
	display_mode = mode
	_refresh_compositor()


func set_color_mode(mode: String) -> void:
	tone_material.set_shader_parameter("dark_mode",mode=="dark")


func clear_color_previews() -> void:
	for view in color_preview_views:
		view.render_target_update_mode = SubViewport.UPDATE_DISABLED
		view.queue_free()
	color_preview_views.clear()


func create_color_previews() -> Dictionary:
	clear_color_previews()
	var result := {}
	for mode in ["light","dark"]:
		var backdrop := SubViewport.new()
		backdrop.size = Vector2i(800,600)
		backdrop.world_2d = World2D.new()
		backdrop.transparent_bg = true
		backdrop.disable_3d = true
		backdrop.gui_disable_input = true
		backdrop.canvas_cull_mask = 2
		backdrop.render_target_update_mode = SubViewport.UPDATE_ONCE
		add_child(backdrop)
		color_preview_views.append(backdrop)
		var copy: Node2D = world.duplicate()
		var shade := ShaderMaterial.new()
		shade.shader = tone_material.shader
		shade.set_shader_parameter("tone",tone_material.get_shader_parameter("tone"))
		shade.set_shader_parameter("dark_mode",mode=="dark")
		_recolor_preview(copy,shade)
		backdrop.add_child(copy)
		var foreground := SubViewport.new()
		foreground.size = Vector2i(800,600)
		foreground.world_2d = backdrop.world_2d
		foreground.transparent_bg = true
		foreground.disable_3d = true
		foreground.gui_disable_input = true
		foreground.canvas_cull_mask = 1
		foreground.render_target_update_mode = SubViewport.UPDATE_ONCE
		add_child(foreground)
		color_preview_views.append(foreground)
		result[mode] = {"background":backdrop.get_texture(),"foreground":foreground.get_texture()}
	return result


func _recolor_preview(node: Node, shade: ShaderMaterial) -> void:
	if node is CanvasItem and node.material==tone_material:node.material=shade
	for child in node.get_children():_recolor_preview(child,shade)


func set_preview_active(active: bool) -> void:
	preview_active = active
	_refresh_compositor()


func _refresh_compositor() -> void:
	if background_viewport == null:return
	var active: bool = is_visible_in_tree() and reader != null and not reader.on_title and not reader.application_paused and viewport.render_target_update_mode != SubViewport.UPDATE_DISABLED
	var split := display_mode=="crop"
	for layer in [background_viewport,foreground_viewport,effect_viewport]:
		layer.render_target_update_mode = SubViewport.UPDATE_ALWAYS if active and (split or preview_active) else SubViewport.UPDATE_DISABLED
	output.visible = not split
	output.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	background_output.visible = split and not movie_active
	foreground_output.visible = split
	effect_output.visible = split
	_fit_effect_nodes()


func _fit_effect_nodes() -> void:
	if size.x<=0 or size.y<=0:return
	var source := Vector2(800,600)
	var fit := minf(size.x/800.0,size.y/600.0)
	var cover := maxf(size.x/800.0,size.y/600.0)
	for node in eyecatch.get("nodes",[]):
		if node.get_meta("effect_cover_full",false):continue
		if not node.has_meta("effect_position"):
			node.set_meta("effect_position",node.position)
			node.set_meta("effect_scale",node.scale)
		var position: Vector2 = node.get_meta("effect_position")
		var scale: Vector2 = node.get_meta("effect_scale")
		if display_mode=="crop":
			node.position = (position*fit+(size-source*fit)*0.5-(size-source*cover)*0.5)/cover
			node.scale = scale*fit/cover
		else:
			node.position = position
			node.scale = scale


func reset() -> void:
	jobs.clear()
	for transient in transients:
		if is_instance_valid(transient.node):transient.node.queue_free()
	transients.clear()
	queued.clear()
	for audio in music_players:
		audio.stop()
	for audio in get_children():
		if audio is AudioStreamPlayer and audio not in music_players:audio.queue_free()
	environment.clear()
	state = {"background":"", "color":[0,0,0], "crop":[0,0], "zoom":[400,300,800,600],
		"characters":[], "tone":"", "music":"", "music_paused":false,"ambient":[], "font":0, "window":0}
	pending = state.duplicate(true)
	changed = false
	transition = {"type":"", "duration":0.5}
	error = ""
	for node in eyecatch.get("nodes",[]):node.queue_free()
	eyecatch.clear()
	overlay.hide()
	background_overlay.hide()
	foreground_overlay.hide()
	(foreground_output.material as ShaderMaterial).set_shader_parameter("active",false)
	flash.hide()
	flash_image.hide()
	_apply_scene(state)


func snapshot() -> Dictionary:
	var saved:=state.duplicate(true)
	for character in saved.characters:
		var id:=str(int(character.id))
		if sprites.has(id) and sprites[id].has_meta("animation_frame"):
			character.animation_frame=int(sprites[id].get_meta("animation_frame"))
	return saved


func restore(saved: Dictionary) -> void:
	jobs.clear()
	queued.clear()
	for transient in transients:
		if is_instance_valid(transient.node):transient.node.queue_free()
	transients.clear()
	for node in eyecatch.get("nodes",[]):node.queue_free()
	eyecatch.clear()
	overlay.hide()
	background_overlay.hide()
	foreground_overlay.hide()
	(foreground_output.material as ShaderMaterial).set_shader_parameter("active",false)
	flash.hide()
	flash_image.hide()
	state = saved.duplicate(true)
	pending = state.duplicate(true)
	changed = false
	for sprite in sprites.values():sprite.set_meta("asset","")
	_apply_scene(state)
	for audio in music_players:
		audio.stop()
	if not str(state.get("music", "")).is_empty():
		var paused: bool=state.get("music_paused",false)
		_music(str(state.music), true)
		music_players[music_index].stream_paused=paused
		state.music_paused=paused
		pending.music_paused=paused
	for audio in get_children():
		if audio is AudioStreamPlayer and audio not in music_players:audio.queue_free()
	environment.clear()
	for asset in state.get("ambient", []):
		_environment(str(asset), false)


func texture(asset: String) -> Texture2D:
	return reader._texture(asset.strip_edges().to_upper())


func _apply_scene(scene: Dictionary) -> void:
	fill.color = Color8(int(scene.color[0]),int(scene.color[1]),int(scene.color[2]))
	background.texture = texture(str(scene.background))
	background.region_enabled=false
	background.position = -Vector2(scene.crop[0],scene.crop[1])
	var zoom: Array = scene.zoom
	stage.scale = Vector2(800.0/maxf(zoom[2],1),600.0/maxf(zoom[3],1))
	if int(zoom[2])!=800 or int(zoom[3])!=600:stage.scale+=Vector2.ONE*0.01
	stage.position = -Vector2(zoom[0]-zoom[2]*0.5,zoom[1]-zoom[3]*0.5)*stage.scale
	var modes := {"":0,"NORMAL":0,"MONOCHROME":1,"NEGATIVE":2,"MONO_NEGATIVE":3}
	tone_material.set_shader_parameter("tone",modes.get(scene.tone,0))
	for sprite in sprites.values():
		sprite.hide()
	var active_assets: Array=scene.characters.map(func(c):return str(c.asset))
	for asset in animation_textures.keys():
		if asset not in active_assets:animation_textures.erase(asset)
	for character in scene.characters:
		var id := str(int(character.id))
		if not sprites.has(id):
			var sprite := Sprite2D.new()
			sprite.centered = false
			sprite.material = tone_material
			stage.add_child(sprite)
			sprites[id] = sprite
		var sprite: Sprite2D = sprites[id]
		var previous_asset:=str(sprite.get_meta("asset",""))
		sprite.texture = texture(str(character.asset))
		sprite.set_meta("asset",str(character.asset))
		var animations: Dictionary=reader.story.get("native_animations",{})
		if animations.has(str(character.asset)):
			if previous_asset!=str(character.asset):
				sprite.set_meta("animation_start",clock)
				sprite.set_meta("animation_offset",int(character.get("animation_frame",randi_range(0,26))))
			var animation_frame:=int(sprite.get_meta("animation_offset",0))
			sprite.texture=_animation_texture(str(character.asset),animation_frame)
			sprite.set_meta("animation_frame",animation_frame)
		else:
			sprite.remove_meta("animation_frame")
		if sprite.texture == null:
			continue  # Original missing-resource behavior, audited at conversion.
		var dimensions := sprite.texture.get_size()
		# Keep the source slot and bottom anchor; compensate asymmetric padding
		# as requested for this port instead of centering the PNG's empty canvas.
		var asset:=str(character.asset)
		if not actor_centers.has(asset):
			var recorded: Dictionary=reader.story.get("native_actor_centers",{}).get(asset,{})
			if recorded.has_all(["x","width","height"]) and int(recorded.width)==int(dimensions.x) and int(recorded.height)==int(dimensions.y):
				actor_centers[asset]=float(recorded.x)
			else:
				var image:=sprite.texture.get_image()
				if image!=null and image.is_compressed():image.decompress()
				var bounds:=image.get_used_rect() if image!=null and not image.is_compressed() else Rect2i()
				actor_centers[asset]=bounds.position.x+bounds.size.x*0.5 if bounds.has_area() else dimensions.x*0.5
		sprite.position = Vector2(character.x-float(actor_centers[asset]),character.y-dimensions.y+50)
		# Entis paints lower numeric priorities in front, within the actor group.
		sprite.z_index = 500-int(character.priority)
		sprite.modulate = Color.WHITE
		sprite.show()


func _adjust_positions() -> void:
	var automatic: Array = pending.characters.filter(func(c): return not c.fixed)
	automatic.sort_custom(func(a,b): return RELATION.get(int(a.id),0)<RELATION.get(int(b.id),0))
	var positions: Array = AUTO_POS.get(automatic.size(),[])
	for i in range(automatic.size()):
		var character: Dictionary = automatic[i]
		if int(character.pos)<0:
			character.pos = -int(character.pos)
		else:
			character.pos = positions[i]
	for character in pending.characters:
		character.x = maxf(float(character.pos)-1.0,0)*80.0


func _arg(args: Array, index: int, fallback = 0):
	return args[index] if index<args.size() else fallback


func execute(command: String, args: Array) -> bool:
	skip_requested = false
	match command:
		"SetCg", "SetCgRGB":
			pending.characters = []
			if command == "SetCgRGB":
				pending.background = ""
				pending.color = [args[0],args[1],args[2]]
			else:
				var asset := str(_arg(args,0,"")).strip_edges().to_upper()
				pending.background = "" if asset in ["BLACK","WHITE"] else asset
				pending.color = [255,255,255] if asset=="WHITE" else [0,0,0]
				pending.crop = [_arg(args,1),_arg(args,2)]
				pending.zoom = [400,300,800,600]
			changed = true
		"SetBustup":
			var asset := str(_arg(args,0,"")).strip_edges().to_upper()
			var id := -1
			for prefix in CHARACTER_IDS:
				if asset.contains(prefix):
					id = CHARACTER_IDS[prefix]
					break
			var matches: Array = pending.characters.filter(func(c):return int(c.id)==id)
			var character: Dictionary
			if matches.is_empty():
				if pending.characters.size()>=5:return true
				character = {"id":id,"asset":asset,"pos":int(_arg(args,1)),"fixed":int(_arg(args,1))>0,
					"x":400.0,"y":600.0,"priority":PRIORITY.get(id,0)}
				pending.characters.append(character)
			else:
				character = matches[0]
				character.asset = asset
				if int(_arg(args,1))!=0:
					character.pos = int(args[1])
					character.fixed = int(args[1])>0
			if int(_arg(args,2))!=0:
				character.priority = int(args[2])
			elif matches.is_empty():
				character.priority += 20 if asset.contains("S") else (-20 if asset.contains("L") else 0)
			changed = true
		"BustupClear":
			var id := int(_arg(args,0))
			pending.characters = [] if id==0 else pending.characters.filter(func(c):return int(c.id)!=id)
			changed = true
		"Down", "Jump", "Shake", "BustupLeave":
			queued.append({"command":command,"args":args})
			changed = true
		"Transition":
			transition = {"type":str(_arg(args,0,"")),"duration":float(_arg(args,1))/1000.0}
		"Commit", "Update":
			await _commit(command=="Update" and int(_arg(args,0))!=0)
		"BlackOut", "WhiteOut":
			if int(_arg(args,1))!=0:
				reader.dialogue.hide()
			await execute("SetCg",["BLACK" if command=="BlackOut" else "WHITE"])
			transition={"type":"","duration":float(_arg(args,0,1000))/1000.0 if int(_arg(args,0))!=0 else 1.0}
			await _commit(false)
		"Tone":
			pending.tone = str(_arg(args,0,"")).to_upper()
			changed = true
		"Scroll":
			var target := Vector2(_arg(args,0),_arg(args,1))
			var duration := float(_arg(args,2))/1000.0
			pending.crop = [target.x,target.y]
			if changed:
				queued.append({"command":"Scroll","args":args})
			else:
				state.crop = pending.crop.duplicate()
				_animate(background,"position",background.position,-target,duration,float(_arg(args,3)))
				if int(_arg(args,4))!=0:
					await _wait(duration)
		"WaitScroll":
			await _wait_jobs(background)
		"Zoom":
			var zoom := [args[0],args[1],args[2],args[3]]
			pending.zoom = zoom
			if not changed:
				state.zoom = zoom.duplicate()
				var magnification := Vector2(800.0/float(zoom[2]),600.0/float(zoom[3]))
				# Source adds 0.01 only while zoomed to avoid a sampling seam.
				if int(zoom[2])!=800 or int(zoom[3])!=600:
					magnification += Vector2.ONE*0.01
				var position := -Vector2(zoom[0]-zoom[2]*0.5,zoom[1]-zoom[3]*0.5)*magnification
				_animate(stage,"scale",stage.scale,magnification,float(_arg(args,4))/1000.0,float(_arg(args,5)))
				_animate(stage,"position",stage.position,position,float(_arg(args,4))/1000.0,float(_arg(args,5)))
		"Quake":
			await _quake(args)
		"Flush":
			await _commit(true)
			var colors := {"BLACK":Color.BLACK,"WHITE":Color.WHITE,"RED":Color.RED,"GREEN":Color.GREEN,"BLUE":Color.BLUE}
			var color := str(args[0]).to_upper()
			var target: CanvasItem = flash if colors.has(color) else flash_image
			if target==flash:
				flash.color = colors[color]
			else:
				flash_image.texture = texture(color)
			target.modulate.a=1.0
			target.show()
			_animate(target,"modulate:a",1.0,0.0,float(_arg(args,1))/1000.0)
			await _wait(float(_arg(args,1))/1000.0)
			target.hide()
		"ScWait":
			await _wait(float(_arg(args,0))/1000.0,int(_arg(args,1))==0)
		"Hide":
			reader.dialogue.hide()
		"WindowView":
			state.window = int(_arg(args,0))
			pending.window = state.window
		"Font":
			state.font = int(_arg(args,0))
			pending.font = state.font
		"ScPlayBgm":
			_music(str(args[0]).to_upper(),int(_arg(args,1))!=0)
		"ScStopBgm":
			_stop_music(int(_arg(args,0))!=0)
		"ScPauseBgm", "ScRestartBgm":
			music_players[music_index].stream_paused = command=="ScPauseBgm"
			state.music_paused=command=="ScPauseBgm"
			pending.music_paused=state.music_paused
		"ScPlayEnvSe":
			_environment(str(args[0]).to_upper(),int(_arg(args,1))!=0 if not _arg(args,1) is String else false)
		"ScStopEnvSe":
			_stop_environment(str(_arg(args,0,"")).to_upper(),int(_arg(args,1))!=0)
		"ScPlaySe", "ScPlayVoice":
			var audio: AudioStreamPlayer = reader.sound_player if command=="ScPlaySe" else reader.voice_player
			reader._play(audio,str(args[0]).to_upper())
			if command=="ScPlaySe" and int(_arg(args,1))!=0:
				await _wait_audio(audio)
		"ScStopSe":
			reader.sound_player.stop()
		"ScWaitVoice":
			await _wait_audio(reader.voice_player)
		"EyeCatchEnter":
			await _eye_enter(str(_arg(args,0,"")),int(_arg(args,1))!=0)
		"StaffRoll":
			await _staff_roll(int(args[0]))
		"ScPlayMovie":
			await _movie(str(args[0]))
		"EnableKeyUpdateFlush":
			pass  # Source uses this only inside an unreachable If 0 debug block.
		_:
			error = "Unknown original presentation command: "+command
	return error.is_empty()


func _commit(immediate: bool, finish_eye:=true) -> void:
	if not changed:
		return
	_adjust_positions()
	var previous: ImageTexture
	var previous_background: ImageTexture
	var previous_foreground: ImageTexture
	if not immediate and not fast_test:
		await RenderingServer.frame_post_draw
		previous = ImageTexture.create_from_image(viewport.get_texture().get_image())
		if display_mode=="crop":
			previous_background = ImageTexture.create_from_image(background_viewport.get_texture().get_image())
			previous_foreground = ImageTexture.create_from_image(foreground_viewport.get_texture().get_image())
	var old_crop := background.position
	state = pending.duplicate(true)
	_apply_scene(state)
	changed = false
	if previous!=null:
		overlay.texture=previous
		transition_material.set_shader_parameter("progress",0.0)
		var mask := texture(str(transition.type))
		transition_material.set_shader_parameter("has_mask",mask!=null)
		if mask!=null:
			transition_material.set_shader_parameter("mask_image",mask)
		overlay.show()
		if previous_background != null:
			background_overlay.texture = previous_background
			foreground_overlay.texture = previous_foreground
			background_overlay.show()
			foreground_overlay.show()
			(foreground_output.material as ShaderMaterial).set_shader_parameter("old_frame",previous_foreground)
			(foreground_output.material as ShaderMaterial).set_shader_parameter("active",true)
			_sync_foreground_transition()
		_animate(transition_material,"shader_parameter/progress",0.0,1.0,float(transition.duration))
	for action in queued:
		var args: Array=action.args
		if action.command=="Scroll":
			var target:=background.position
			background.position=old_crop
			_animate(background,"position",old_crop,target,float(_arg(args,2))/1000.0,float(_arg(args,3)))
	if previous!=null:
		await _wait(float(transition.duration))
		overlay.hide()
		background_overlay.hide()
		foreground_overlay.hide()
		(foreground_output.material as ShaderMaterial).set_shader_parameter("active",false)
	transition={"type":"","duration":0.5}
	for action in queued:
		if action.command!="Scroll":
			await _actor_action(action.command,action.args,immediate)
	queued.clear()
	pending = state.duplicate(true)
	if finish_eye and not eyecatch.is_empty():
		await _eye_leave()


func _actor_action(command: String, args: Array, immediate: bool) -> void:
	var id:=str(int(args[0]))
	if not sprites.has(id) or not sprites[id].visible:
		return
	var sprite: Sprite2D=sprites[id]
	var origin:=sprite.position
	var characters: Array=state.characters.filter(func(c):return str(int(c.id))==id)
	if command=="Down":
		var mv:=float(_arg(args,1))
		if mv==0:mv=50
		if mv==-1:mv=600.0-float(characters[0].y)
		var duration:=float(_arg(args,2))/1000.0
		if duration==0:duration=1.0
		if duration<0 or immediate:duration=0
		characters[0].y+=mv
		_animate(sprite,"position",origin,origin+Vector2(0,mv),duration,float(_arg(args,3,3)))
	elif command=="BustupLeave":
		var duration:=float(_arg(args,4))/1000.0 if not immediate else 0.0
		var leave: Sprite2D=sprite.duplicate()
		world.add_child(leave)
		leave.global_transform=sprite.global_transform
		leave.z_index=650
		sprite.hide()
		origin=leave.position
		_animate(leave,"position",origin,origin+Vector2(_arg(args,1),_arg(args,2)),duration,float(_arg(args,5)))
		if int(_arg(args,3))!=0:_animate(leave,"modulate:a",1.0,0.0,duration)
		state.characters=state.characters.filter(func(c):return str(int(c.id))!=id)
		if fast_test or duration<=0:leave.queue_free()
		else:transients.append({"node":leave,"end":clock+duration})
	elif not immediate:
		if command=="Jump":
			await _move(sprite,origin,origin+Vector2(0,-25),0.2,3)
			await _move(sprite,sprite.position,origin,0.2,3)
		else:
			await _shake_target(sprite,25,0,1,0.03,3.0)


func _quake(args: Array) -> void:
	var target: Node2D=world
	var ghost: Sprite2D
	if int(_arg(args,2))==0:
		ghost=background.duplicate()
		stage.add_child(ghost)
		ghost.z_index=100
		ghost.modulate.a=(256.0-98.0)/256.0
		target=ghost
	await _shake_target(target,float(args[0]),float(args[1]),int(_arg(args,3)),float(_arg(args,4,30))/1000.0)
	if ghost!=null:ghost.queue_free()


func _shake_target(target: Node2D, w: float, h: float, count: int, duration: float, acceleration:=NAN) -> void:
	var origin:=target.position
	var offset:=Vector2(w,h)
	if duration==0:duration=0.03
	await _move(target,origin,origin-offset,duration,acceleration)
	for i in range(count+1):
		await _move(target,target.position,origin+offset,duration*2,acceleration)
		if i<count:await _move(target,target.position,origin-offset,duration*2,acceleration)
	await _move(target,target.position,origin,duration,acceleration)


func _move(target: Object, start: Vector2, finish: Vector2, duration: float, acceleration:=NAN) -> void:
	_animate(target,"position",start,finish,duration,acceleration)
	await _wait(duration)


func _animate(target: Object, property: String, start, finish, duration: float, acceleration:=NAN) -> void:
	jobs=jobs.filter(func(job):return job.target!=target or job.property!=property)
	if fast_test or duration<=0:
		_set_property(target,property,finish)
		return
	jobs.append({"target":target,"property":property,"start":start,"finish":finish,
		"begin":clock,"duration":duration,"accel":acceleration})


# Original Bezier2D.SetLinear followed by SetAcceleration(a0, 0).
func _source_curve(t: float, a0: float) -> float:
	return a0*t*(1.0-t)*(1.0-t)+3.0*(1.0-t)*t*t+t*t*t


func _sync_foreground_transition() -> void:
	if not foreground_overlay.visible:return
	var material: ShaderMaterial = foreground_output.material
	material.set_shader_parameter("progress",transition_material.get_shader_parameter("progress"))
	var has_mask: bool = transition_material.get_shader_parameter("has_mask")
	material.set_shader_parameter("has_mask",has_mask)
	if has_mask:material.set_shader_parameter("mask_image",transition_material.get_shader_parameter("mask_image"))


func _process(delta: float) -> void:
	_refresh_compositor()
	if reader==null or reader.application_paused or reader.modal.visible or reader.on_title:
		return
	clock+=delta
	for job in jobs:
		if not is_instance_valid(job.target):continue
		var amount:=clampf((clock-float(job.begin))/float(job.duration),0,1)
		if not is_nan(float(job.accel)):amount=_source_curve(amount,float(job.accel))
		_set_property(job.target,job.property,lerp(job.start,job.finish,amount))
	_sync_foreground_transition()
	jobs=jobs.filter(func(job):return is_instance_valid(job.target) and clock<float(job.begin)+float(job.duration))
	for transient in transients:
		if clock>=float(transient.end) and is_instance_valid(transient.node):transient.node.queue_free()
	transients=transients.filter(func(transient):return clock<float(transient.end))
	for audio in music_players:
		if audio.playing and audio.stream!=null:
			var asset:=str(audio.get_meta("asset",""))
			var loops: Dictionary=reader.story.get("native_music_loops",{})
			if loops.has(asset):
				var loop: Array=loops[asset]
				if audio.get_playback_position()>=float(loop[0]):audio.seek(float(loop[1]))
	for child in get_children():
		if child is AudioStreamPlayer and child.get_meta("retire",false) and _gain(child)<=0.0001:
			child.queue_free()
	var animations: Dictionary=reader.story.get("native_animations",{})
	for id in sprites:
		var sprite: Sprite2D=sprites[id]
		var asset:=str(sprite.get_meta("asset",""))
		if sprite.visible and animations.has(asset):
			var animation: Dictionary=animations[asset]
			var elapsed:=clock-float(sprite.get_meta("animation_start",clock))
			var frame: int=(int(elapsed/float(animation.frame_seconds))+int(sprite.get_meta("animation_offset",0))) % animation.frames.size()
			sprite.texture=_animation_texture(asset,frame)
			sprite.set_meta("animation_frame",frame)
	if str(state.background) in ["EZ01A","EZ01B"]:
		background.region_enabled=true
		background.texture_repeat=CanvasItem.TEXTURE_REPEAT_ENABLED
		background.region_rect=Rect2(Vector2(-fmod(clock*10.0,800.0),0),Vector2(800,600))


func _wait(duration: float, cancellable:=true) -> void:
	if fast_test:return
	var end:=clock+maxf(duration,0)
	while clock<end:
		await get_tree().process_frame
		if cancellable and skip_requested:
			for job in jobs:
				if is_instance_valid(job.target):_set_property(job.target,job.property,job.finish)
			jobs.clear()
			break


func _wait_jobs(target: Object) -> void:
	while jobs.any(func(job):return job.target==target):
		await _wait(0.01)


func _wait_audio(audio: AudioStreamPlayer) -> void:
	if fast_test:return
	while audio.playing and not skip_requested:
		await get_tree().process_frame


func _music(asset: String, immediate: bool) -> void:
	if state.music==asset and music_players[music_index].playing:return
	_stop_music(immediate)
	music_index=1-music_index
	var audio:=music_players[music_index]
	reader._play(audio,asset,false)
	audio.set_meta("asset",asset)
	state.music=asset
	pending.music=asset
	state.music_paused=false
	pending.music_paused=false
	_set_gain(audio,1.0 if immediate else 0.0)
	if not immediate:_animate(audio,"native_gain",0.0,1.0,2.0)


func _stop_music(immediate: bool) -> void:
	var audio:=music_players[music_index]
	if immediate:audio.stop()
	else:_animate(audio,"native_gain",_gain(audio),0.0,3.0)
	state.music=""
	pending.music=""


func _environment(asset: String, fade: bool) -> void:
	if environment.has(asset):environment[asset].queue_free()
	var audio:=AudioStreamPlayer.new()
	add_child(audio)
	environment[asset]=audio
	reader._play(audio,asset,true)
	_set_gain(audio,0.0 if fade else 1.0)
	if fade:_animate(audio,"native_gain",0.0,1.0,2.0)
	state.ambient=environment.keys()
	pending.ambient=state.ambient.duplicate()


func _stop_environment(asset: String, fade: bool) -> void:
	for key in environment.keys():
		if asset.is_empty() or asset==key:
			var audio: AudioStreamPlayer=environment[key]
			if fade:
				_animate(audio,"native_gain",_gain(audio),0.0,3.0)
				audio.set_meta("retire",true)
			else:audio.queue_free()
			environment.erase(key)
	state.ambient=environment.keys()
	pending.ambient=state.ambient.duplicate()


func suspend(paused: bool) -> void:
	for audio in music_players+environment.values():
		audio.stream_paused=paused


# Keep the source fade envelope separate from user volume preferences.
# volume_db works on older Godot 4 releases as well as current versions.
func _gain(audio: AudioStreamPlayer) -> float:
	return float(audio.get_meta("native_gain",1.0))


func _set_gain(audio: AudioStreamPlayer, gain: float) -> void:
	audio.set_meta("native_gain",clampf(gain,0.0,1.0))
	var preference: float=reader.music_volume if audio in music_players else reader.effect_volume
	audio.volume_db=linear_to_db(maxf(0.0001,_gain(audio)*clampf(preference,0.0,1.0)))


func apply_volumes() -> void:
	for audio in get_children():
		if audio is AudioStreamPlayer:_set_gain(audio,_gain(audio))
	for video in viewport.get_children():
		if video is VideoStreamPlayer:video.volume=reader.music_volume


func _eye_enter(type: String, keep_sound: bool) -> void:
	reader.dialogue.hide()
	reader.voice_player.stop()
	if not keep_sound:
		_stop_music(false)
		_stop_environment("",false)
	eyecatch={"type":type.to_upper(),"nodes":[]}
	if type in ["","NORMAL"]:
		for key in ["EYECATCHT","EYECATCHB"]:
			var sprite:=Sprite2D.new()
			sprite.texture=texture(key)
			var material:=ShaderMaterial.new()
			var shader:=Shader.new()
			shader.code=BLACK_MASK_SHADER
			material.shader=shader
			sprite.material=material
			sprite.centered=false
			sprite.position=Vector2(0,0 if key=="EYECATCHT" else 500)
			sprite.z_index=800
			sprite.visibility_layer=4
			viewport.add_child(sprite)
			sprite.modulate.a=0
			_animate(sprite,"modulate:a",0.0,1.0,1.5)
			eyecatch.nodes.append(sprite)
		pending.characters=[]
		changed=true
		await _commit(false,false)
		await _wait(1.5)
	else:
		var black:=ColorRect.new()
		black.size=Vector2(800,600)
		black.visibility_layer=4
		black.set_meta("effect_cover_full",true)
		black.color=Color.BLACK
		black.z_index=800
		black.modulate.a=0
		viewport.add_child(black)
		eyecatch.nodes.append(black)
		_animate(black,"modulate:a",0.0,1.0,1.5)
		await _wait(2.0)
	var logo:=Sprite2D.new()
	logo.texture=texture("TITLE")
	logo.centered=false
	logo.position=Vector2(430,510)
	logo.z_index=801
	logo.visibility_layer=4
	logo.modulate.a=0
	viewport.add_child(logo)
	eyecatch.nodes.append(logo)
	_animate(logo,"modulate:a",0.0,1.0,1.0 if type in ["","NORMAL"] else 1.5)
	await _wait(2.5)


func _eye_leave() -> void:
	var duration:=1.0 if eyecatch.type in ["","NORMAL"] else 3.0
	for node in eyecatch.nodes:
		var node_duration:=1.5 if duration==3.0 and node is ColorRect else duration
		_animate(node,"modulate:a",1.0,0.0,node_duration)
	await _wait(duration+0.5)
	for node in eyecatch.nodes:node.queue_free()
	eyecatch.clear()


func _staff_roll(type: int) -> void:
	# Implemented separately from the source-derived task timeline.
	if not reader.story.get("native_endings",{}).has(str(type)):
		error="Missing source ending timeline: "+str(type)
		return
	await _play_ending(reader.story.native_endings[str(type)])


func _play_ending(timeline: Array) -> void:
	reader.dialogue.hide()
	_stop_music(true)
	_music("BGM02",true)
	var screenshot: ImageTexture
	if not fast_test:
		await RenderingServer.frame_post_draw
		screenshot=ImageTexture.create_from_image(viewport.get_texture().get_image())
	var panels: Array=[]
	for task in timeline:
		if int(task[0])==0:continue
		var type:=int(task[0])
		var image: Texture2D=screenshot if str(task[3])=="@snapshot" else texture(str(task[3]).to_upper())
		if image==null:continue
		var start:=Vector2(task[4][0],task[4][1])
		var finish:=Vector2(task[5][0],task[5][1]) if task.size()>5 else start
		var dimensions:=Vector2(800,600)
		if type==1:dimensions=image.get_size()
		elif type==2:dimensions=Vector2(306,600)
		elif type==3:dimensions=Vector2(494,600)
		elif type==4:dimensions=Vector2(800,230)
		elif type==5:dimensions=Vector2(800,370)
		if type==1:
			if start.x==-1:start.x=400
			if start.y==-1:start.y=300
			start-=dimensions*0.5
			finish=start
		var panel:=Control.new()
		panel.size=dimensions
		panel.clip_contents=true
		panel.z_index=1100+panels.size()
		panel.position=start
		panel.hide()
		viewport.add_child(panel)
		var image_node:=Sprite2D.new()
		image_node.texture=image
		image_node.centered=false
		panel.add_child(image_node)
		var center:=Vector2(task[7][0],task[7][1]) if task.size()>7 else Vector2.ZERO
		var source_offset:=Vector2.ZERO
		if type in [1,2,4]:image_node.position=(dimensions-image.get_size())*0.5
		elif type==3:source_offset=Vector2(-float(task[6]),0)
		elif type==5:source_offset=Vector2(0,-float(task[6]))
		if type in [3,5]:image_node.position=source_offset
		panels.append({"panel":panel,"image":image_node,"begin":float(task[1]),"life":float(task[2]),
			"start":start,"finish":finish,"type":type,"center":center,"offset":source_offset})
	var begin:=clock
	while clock-begin<280.0 and not fast_test and not skip_requested:
		var elapsed:=clock-begin
		stage.visible=elapsed<35.0
		for task in panels:
			var age:=elapsed-float(task.begin)
			var panel: Control=task.panel
			panel.visible=age>=0 and age<float(task.life)+0.5
			if not panel.visible:continue
			panel.modulate.a=minf(clampf(age/0.5,0,1),clampf((float(task.life)+0.5-age)/0.5,0,1))
			panel.position=task.start.lerp(task.finish,_source_curve(clampf(age/0.5,0,1),3.0))
			if int(task.type) in [3,5]:
				var scale:=1.0+0.5*clampf(age/50.0,0,1)
				task.image.scale=Vector2.ONE*scale
				task.image.position=task.offset+task.center*(1.0-scale)
		await get_tree().process_frame
	for task in panels:task.panel.queue_free()
	stage.show()
	_stop_music(true)


func _set_property(target: Object, property: String, value) -> void:
	if property=="native_gain" and target is AudioStreamPlayer:
		_set_gain(target,float(value))
	elif property.begins_with("shader_parameter/"):
		target.set(property,value)
	else:
		target.set_indexed(NodePath(property),value)


func _animation_texture(asset: String, frame: int) -> Texture2D:
	if not animation_textures.has(asset):animation_textures[asset]={}
	if not animation_textures[asset].has(frame):
		var frames: Array=reader.story.native_animations[asset].frames
		animation_textures[asset][frame]=texture(str(frames[frame]))
	return animation_textures[asset][frame]


func _movie(asset: String) -> void:
	reader.dialogue.hide()
	var path:=str(reader.story.get("native_movies",{}).get(asset.to_upper(),""))
	if path.is_empty():
		error="Missing converted original movie: "+asset
		return
	if fast_test:return
	var video:=VideoStreamPlayer.new()
	video.stream=load("res://content/"+path)
	video.expand=true
	video.size=Vector2(800,600)
	video.z_index=1200
	viewport.add_child(video)
	video.volume=reader.music_volume
	movie_active=true
	_refresh_compositor()
	video.play()
	while video.is_playing() and not fast_test and not skip_requested:
		video.paused=reader.application_paused or reader.modal.visible
		await get_tree().process_frame
	video.stop()
	video.queue_free()
	movie_active=false
	_refresh_compositor()
