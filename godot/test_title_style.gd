# SPDX-License-Identifier: GPL-2.0-only
extends SceneTree
## Isolated UI regression using artificial dialogue and no original game assets.

var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)


func settle() -> void:
	for index in range(6):
		await process_frame


func _run() -> void:
	create_timer(30).timeout.connect(func(): push_error("TITLE_STYLE_TIMEOUT"); quit(1))
	var player = load("res://main.tscn").instantiate()
	root.add_child(player)
	await process_frame
	var fixture := {"schema": 2, "entry": "preview", "source_sha256": "title-style-artificial-fixture",
		"assets": {"BGMpreview": "preview-tone.wav"}, "chapters": {"preview": {
			"dialogue": {"intro": {"speaker": "", "text": "Preview sentence."}},
			"scenes": {"intro": {}}, "program": [{"op": "frame", "id": "intro"}, {"op": "end"}]}}}
	check(player._prepare_story(fixture) and player._validate_story_assets(), "Prepare artificial preview")
	player.frames = player._chapter_frames("preview")
	check(player.flow.begin(player.chapter_programs, "preview"), "Begin preview")
	player._show_title()
	await settle()
	check(player.front.backdrop.texture != null and not player.front.shade.visible and not player.front.panel.visible,
		"Title uses bright sky without an opaque panel")
	check(player.front.title_buttons.size() == 6 and player.front.title_buttons[1].disabled,
		"Six actions; unavailable Continue is disabled")
	check(player.front.music.playing, "Existing automatic title BGM remains active")
	var original_size: Vector2 = player.size
	for viewport in [Vector2(1280, 720), Vector2(1560, 720), Vector2(1920, 1080), Vector2(1280, 640)]:
		player.size = viewport
		player.front.size = viewport
		player.front.layout(Vector2(48, 30))
		var previous := Vector2(INF, -INF)
		for button in player.front.title_buttons:
			var bounds: Rect2 = button.get_rect()
			check(bounds.position.x < previous.x and bounds.position.y > previous.y, "Menu descends in a staircase")
			check(bounds.position.x >= 48 and bounds.end.x <= viewport.x - 48 and bounds.end.y <= viewport.y - 30,
				"All menu hit areas fit inside safe margins")
			check(bounds.size.y >= 48, "Menu retains a usable touch height")
			previous = bounds.position
	player.size = original_size
	player.front.size = original_size
	player._layout_safe_area()
	await settle()
	if "--capture" in OS.get_cmdline_user_args():
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../reports/title-style-preview.png"))
	player.front.title_buttons[3].pressed.emit()
	check(player.front.page == "music" and player.front.panel.visible and player.front.shade.visible,
		"Music room action keeps its readable panel")
	player.front.show_title()
	player.front.title_buttons[4].pressed.emit()
	check(player.front.page == "gallery", "Gallery action")
	player.front.show_title()
	player.front.title_buttons[5].pressed.emit()
	check(player.modal.visible and player.on_title, "Settings action")
	player._close_modal()
	player.front.title_buttons[2].pressed.emit()
	check(player.modal.visible and player.on_title, "Load list action")
	player._close_modal()
	player.front.title_buttons[0].pressed.emit()
	check(not player.on_title and player.current_location.id == "intro", "Start action enters reader")
	player._show_title()
	check(not player.front.title_buttons[1].disabled, "Continue becomes enabled after progress")
	player.front.title_buttons[1].pressed.emit()
	check(not player.on_title and player.body.visible_characters == -1, "Continue restores reader")
	await player._stop_audio()
	if DirAccess.dir_exists_absolute(player.saves.directory):
		for id in DirAccess.get_files_at(player.saves.directory):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(player.saves.directory.path_join(id)))
		DirAccess.remove_absolute(ProjectSettings.globalize_path(player.saves.directory))
	if FileAccess.file_exists(player.settings_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(player.settings_path))
	print("TITLE_STYLE: %s" % ("PASS" if failures == 0 else "FAIL"))
	quit(0 if failures == 0 else 1)
