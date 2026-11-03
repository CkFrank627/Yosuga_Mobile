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
func click(button: Button) -> void:
	var point := button.get_global_rect().get_center()
	for down in [true,false]:
		var event := InputEventScreenTouch.new()
		event.position = point
		event.pressed = down
		root.push_input(event,true)
func _run() -> void:
	create_timer(600).timeout.connect(func():push_error("CHAPTER_DIRECTORY_TIMEOUT");quit(1))
	var player = load("res://main.tscn").instantiate()
	root.add_child(player)
	await process_frame
	var source = JSON.parse_string(FileAccess.get_file_as_string("res://content/story.json"))
	check(player._prepare_story(source) and player._validate_story_assets(),"Full source validates")
	check(player.flow.begin(player.chapter_programs,source.entry),"Flow starts")
	player.native_visuals.fast_test = true
	player._show_title()
	player._layout_safe_area()
	await process_frame
	var title_button := find(player.front,"章节目录")
	check(title_button!=null and player.front.title_buttons.size()==7,"Title staircase includes chapter directory")
	for viewport_size in [Vector2i(1280,720),Vector2i(1560,720),Vector2i(2774,1280)]:
		root.size = viewport_size
		await process_frame
		player._layout_safe_area()
		await process_frame
		for button in player.front.title_buttons:
			check(player.get_global_rect().encloses(button.get_global_rect()),"Title button fits viewport")
		check(player.toolbar.get_global_rect().end.x<=player.size.x-30,"Toolbar fits viewport")
	root.size = Vector2i(1280,720)
	await process_frame
	player._layout_safe_area()
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://../reports/chapter-title-2026-10-22.png")
	click(title_button)
	await process_frame
	await process_frame
	check(player.modal.visible and player.on_title,"Real title touch opens directory")
	var routes: Array = player._chapter_routes()
	check(routes.size()==6,"Main and five separate character routes")
	var seen := {}
	var initial_globals: Dictionary = player.saves.global_flags()
	for route in routes:
		player._chapter_directory(route.id)
		await process_frame
		for index in range(route.entries.size()):
			var entry: Dictionary = route.entries[index]
			check(entry.title==route.title+str(index+1),"Sequential chapter titles")
			check(not seen.has(entry.chapter),"No duplicate chapter entries")
			seen[entry.chapter] = true
			check(player._validate_native_state(entry.native_state),"Valid inherited stage: "+entry.chapter)
	check(seen.size()==305,"All 305 reachable source segments included")
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://../reports/chapter-directory-2026-10-22.png")
	# Every real entry executes its opening commands after restoring its own stage.
	for route in routes:
		for entry in route.entries:
			await player._jump_to_chapter(entry)
			check(not player.failed and not player.current_location.is_empty(),"Chapter jump succeeds: "+entry.chapter)
			check(player.current_location.get("chapter")==entry.chapter,"Jump reaches requested chapter: "+entry.chapter)
			check(player.history.size()==1 and player.history_cursor==0,"Old history cleared")
			check(not player.on_title and not player.modal.visible and not player.auto_read,"Jump enters manual reading")
			var commands: Array = []
			for op in player.chapter_programs[entry.chapter]:
				if op.op=="frame":break
				if op.op=="presentation":commands.append(op.command)
			if not commands.any(func(command):return command in ["SetCg","SetCgRGB","BlackOut","WhiteOut"]):
				check(player.native_visuals.state.background==entry.native_state.background,"Inherited background restored: "+entry.chapter)
			await process_frame
		print("CHAPTER_ROUTE_JUMPS: ",route.id," ",route.entries.size())
	check(player.saves.global_flags()==initial_globals,"Directory does not grant completion flags")
	var prior: Dictionary = player.current_location.duplicate(true)
	var slot: String = player._save_current("catalog-regression")
	player._chapter_directory("sora")
	await process_frame
	await process_frame
	click(find(player.modal,"穹线1"))
	while player.presentation_busy:await process_frame
	check(player.current_location.chapter=="00_a001","Touch chapter button jumps directly")
	check(player.saves.read("autosave.json").presentation.location==prior,"Autosave preserves position before jump")
	check(player._load_slot(slot) and player.current_location==prior,"Manual save loads after jump")
	player._chapter_directory("main")
	await process_frame
	var location: Dictionary = player.current_location.duplicate(true)
	for down in [true,false]:
		var event := InputEventScreenTouch.new()
		event.position = Vector2(640,10)
		event.pressed = down
		root.push_input(event,true)
	check(not player.modal.visible and player.current_location==location,"Outside tap dismisses without jumping")
	click(find(player.toolbar,"章节目录"))
	await process_frame
	check(player.modal.visible,"Toolbar touch opens directory")
	print("CHAPTER_DIRECTORY: %s; 6 routes, 305 real jumps, UI touch, autosave, manual load, viewport layout" % ("PASS" if failures==0 else "FAIL"))
	quit(0 if failures==0 else 1)
