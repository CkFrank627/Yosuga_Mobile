# SPDX-License-Identifier: GPL-2.0-only
extends SceneTree
var failures := 0
func _initialize() -> void:call_deferred("_run")
func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)
func find(node: Node, text: String) -> Button:
	for child in node.get_children():
		if child is Button and child.text==text:return child
		var found := find(child,text)
		if found!=null:return found
	return null
func near(a: Color, b: Color) -> bool:
	return absf(a.r-b.r)<0.015 and absf(a.g-b.g)<0.015 and absf(a.b-b.b)<0.015
func shaded(color: Color, mode: String) -> Color:
	return Color(color.r*color.r,color.g*color.g,color.b*color.b,color.a*color.a) if mode=="dark" else color
func click(button: Button) -> void:
	for down in [true,false]:
		var event := InputEventScreenTouch.new()
		event.position = button.get_global_rect().get_center()
		event.pressed = down
		root.push_input(event,true)
func _run() -> void:
	create_timer(90).timeout.connect(func():push_error("COLOR_MODES_TIMEOUT");quit(1))
	var player = load("res://main.tscn").instantiate()
	root.add_child(player)
	await process_frame
	check(player.scene_color_mode=="light","Default light mode")
	var file := FileAccess.open(player.settings_path,FileAccess.WRITE)
	file.store_string('{"schema":2,"scene_saturation":0.2}')
	file.close()
	player.scene_color_mode = "dark"
	player._load_settings()
	check(player.scene_color_mode=="light","Old saturation preference discarded")
	player._settings()
	await process_frame
	check(player.color_mode_buttons.size()==2,"Two selectable shader previews")
	check(not FileAccess.get_file_as_string("res://player.gd").contains("画面饱和度"),"Saturation control removed")
	var dark: Button = player.color_mode_buttons[1]
	var scroll: ScrollContainer = dark.get_parent().get_parent().get_parent()
	scroll.scroll_vertical = int(dark.get_parent().position.y)-12
	await process_frame
	await process_frame
	click(dark)
	check(player.scene_color_mode=="dark" and dark.button_pressed,"Touch selects dark mode")
	player._store_settings()
	var preferences = JSON.parse_string(FileAccess.get_file_as_string(player.settings_path))
	check(preferences.get("scene_color_mode")=="dark" and not preferences.has("scene_saturation"),"Only mode is persisted")
	player.scene_color_mode = "light"
	player._load_settings()
	check(player.scene_color_mode=="dark","Mode survives settings reload")
	for card in player.display_mode_buttons:
		check(card.get_meta("preview").color_mode=="dark","Aspect preview follows selected shader")
	check(player.body.modulate==Color.WHITE and not player.dialogue.material,"Text and dialogue use no image shader")
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://../reports/color-modes-settings-2026-10-22.png")
	find(player.modal,"恢复阅读默认值").pressed.emit()
	check(player.scene_color_mode=="light","Restore defaults selects light")
	player._close_modal(false)
	player.front.hide()
	player.on_title = false
	var native = player.native_visuals
	native.show()
	native.viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	native.set_process(false)
	var background := Color(0.2,0.5,0.8)
	var actor := Color(0.8,0.2,0.1)
	var bg_image := Image.create(800,600,false,Image.FORMAT_RGBA8)
	bg_image.fill(background)
	native.background.texture = ImageTexture.create_from_image(bg_image)
	native.fill.color = Color.BLACK
	var actor_image := Image.create(100,200,false,Image.FORMAT_RGBA8)
	var sprite := Sprite2D.new()
	sprite.centered = false
	sprite.position = Vector2(500,100)
	sprite.material = native.tone_material
	native.stage.add_child(sprite)
	var screen := SubViewport.new()
	screen.size = Vector2i(1280,720)
	screen.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(screen)
	var canvas := Control.new()
	canvas.size = Vector2(1280,720)
	screen.add_child(canvas)
	native.reparent(canvas)
	await process_frame
	for alpha in [1.0,0.5]:
		actor_image.fill(Color(actor,alpha))
		sprite.texture = ImageTexture.create_from_image(actor_image)
		for aspect in ["original","crop"]:
			native.set_display_mode(aspect)
			for mode in ["light","dark"]:
				native.set_color_mode(mode)
				await process_frame
				await process_frame
				await RenderingServer.frame_post_draw
				var frame := screen.get_texture().get_image()
				var expected_bg := shaded(background,mode)
				var expected_actor := shaded(Color(actor,alpha),mode)
				check(near(frame.get_pixel(250,100),expected_bg),"Background matches shader: "+aspect+mode)
				check(near(frame.get_pixel(820,240),expected_bg.lerp(expected_actor,expected_actor.a)),"Portrait RGB and alpha match exact shader: "+aspect+mode+str(alpha))
				if alpha==1.0 and aspect=="crop":frame.save_png("res://../reports/color-mode-"+mode+"-2026-10-22.png")
		var textures: Dictionary = native.create_color_previews()
		check(native.color_preview_views.size()==4,"Exactly four temporary preview layers")
		for selected in ["light","dark"]:
			native.set_color_mode(selected)
			await process_frame
			await process_frame
			await RenderingServer.frame_post_draw
			for mode in ["light","dark"]:
				var bg: Image = textures[mode].background.get_image()
				var fg: Image = textures[mode].foreground.get_image()
				var expected := shaded(Color(actor,alpha),mode)
				check(near(bg.get_pixel(100,100),shaded(background,mode)),"Independent preview background: "+mode+selected)
				check(near(fg.get_pixel(550,200),Color(expected.r*expected.a,expected.g*expected.a,expected.b*expected.a)),"Independent premultiplied preview portrait: "+mode+selected)
		native.clear_color_previews()
		check(native.color_preview_views.is_empty(),"Preview renderer resources released")
	player._settings()
	await process_frame
	await process_frame
	check(native.color_preview_views.size()==4,"Reading settings create current scene previews")
	var preview_card: Button = player.color_mode_buttons[0]
	var preview_scroll: ScrollContainer = preview_card.get_parent().get_parent().get_parent()
	preview_scroll.scroll_vertical = int(preview_card.get_parent().position.y)-12
	await process_frame
	for aspect in ["original","crop"]:
		player.display_mode = aspect
		player._apply_preferences()
		await process_frame
		await process_frame
		await RenderingServer.frame_post_draw
		var frame := root.get_texture().get_image()
		for card in player.color_mode_buttons:
			var preview: Control = card.get_meta("preview")
			var point := preview.global_position+preview.size*0.5
			check(near(frame.get_pixelv(Vector2i(point)),shaded(background,str(card.get_meta("color_mode")))),"Settings actual preview matches its shader in "+aspect)
		if aspect=="crop":frame.save_png("res://../reports/color-modes-scene-preview-2026-10-22.png")
	player._close_modal(false)
	check(native.color_preview_views.is_empty(),"Closing settings releases current scene previews")
	var snapshot: Dictionary = native.snapshot()
	native.set_color_mode("dark")
	native.reset()
	native.restore(snapshot)
	check(native.tone_material.get_shader_parameter("dark_mode")==true,"Stage reset/restore retains user mode")
	print("COLOR_MODES: %s; exact light/dark RGB+alpha, both aspect modes, independent actual scene previews, settings/touch/defaults/lifecycle" % ("PASS" if failures==0 else "FAIL"))
	quit(0 if failures==0 else 1)
