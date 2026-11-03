# SPDX-License-Identifier: GPL-2.0-only
extends SceneTree

const PlayerScene = preload("res://main.tscn")
const SaveStore = preload("res://save_store.gd")
var failures := 0


func check(value: bool, message: String) -> void:
	if not value:
		push_error(message)
		failures += 1


func _initialize() -> void:
	call_deferred("_run")


func check_menu_layout(player, name: String) -> void:
	for frame in range(8):
		await process_frame
	var panel: Control = player.front.panel
	check(panel.get_global_rect().end.y <= player.size.y + 1, name + " panel fits screen height")
	check(panel.get_global_rect().end.x <= player.size.x + 1, name + " panel fits screen width")
	for child in player.front.box.get_children():
		if child is Control:
			check(child.get_global_rect().end.y <= player.size.y + 1, name + " controls remain reachable")


func _run() -> void:
	create_timer(30).timeout.connect(func(): push_error("V11_TIMEOUT"); quit(1))
	var player = PlayerScene.instantiate()
	root.add_child(player)
	await process_frame
	player.saves = SaveStore.new("user://v11-test-%d" % Time.get_ticks_usec())
	player.settings_path = player.saves.directory + "-settings.json"
	var fixture = JSON.parse_string(FileAccess.get_file_as_string("res://tests/manual_routes.json"))
	check(player._prepare_story(fixture) and player._validate_story_assets(), "Prepare artificial two-chapter fixture")
	player.frames = player._chapter_frames(player.story.entry)
	check(player.flow.begin(player.chapter_programs, player.story.entry), "Initialize flow")
	player._show_title()
	await check_menu_layout(player, "Title")
	check(player.on_title and player.front.visible and not player.dialogue.visible and player.history.is_empty(), "Launch title without silently advancing story")
	check(player.front.music.stream != null and player.front.music.playing, "Title BGM starts automatically")
	check(not player._has_continue(), "Continue disabled without saved progress")
	player._settings()
	check(player.on_title and player.modal.visible and player.preferences_preview != null, "Settings are reachable from title")
	player._close_modal()
	player._new_from_title()
	check(not player.on_title and not player.front.visible and player.front.music.stream == null, "New game leaves title and stops menu BGM")
	check(player.current_location.id == "manual_start:intro" and player.body.visible_characters == 0, "New dialogue starts hidden")
	player.text_speed = 10
	player._process(0.1)
	check(player.body.visible_characters > 0 and player.body.visible_characters < player.body.get_total_character_count(), "Timed progressive text reveal")
	var initial: Dictionary = player.flow.snapshot()
	player.book_mode = true
	var right: Vector2 = player.size * Vector2(0.9, 0.5)
	player._reading_gesture(right, right)
	check(player.flow.snapshot() == initial and player.body.visible_characters == -1, "First phone tap reveals entire current dialogue without skipping")
	player._reading_gesture(right, right)
	check(player.modal.visible and player.flow.pending.size() == 2, "Following tap advances to choice")
	player._choose_option(0)
	check(player.body.visible_characters == 0, "Next chapter frame also animates")
	player._previous()
	check(player.body.visible_characters == -1 and player.current_location.chapter == "manual_start", "Phone previous remains instant")
	player._reading_gesture(right, right)
	check(player.current_location.id == "manual_routes:route_a" and player.body.visible_characters == 0, "Forward through history uses progressive reveal")
	player._process(0.1)
	var visible_before: int = player.body.visible_characters
	player._settings()
	player._process(10)
	check(player.body.visible_characters == visible_before, "Modal pauses reveal rather than letting it jump ahead")
	player._close_modal()
	player._full_text()
	check(player.modal.visible and player.body.visible_characters == -1, "Full text view completes and exposes the paragraph")
	player._close_modal()
	player._show_title()
	check(player._has_continue() and player.saves.read("autosave.json").get("schema") == 3, "Return to title saves runtime state")
	player.font_size = 42
	player.text_speed = 61
	player.auto_delay = 1.5
	player.dialogue_color = Color("#e8dcc4")
	player.dialogue_opacity = 0.7
	player.music_volume = 0.25
	player.voice_volume = 0.5
	player.effect_volume = 0.3
	player._apply_preferences()
	player._store_settings()
	player.font_size = 30
	player.text_speed = 32
	player.music_volume = 0.8
	player._load_settings()
	check(player.font_size == 42 and player.text_speed == 61 and player.auto_delay == 1.5 and player.music_volume == 0.25,
		"Font, text/auto speed and volume persist")
	check(player.body.get_theme_font_size("normal_font_size") == 42 and player.body.get_theme_color("default_color").get_luminance() < 0.2,
		"Font preference applies and light dialogue background receives dark text")
	var bad_settings := FileAccess.open(player.settings_path, FileAccess.WRITE)
	bad_settings.store_string('{"font_size":"invalid","text_speed":0,"auto_delay":999}')
	bad_settings.close()
	player._load_settings()
	check(player.font_size == 42 and player.text_speed == 5 and player.auto_delay == 10, "Malformed preferences use defaults and clamp numeric limits")
	player.front.show_music()
	await check_menu_layout(player, "Music")
	check(player.front.tracks.size() >= 2 and player.front.page == "music", "Music room exposes background tracks")
	player.front.play_track(0)
	player.front._toggle_play()
	check(player.front.music.stream_paused, "Music pause")
	player.front._toggle_play()
	check(not player.front.music.stream_paused, "Music resume")
	player.front._next_track()
	check(player.front.track_index == 1, "Next track")
	player.front._next_track(-1)
	check(player.front.track_index == 0, "Previous track")
	player.front._seek_to(1.0)
	await create_timer(0.05).timeout
	check(player.front.music.get_playback_position() >= 0.8, "Music seek updates playback")
	player.front.repeat_mode = 2
	player.front._track_finished()
	check(player.front.track_index == 0, "Single-track repeat")
	player.front.repeat_mode = 1
	player.front.shuffle = true
	player.front._track_finished()
	check(player.front.track_index != 0, "Shuffle selects a different track")
	player._notification(Node.NOTIFICATION_APPLICATION_PAUSED)
	check(player.front.music.stream_paused, "Menu BGM participates in background pause")
	player._notification(Node.NOTIFICATION_APPLICATION_RESUMED)
	check(not player.front.music.stream_paused, "Menu BGM resumes without changing track")
	player.front.show_gallery()
	var expected: Array = []
	var opening = JSON.parse_string(FileAccess.get_file_as_string("res://content/sample.json"))
	for frame in opening.frames:
		if not frame.background.is_empty() and not expected.has(frame.background):
			expected.append(frame.background)
	check(player.front.pictures == expected, "Gallery contains only verified opening background references")
	player.front.show_picture(0)
	check(player.front.page == "picture" and player.front.picture_index == 0, "Open background viewer")
	player.front.show_picture(1)
	check(player.front.picture_index == 1, "Next picture")
	player.front.picture_zoom = true
	player.front.show_picture(1)
	await check_menu_layout(player, "Picture viewer")
	player.front.show_gallery()
	await check_menu_layout(player, "Gallery")
	player.front.show_title()
	player.history.clear()
	player.history_cursor = -1
	player.current_location = {}
	check(player._has_continue(), "Continue discovers background autosave across sessions")
	player._continue_from_title()
	check(not player.on_title and player.current_location.id == "manual_routes:route_a", "Continue loads saved route rather than restarting")
	player._show_title()
	check(player._load_slot("autosave.json") and not player.on_title and not player.front.visible,
		"Load from title exits menu and restores dialogue")
	player._show_title()
	player._start_new()
	player.auto_read = true
	player.text_speed = 100
	player.auto_delay = 0.5
	player._process(0.1)
	check(player.flow.pending.is_empty(), "Auto cannot skip incomplete dialogue")
	player._process(0.4)
	check(player.flow.pending.is_empty(), "Auto waits after complete reveal")
	player._process(0.2)
	check(player.flow.pending.size() == 2, "Auto advances only after reveal and configured delay")
	player._show_title()
	var invalid_save: Dictionary = player.saves.read("autosave.json")
	invalid_save.flow.pc = -100
	check(player.saves.write("invalid-flow.json", invalid_save), "Prepare invalid flow save")
	check(not player._load_slot("invalid-flow.json") and player.on_title and not player.modal.visible,
		"Failed title load keeps title visible instead of showing an old story choice")
	await player._stop_audio()
	for id in DirAccess.get_files_at(player.saves.directory):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(player.saves.directory.path_join(id)))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(player.saves.directory))
	if FileAccess.file_exists(player.settings_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(player.settings_path))
	print("V11: %s" % ("PASS" if failures == 0 else "FAIL"))
	quit(0 if failures == 0 else 1)
