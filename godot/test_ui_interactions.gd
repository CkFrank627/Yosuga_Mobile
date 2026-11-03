# SPDX-License-Identifier: GPL-2.0-only
extends SceneTree
var failures := 0
var clicks := 0
func _initialize() -> void:
	call_deferred("_run")
func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)
func touch(point: Vector2, pressed: bool, canceled := false, index := 0) -> void:
	var event := InputEventScreenTouch.new()
	event.index = index; event.position = point; event.pressed = pressed; event.canceled = canceled
	root.push_input(event,true)
func drag(point: Vector2, relative: Vector2, index := 0) -> void:
	var event := InputEventScreenDrag.new()
	event.index = index; event.position = point; event.relative = relative
	root.push_input(event,true)
func mouse(point: Vector2, pressed: bool, device := 0) -> void:
	var event := InputEventMouseButton.new()
	event.device = device; event.position = point; event.global_position = point
	event.button_index = MOUSE_BUTTON_LEFT; event.pressed = pressed
	root.push_input(event,true)
func find(node: Node, type: String, text := "") -> Control:
	for child in node.get_children():
		if child.is_class(type) and (text.is_empty() or child.get("text")==text):return child
		var found := find(child,type,text)
		if found != null:return found
	return null
func _run() -> void:
	create_timer(90).timeout.connect(func():push_error("UI_INTERACTION_TIMEOUT");quit(1))
	var player = load("res://main.tscn").instantiate()
	root.add_child(player)
	await process_frame
	player.on_title = false
	player._settings()
	await process_frame
	await process_frame
	check(player.display_mode_buttons.size()==2,"Both display modes have selectable preview cards")
	var crop: Button = player.display_mode_buttons[1]
	var settings_scroll: ScrollContainer = find(player.modal,"ScrollContainer")
	settings_scroll.scroll_vertical = 360
	await process_frame
	var card_point := crop.get_global_rect().get_center()
	touch(card_point,true); touch(card_point,false)
	check(player.display_mode=="crop" and player.native_visuals.display_mode=="crop" and player.native_visuals.foreground_output.stretch_mode==TextureRect.STRETCH_KEEP_ASPECT_CENTERED,"Crop selection updates real stage")
	player._store_settings()
	player.display_mode = "original"
	player._load_settings()
	check(player.display_mode=="crop","Display mode survives save/reload")
	settings_scroll.scroll_vertical = 360
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://../reports/settings-updated-2026-10-22.png")
	# Outside touches close without forwarding into the reading layer.
	var history_before: int = player.history_cursor
	player.book_mode = true
	var hidden_before: bool = player.chrome_hidden
	touch(Vector2(640,10),true)
	touch(Vector2(640,10),false)
	mouse(Vector2(640,10),true,-1)
	mouse(Vector2(640,10),false,-1)
	check(not player.modal.visible and player.history_cursor==history_before and player.chrome_hidden==hidden_before,"Touch outside closes modal without click-through")
	player._settings()
	await process_frame
	mouse(Vector2(10,10),true)
	mouse(Vector2(10,10),false)
	check(not player.modal.visible,"Desktop outside click closes modal")
	player._open_modal("Scroll fixture")
	var scroll: ScrollContainer = player._scroll_container()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	player.modal_box.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	for i in range(60):player._button(list,"Row %d" % i,func():clicks+=1)
	await process_frame
	await process_frame
	var point := scroll.get_global_rect().get_center()
	scroll.scroll_vertical = 700
	await process_frame
	for i in range(100):
		var before := scroll.scroll_vertical
		var movement := Vector2(0,-65 if i%2==0 else 65)
		touch(point,true)
		drag(point+movement,movement)
		check(scroll.scroll_vertical>before if movement.y<0 else scroll.scroll_vertical<before,"Rapid alternating drag %d changes scroll in requested direction" % i)
		touch(point+movement,false)
	check(clicks==0 and player.ui_touch.pointer==-1,"Dragging list buttons does not activate them or keep capture")
	await process_frame
	point = scroll.get_global_rect().get_center()
	touch(point,true); touch(point,false)
	check(clicks==1,"List button remains tappable after rapid scrolls")
	touch(point,true)
	drag(point-Vector2(0,80),Vector2(0,-80))
	touch(point-Vector2(0,80),false)
	check(player.ui_touch.velocity.length()>0,"Release starts momentum")
	touch(point,true)
	check(player.ui_touch.velocity==Vector2.ZERO,"Next press immediately interrupts momentum")
	touch(point,false,true)
	touch(point,true)
	touch(point+Vector2(5,0),true,false,1)
	touch(point,false); touch(point,false,false,1)
	check(player.ui_touch.pointer==-1 and player.ui_touch.blocked.is_empty(),"Multitouch cancellation fully releases state")
	touch(point,true); drag(point-Vector2(0,30),Vector2(0,-30))
	player._notification(Node.NOTIFICATION_WM_WINDOW_FOCUS_OUT)
	check(player.ui_touch.pointer==-1 and player.ui_touch.velocity==Vector2.ZERO,"Focus loss clears scroll state")
	touch(point,true); touch(point,false)
	check(clicks==2,"Tap still works after interruption")
	var wheel := InputEventMouseButton.new()
	wheel.position = point; wheel.global_position = point
	wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN; wheel.pressed = true
	var wheel_before := scroll.scroll_vertical
	root.push_input(wheel,true)
	check(scroll.scroll_vertical>wheel_before,"Desktop wheel input remains available")
	player._settings()
	await process_frame
	await process_frame
	var slider: HSlider = find(player.modal,"HSlider")
	point = slider.get_global_transform()*slider.thumb_center()
	var old_value := slider.value
	touch(point,true)
	drag(point-Vector2(80,0),Vector2(-80,0))
	touch(point-Vector2(80,0),false)
	check(slider.value!=old_value,"Horizontal slider dragging still works inside scroll view")
	var fixture := {"schema":2,"entry":"fixture","source_sha256":"ui-test","assets":{},"chapters":{"fixture":{
		"dialogue":{"first":{"speaker":"","text":"Fixture.","voice":""}},"scenes":{"first":{}},
		"program":[{"op":"frame","id":"first"},{"op":"choice","options":[{"text":"A","chapter":"fixture","pc":2}]},{"op":"end"}]}}}
	player._close_modal()
	check(player._prepare_story(fixture) and player.flow.begin(player.chapter_programs,"fixture"),"Prepare isolated save/choice fixture")
	await player._advance_flow()
	player._save_list(true)
	await process_frame
	var create: Button = find(player.modal,"Button","新建存档")
	check(create!=null and create.get_meta("action_role","")=="primary" and create.custom_minimum_size.y>=58,"New save has prominent primary styling")
	var save_count: int = player.saves.entries(player.story,true).size()
	point = create.get_global_rect().get_center()
	touch(point,true); touch(point,false)
	check(player.saves.entries(player.story,true).size()==save_count+1,"New save touch still creates exactly one save")
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://../reports/save-updated-2026-10-22.png")
	player._close_modal()
	await player._advance_flow()
	check(player.choice_visible,"Choice opens")
	touch(Vector2(10,10),true); touch(Vector2(10,10),false)
	await process_frame
	check(not player.modal.visible and not player.flow.pending.is_empty(),"Outside closes choice without selecting a route")
	await player._advance_flow()
	check(player.choice_visible and player.modal.visible,"Pending choice reopens on advance")
	player._close_modal(false)
	player._show_title()
	for i in range(60):player.front.tracks.append("BGM_test_%d" % i)
	player.front.show_music()
	await process_frame
	await process_frame
	var music_scroll: ScrollContainer = find(player.front,"ScrollContainer")
	music_scroll.scroll_vertical = 500
	point = music_scroll.get_global_rect().get_center()
	for i in range(20):
		var before := music_scroll.scroll_vertical
		var movement := Vector2(0,-40 if i%2==0 else 40)
		touch(point,true); drag(point+movement,movement); touch(point+movement,false)
		check(music_scroll.scroll_vertical!=before,"Title music list rapid drag works")
	check(player.front.track_index==-1,"Music list drag does not activate a track")
	player.front.tracks.clear() # Fixture has no actual audio to autoplay on title.
	touch(Vector2(5,5),true); touch(Vector2(5,5),false)
	check(player.front.page=="title","Outside music panel returns to title")
	print("UI_INTERACTIONS: %s (modes/persistence, previews, outside dismissal, primary buttons, 100 rapid drags, tap/slider/multitouch/focus)" % ("PASS" if failures==0 else "FAIL"))
	quit(0 if failures==0 else 1)
