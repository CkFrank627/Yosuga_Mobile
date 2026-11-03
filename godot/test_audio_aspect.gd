# SPDX-License-Identifier: GPL-2.0-only
extends SceneTree
var failures := 0
func _initialize() -> void:
	call_deferred("_run")
func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)
func slider_for(node: Node, caption: String) -> HSlider:
	for child in node.get_children():
		if child is Label and child.text.begins_with(caption + "："):
			return node.get_child(child.get_index()+1) as HSlider
		var found := slider_for(child,caption)
		if found != null:return found
	return null
func span(image: Image, color: Color, horizontal: bool, fixed: int) -> int:
	var count := 0
	for i in range(image.get_width() if horizontal else image.get_height()):
		var pixel := image.get_pixel(i,fixed) if horizontal else image.get_pixel(fixed,i)
		if absf(pixel.r-color.r)<0.5 and absf(pixel.g-color.g)<0.5 and absf(pixel.b-color.b)<0.5:
			count += 1
	return count
func _run() -> void:
	create_timer(60).timeout.connect(func():push_error("AUDIO_ASPECT_TIMEOUT");quit(1))
	var player = load("res://main.tscn").instantiate()
	root.add_child(player)
	await process_frame
	var native = player.native_visuals
	player._settings()
	var music := slider_for(player.modal,"背景音乐音量")
	var voice := slider_for(player.modal,"角色语音音量")
	check(music != null and voice != null and music != voice,"Settings expose separate music and voice controls")
	if music == null or voice == null:
		quit(1)
		return
	voice.value = 0.9
	music.value = 0.2
	var channel: AudioStreamPlayer = native.music_players[0]
	check(is_equal_approx(db_to_linear(player.voice_player.volume_db),0.9),"Music slider leaves voice at its own volume")
	check(is_equal_approx(db_to_linear(channel.volume_db),0.2),"Music preference reaches native music channel")
	voice.value = 0.35
	check(is_equal_approx(db_to_linear(channel.volume_db),0.2),"Voice slider leaves music unchanged")
	player._store_settings()
	player.music_volume = 0.8
	player.voice_volume = 1.0
	player._load_settings()
	check(is_equal_approx(player.music_volume,0.2) and is_equal_approx(player.voice_volume,0.35),"Independent preferences survive disk save/reload")
	player._close_modal()
	player.on_title = false
	player.front.hide()
	native.set_process(false)
	native.fast_test = false
	native._set_gain(channel,0.0)
	native._animate(channel,"native_gain",0.0,1.0,2.0)
	native._process(0.5)
	check(is_equal_approx(db_to_linear(channel.volume_db),0.05),"Fade uses compatible decibel property at quarter envelope")
	player.music_volume = 0.6
	native.apply_volumes()
	check(is_equal_approx(db_to_linear(channel.volume_db),0.15),"Volume change preserves ongoing fade envelope")
	native._process(1.5)
	check(is_equal_approx(db_to_linear(channel.volume_db),0.6),"Fade ends at current user preference")
	native._animate(channel,"native_gain",1.0,0.0,3.0)
	native._process(3.0)
	native.apply_volumes()
	check(db_to_linear(channel.volume_db)<=0.00011,"Applying preferences does not resurrect faded-out music")
	var environment := AudioStreamPlayer.new()
	native.add_child(environment)
	native._set_gain(environment,0.5)
	player.effect_volume = 0.4
	native.apply_volumes()
	check(is_equal_approx(db_to_linear(environment.volume_db),0.2),"Environment level has independent preference and envelope")
	player.music_volume = 0.0
	native._set_gain(channel,1.0)
	check(channel.volume_db<=-80.0,"Zero music slider silences its channel")
	# Render the real output TextureRect in multiple screen sizes.
	native.show()
	native.viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	RenderingServer.set_default_clear_color(Color.BLACK)
	native.fill.color = Color.RED
	var test_actor: Sprite2D
	for spec in [[Vector2(200,300),Vector2i(100,100),Color.GREEN],[Vector2(600,300),Vector2i(100,200),Color.BLUE]]:
		var image := Image.create(spec[1].x,spec[1].y,false,Image.FORMAT_RGBA8)
		image.fill(spec[2])
		var sprite := Sprite2D.new()
		sprite.texture = ImageTexture.create_from_image(image)
		sprite.position = spec[0]
		if spec[2]==Color.GREEN:sprite.visibility_layer = 2
		else:test_actor = sprite
		native.stage.add_child(sprite)
	var screen := SubViewport.new()
	screen.disable_3d = true
	screen.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(screen)
	var canvas := Control.new()
	screen.add_child(canvas)
	native.reparent(canvas)
	for mode in ["original","crop"]:
		native.set_display_mode(mode)
		for dimensions in [Vector2i(1280,720),Vector2i(1560,720),Vector2i(2774,1280)]:
			screen.size = dimensions
			canvas.size = Vector2(dimensions)
			await process_frame
			await process_frame
			await RenderingServer.frame_post_draw
			var image := screen.get_texture().get_image()
			var scale := minf(float(dimensions.x)/800.0,float(dimensions.y)/600.0) if mode=="original" else maxf(float(dimensions.x)/800.0,float(dimensions.y)/600.0)
			var left := (float(dimensions.x)-800.0*scale)/2.0
			var middle := int(dimensions.y/2)
			var square_width := span(image,Color.GREEN,true,middle)
			var square_height := span(image,Color.GREEN,false,int(left+200.0*scale))
			var portrait_width := span(image,Color.BLUE,true,middle)
			var actor_scale := minf(float(dimensions.x)/800.0,float(dimensions.y)/600.0)
			var actor_left := (float(dimensions.x)-800.0*actor_scale)*0.5
			var portrait_height := span(image,Color.BLUE,false,int(actor_left+600.0*actor_scale))
			check(square_width>0 and abs(square_width-square_height)<=1,"Background square keeps ratio at "+str(dimensions))
			check(portrait_width>0 and abs(portrait_width-roundi(100.0*actor_scale))<=2 and abs(portrait_height-roundi(200.0*actor_scale))<=2,"Portrait retains ORIGINAL size in both modes at "+str(dimensions))
			check(image.get_pixel(0,middle)==(Color.BLACK if mode=="original" else Color.RED),"Original has borders; crop fills screen")
			if dimensions==Vector2i(1560,720):image.save_png("res://../reports/background-only-"+mode+"-2026-10-22.png")
	# Background snapshots must fade across the full width, while foreground
	# sprites keep their fitted size. Global flashes still cover the screen.
	screen.size = Vector2i(1560,720)
	canvas.size = Vector2(1560,720)
	test_actor.self_modulate.a = 0.5
	var colors: Array[Color] = []
	for mode in ["original","crop"]:
		native.set_display_mode(mode)
		await process_frame
		await RenderingServer.frame_post_draw
		colors.append(screen.get_texture().get_image().get_pixel(1020,360))
	check(absf(colors[0].r-colors[1].r)<0.01 and absf(colors[0].b-colors[1].b)<0.01 and colors[1].r>0.4,"Transparent portrait colors do not darken in cropped mode")
	native.set_display_mode("crop")
	native.fast_test = true
	await native.execute("SetCgRGB",[255,0,0])
	await native.execute("Commit",[])
	native.fast_test = false
	await process_frame
	await RenderingServer.frame_post_draw
	await native.execute("SetCgRGB",[0,0,255])
	await native.execute("Transition",["",300])
	var finished: Array = [false]
	_commit_later(native,finished)
	while not native.overlay.visible:await process_frame
	native._process(0.15)
	await RenderingServer.frame_post_draw
	var blended := screen.get_texture().get_image().get_pixel(30,100)
	check(blended.r>0.4 and blended.b>0.4,"Cropped background transition spans the side regions")
	var actor_blend := screen.get_texture().get_image().get_pixel(1020,360)
	check(absf(actor_blend.r-0.25)<0.04 and absf(actor_blend.b-0.75)<0.04,"Transition preserves semi-transparent portrait alpha")
	native._process(0.16)
	while not finished[0]:await process_frame
	check(not native.background_overlay.visible and not native.foreground_overlay.visible,"Layer transition snapshots are released")
	finished[0] = false
	_flush_later(native,finished)
	while not native.flash.visible:await process_frame
	await RenderingServer.frame_post_draw
	check(screen.get_texture().get_image().get_pixel(0,0).is_equal_approx(Color.WHITE),"Global flash covers the whole screen in background-only crop")
	native._process(0.15)
	await RenderingServer.frame_post_draw
	var half_flash := screen.get_texture().get_image().get_pixel(0,0)
	check(absf(half_flash.r-0.5)<0.04,"Half-opacity flash blends once across the whole screen")
	native._process(0.16)
	while not finished[0]:await process_frame
	print("AUDIO_ASPECT: %s (independent controls, persistence, fade envelopes, both modes at three rendered screen sizes)" % ("PASS" if failures==0 else "FAIL"))
	quit(0 if failures==0 else 1)

func _commit_later(native, finished: Array) -> void:
	await native.execute("Commit",[])
	finished[0] = true
func _flush_later(native, finished: Array) -> void:
	await native.execute("Flush",["WHITE",300])
	finished[0] = true
