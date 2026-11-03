# SPDX-License-Identifier: GPL-2.0-only
extends SceneTree
## Exercise the real full-story entry with normal timing and isolated test saves.
var failures := 0
func _initialize() -> void:
	call_deferred("_run")
func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)
func _run() -> void:
	create_timer(90).timeout.connect(func():push_error("FULL_STARTUP_TIMEOUT");quit(1))
	var player = load("res://main.tscn").instantiate()
	root.add_child(player)
	await process_frame
	var source = JSON.parse_string(FileAccess.get_file_as_string("res://content/story.json"))
	check(source is Dictionary and player._prepare_story(source) and player._validate_story_assets(),"Complete project source and assets validate")
	if failures > 0:
		quit(1)
		return
	player._show_title()
	check(player.on_title and player.front.visible,"Full project title opens")
	player._start_new()
	while player.current_location.is_empty() or player.presentation_busy:
		await process_frame
	check(not player.on_title and player.story.native_presentation,"New game enters native presentation")
	for index in range(10):
		check(not player.current_location.is_empty() and not player.body.text.is_empty(),"Actual dialogue frame available")
		check(player.native_visuals.visible,"Actual source stage visible")
		player._advance_flow()
		while player.presentation_busy:
			await process_frame
		await process_frame
	await RenderingServer.frame_post_draw
	var frame: Image = player.native_visuals.viewport.get_texture().get_image()
	check(frame != null and frame.get_size() == Vector2i(800,600),"Native stage renders at source resolution")
	print("FULL_STARTUP: %s (real title, new game, 10 dialogue advances, rendered stage)" % ("PASS" if failures == 0 else "FAIL"))
	quit(0 if failures == 0 else 1)
