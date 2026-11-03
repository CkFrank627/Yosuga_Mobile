# SPDX-License-Identifier: GPL-2.0-only
extends SceneTree
var failures := 0
func _initialize() -> void:call_deferred("_run")
func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)
func find(node: Node, type: String, caption := "") -> Control:
	for child in node.get_children():
		if child.is_class(type) and (caption.is_empty() or child.get("text")==caption):return child
		var found := find(child,type,caption)
		if found != null:return found
	return null
func mouse(point: Vector2, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.position = point; event.global_position = point
	event.button_index = MOUSE_BUTTON_LEFT; event.pressed = pressed
	root.push_input(event,true)
func motion(point: Vector2, relative: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = point; event.global_position = point; event.relative = relative
	event.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(event,true)
func touch(point: Vector2, pressed: bool) -> void:
	var event := InputEventScreenTouch.new()
	event.position = point; event.pressed = pressed
	root.push_input(event,true)
func drag(point: Vector2, relative: Vector2) -> void:
	var event := InputEventScreenDrag.new()
	event.position = point; event.relative = relative
	root.push_input(event,true)
func _run() -> void:
	create_timer(90).timeout.connect(func():push_error("DIALOGUE_CONTROLS_TIMEOUT");quit(1))
	var player = load("res://main.tscn").instantiate()
	root.add_child(player)
	await process_frame
	player.on_title = false
	player._settings()
	await process_frame
	await process_frame
	var slider: HSlider = find(player.modal,"HSlider")
	var original := slider.value
	var track := slider.get_global_rect().position+Vector2(50,slider.size.y*0.5)
	mouse(track,true); motion(track+Vector2(100,0),Vector2(100,0)); mouse(track+Vector2(100,0),false)
	check(is_equal_approx(slider.value,original),"Desktop track click/drag cannot change setting")
	touch(track,true); drag(track+Vector2(100,0),Vector2(100,0)); touch(track+Vector2(100,0),false)
	check(is_equal_approx(slider.value,original),"Touch track click/drag cannot change setting")
	var thumb: Vector2 = slider.get_global_transform()*slider.thumb_center()
	mouse(thumb,true); motion(thumb-Vector2(120,0),Vector2(-120,0)); mouse(thumb-Vector2(120,0),false)
	check(slider.value<original,"Desktop thumb drag changes setting")
	var before := slider.value
	thumb = slider.get_global_transform()*slider.thumb_center()
	touch(thumb,true); drag(thumb-Vector2(100,0),Vector2(-100,0)); touch(thumb-Vector2(100,0),false)
	check(slider.value<before,"Touch thumb drag changes setting")
	var scroller: ScrollContainer = find(player.modal,"ScrollContainer")
	var scroll_before := scroller.scroll_vertical
	touch(track,true); drag(track-Vector2(0,65),Vector2(0,-65)); touch(track-Vector2(0,65),false)
	check(scroller.scroll_vertical>scroll_before,"Vertical drag starting on track scrolls settings")
	player._close_modal()
	# Use the original imported window skins, not a substitute.
	player.story = {"assets":{"FRM_0102B":"FRM_0102b.png","FRM_0106B":"FRM_0106b.png"},"native_presentation":true}
	player.native_visuals.hide()
	player.bg.hide()
	player.bg_fill.color = Color.WHITE
	player.toolbar.hide(); player.progress.hide(); player.hint.hide(); player.speaker.hide()
	player.body.text = "Text remains visible."
	player.body.visible_characters = -1
	player.dialogue.show()
	for mode in ["classic","custom"]:
		player.dialogue_mode = mode
		player.dialogue_color = Color(0.05,0.12,0.3)
		var samples: Array[Color] = []
		for opacity in [0.0,0.5,1.0]:
			player.dialogue_opacity = opacity
			player._apply_preferences()
			await process_frame
			await RenderingServer.frame_post_draw
			var image := root.get_texture().get_image()
			var point: Vector2 = player.dialogue.get_global_rect().get_center()
			samples.append(image.get_pixel(int(point.x),int(point.y)))
			check(is_equal_approx(player.body.modulate.a,1.0),"Opacity does not fade dialogue text")
			if opacity==0.5:image.save_png("res://../reports/dialogue-"+mode+"-2026-10-19.png")
		check(samples[0].is_equal_approx(Color.WHITE),"Zero opacity makes "+mode+" background completely transparent")
		check(samples[0].get_luminance()>samples[1].get_luminance()+0.03 and samples[1].get_luminance()>samples[2].get_luminance()+0.03,"Actual "+mode+" pixels respond monotonically to opacity")
		var style = player.dialogue.get_theme_stylebox("panel")
		check(style is StyleBoxTexture if mode=="classic" else style is StyleBoxFlat,"Selected dialogue mode installs correct active style")
	player.dialogue_mode = "custom"
	player.dialogue_color = Color("#bc6a3f")
	player.dialogue_opacity = 0.35
	player._apply_preferences()
	player._apply_native_window()
	check(player.dialogue.get_theme_stylebox("panel") is StyleBoxFlat,"Source window changes cannot override custom mode")
	player._store_settings()
	player.dialogue_mode = "classic"; player.dialogue_color = Color.BLACK; player.dialogue_opacity = 1.0
	player._load_settings()
	check(player.dialogue_mode=="custom" and player.dialogue_color.to_html(false)=="bc6a3f" and is_equal_approx(player.dialogue_opacity,0.35),"Mode/color/opacity persist independently")
	player._settings()
	await process_frame
	var picker: ColorPickerButton = find(player.modal,"ColorPickerButton")
	check(not picker.disabled,"Custom mode enables color picker")
	var classic: Button = find(player.modal,"Button","经典模式")
	classic.button_pressed = true
	check(picker.disabled and player.dialogue_mode=="classic","Classic mode selects original skin and disables custom picker")
	var custom: Button = find(player.modal,"Button","自设模式")
	custom.button_pressed = true
	check(not picker.disabled and player.dialogue_color.to_html(false)=="bc6a3f","Returning to custom mode preserves chosen color")
	var settings_scroll: ScrollContainer = find(player.modal,"ScrollContainer")
	settings_scroll.scroll_vertical = 1100
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://../reports/settings-dialogue-2026-10-19.png")
	print("DIALOGUE_CONTROLS: %s (thumb-only touch/mouse, vertical scroll, classic/custom actual opacity pixels, text, source window, persistence)" % ("PASS" if failures==0 else "FAIL"))
	quit(0 if failures==0 else 1)
