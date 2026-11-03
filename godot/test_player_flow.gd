# SPDX-License-Identifier: GPL-2.0-only
extends SceneTree

const PlayerScene = preload("res://main.tscn")
const Flow = preload("res://story_flow.gd")
const SaveStore = preload("res://save_store.gd")
var failures := 0


func check(condition: bool, message: String) -> void:
	if not condition:
		push_error(message)
		failures += 1


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	create_timer(20).timeout.connect(func(): push_error("PLAYER_FLOW_TIMEOUT"); quit(1))
	var player = PlayerScene.instantiate()
	root.add_child(player)
	await process_frame
	await process_frame
	player.saves = SaveStore.new("user://player-flow-test-%d" % Time.get_ticks_usec())
	var fixture = JSON.parse_string(FileAccess.get_file_as_string("res://tests/manual_routes.json"))
	fixture.chapters.manual_start.scenes["manual_start:intro"]["camera"] = {"offset": [17, -9], "zoom": 1.2}
	fixture.chapters.manual_start.scenes["manual_start:intro"]["transition"] = {"type": "fade", "duration": 0.5}
	check(fixture is Dictionary and player._prepare_story(fixture) and player._validate_story_assets(),
		"Load and validate manual two-chapter fixture")
	player.flow = Flow.new()
	check(player.flow.begin(player.chapter_programs, player.story.entry, player.saves.global_flags()), "Begin manual story")
	check(player.saves.merge_global_flags({}) and not FileAccess.file_exists(player.saves.directory.path_join("global-unlocks.json")),
		"No disk write for unchanged empty unlocks")
	player.history.clear()
	player.history_cursor = -1
	player.frames = player._chapter_frames(player.story.entry)
	player._advance_flow()
	check(player.current_location == {"chapter": "manual_start", "id": "manual_start:intro"}, "Entry dialogue frame")
	check(player.bg.texture != null and not player.actors[0].visible and player.actors[1].visible,
		"Background, named character hiding and multiple character layers")
	check(player.bg.position == Vector2(17, -9) and player.bg.scale == Vector2(1.2, 1.2), "JSON camera offset and zoom")
	check(is_equal_approx(player.actors[1].position.x, player.size.x * 0.7 - player.size.x * 0.28 + 17),
		"Character horizontal placement")
	var original_size: Vector2 = player.size
	player.size = original_size * Vector2(0.8, 0.9)
	player._layout_safe_area()
	check(player.actors[1].size.is_equal_approx(Vector2(player.size.x * 0.56, player.size.y)) and is_equal_approx(player.actors[1].position.x, player.size.x * 0.7 - player.actors[1].size.x * 0.5 + 17), "Visual placement updates after viewport resize")
	player.size = original_size
	player._layout_safe_area()
	# A converted CG center of (800, 300) means crop origin (400, 0),
	# not a positive translation of the background and every character.
	var original_texture: Texture2D = player.bg.texture
	var wide_image := Image.create(1766, 600, false, Image.FORMAT_RGB8)
	wide_image.fill(Color(0.2, 0.4, 0.6))
	player.bg.texture = ImageTexture.create_from_image(wide_image)
	var crop_frame: Dictionary = player._runtime_frame("manual_start", "manual_start:intro").duplicate(true)
	crop_frame.camera = {"offset": [400.0, 0.0], "source_coordinates": true}
	player._layout_visuals(crop_frame)
	check(player.bg.position.is_equal_approx(Vector2(-400.0 * player.size.x / 800.0, 0)),
		"Source CG center crops into a wide image instead of shifting it right by half a screen")
	check(is_equal_approx(player.actors[1].position.x, player.size.x * (0.7 - 0.28)),
		"Background source crop does not shift foreground characters")
	check(player.bg.get_rect().position.x <= 0 and player.bg.get_rect().end.x >= player.size.x,
		"Wide background crop covers both viewport edges")
	player.size = original_size * Vector2(0.8, 0.9)
	player._layout_visuals(crop_frame)
	check(is_equal_approx(player.bg.position.x, -400.0 * player.size.x / 800.0) and player.bg.get_rect().end.x >= player.size.x,
		"Source crop follows resized viewport dimensions")
	player.size = original_size
	crop_frame.camera.offset = [966.0, 0.0]
	player._layout_visuals(crop_frame)
	check(is_equal_approx(player.bg.get_rect().end.x, player.size.x), "Last wide-image crop reaches right edge without black border")
	crop_frame.camera.offset = [9999.0, -300.0]
	player._layout_visuals(crop_frame)
	check(player.bg.position.x <= 0 and player.bg.get_rect().end.x >= player.size.x and is_zero_approx(player.bg.position.y),
		"Source crop bounds avoid uncovered background edges")
	player.bg.texture = ImageTexture.create_from_image(Image.create(800, 600, false, Image.FORMAT_RGB8))
	player._layout_visuals(crop_frame)
	check(player.bg.position.is_zero_approx() and player.bg.size.is_equal_approx(player.size),
		"A normal-size background cannot be panned completely off the screen")
	player.bg.texture = original_texture
	player._layout_visuals(player._runtime_frame("manual_start", "manual_start:intro"))
	check(player.bg.size.is_equal_approx(player.size) and player.bg.position == Vector2(17, -9),
		"Returning from source crop restores generic camera geometry")
	var silent_audio := AudioStreamWAV.new()
	silent_audio.format = AudioStreamWAV.FORMAT_16_BITS
	silent_audio.mix_rate = 44100
	var silence := PackedByteArray()
	silence.resize(88200)
	silent_audio.data = silence
	player.bgm_player.stream = silent_audio
	player.bgm_player.play()
	player.ambient_player.stream = silent_audio
	player.ambient_player.play()
	await create_timer(0.03).timeout
	player.ambient_player.stream_paused = true
	player.book_mode = true
	var touch_point: Vector2 = Vector2(player.size.x * 0.9, player.size.y * 0.5)
	player._test_touch(touch_point, true)
	player.mouse_tracking = true
	var before_pause: Dictionary = player.flow.snapshot()
	player.auto_read = true
	player._notification(Node.NOTIFICATION_APPLICATION_PAUSED)
	check(player.application_paused and player.bgm_player.stream_paused and player.touch_index == -1 and player.touches.is_empty() and not player.mouse_tracking,
		"Background pause suspends audio and clears active touch/mouse gestures")
	check(player.saves.read("autosave.json").get("schema") == 3, "Background pause saves runtime state")
	player._process(100.0)
	player._advance()
	check(player.flow.snapshot() == before_pause, "Background cannot advance auto or manual reading")
	player._notification(Node.NOTIFICATION_APPLICATION_PAUSED)
	player._notification(Node.NOTIFICATION_APPLICATION_RESUMED)
	player._test_touch(touch_point, false)
	check(not player.application_paused and not player.bgm_player.stream_paused and player.ambient_player.stream_paused and player.bgm_player.stream == silent_audio,
		"Repeated pause and resume preserve audio stream and previous pause state")
	check(player.flow.snapshot() == before_pause, "Releasing a touch after resume does not flip the page")
	player._play(player.bgm_player, "")
	check(player.bgm_player.stream == null and not player.bgm_player.playing, "Clearing audio releases the previous stream")
	player._play(player.ambient_player, "")
	player.auto_read = false
	player.body.visible_characters = -1
	player._advance()
	check(player.flow.pending.size() == 2 and player.modal.visible, "Choice pauses and presents both options")
	var choice_save: String = player._save_current("At the choice")
	check(not choice_save.is_empty(), "Save at choice")
	player._notification(Node.NOTIFICATION_APPLICATION_PAUSED)
	player._notification(Node.NOTIFICATION_APPLICATION_RESUMED)
	check(player._load_slot("autosave.json") and player.flow.pending.size() == 2 and player.modal.visible,
		"Background autosave at a choice restores the actionable choice")
	player._choose_option(0)
	await create_timer(0.1).timeout
	check(is_equal_approx(player.bg.modulate.a, 1.0), "Previous fade cannot alter the next frame")
	check(player.current_location.chapter == "manual_routes" and player.current_location.id == "manual_routes:route_a", "Cross-chapter Route A")
	player._previous()
	check(player.current_location.chapter == "manual_start", "Previous returns to actual visited history")
	player._advance_flow()
	player.body.visible_characters = -1
	player._advance()
	check(player.ending and player.flow.global_flags.get("completed_a", false), "Route A completion")
	check(player.saves.global_flags().get("completed_a", false), "Persist route completion outside slot")
	check(player._load_slot(choice_save), "Load older choice save")
	check(player.flow.pending.size() == 2 and player.flow.global_flags.get("completed_a", false), "Restore pending choice without losing unlock")
	player._choose_option(1)
	check(player.current_location.id == "manual_routes:route_b", "Cross-chapter Route B")
	player._previous()
	check(player.current_location.chapter == "manual_start", "Route B history does not include discarded Route A")
	player._advance_flow()
	player.body.visible_characters = -1
	player._advance()
	check(player.flow.global_flags.get("completed_b", false), "Route B completion")
	check(player._load_slot(choice_save), "Reload old save after both completions")
	check(player.flow.global_flags.get("completed_a", false) and player.flow.global_flags.get("completed_b", false), "Old save preserves all completion unlocks")
	check(player.flow.pending.size() == 2, "Loaded choice remains actionable")
	player.choice_visible = false
	player._close_modal()
	player._choose_option(1)
	await process_frame
	check(not player.modal.visible and player.flow.pending.is_empty(), "Deferred modal callback cannot resurrect an old choice")
	check(player._load_slot(choice_save), "Restore choice after deferred callback test")
	var before: Dictionary = player.flow.snapshot()
	var bad: Dictionary = player.saves.read(choice_save)
	bad.presentation.location = {"chapter": "manual_routes", "id": "manual_routes:route_b"}
	check(player.saves.write("bad-presentation.json", bad) and not player._load_slot("bad-presentation.json"), "Reject mismatched displayed frame and history")
	bad = player.saves.read(choice_save)
	bad.flow.chapter = "manual_routes"
	bad.flow.pc = 6
	bad.flow.pending = []
	check(player.saves.write("bad-position.json", bad) and not player._load_slot("bad-position.json"), "Reject unrelated resume position")
	bad = player.saves.read(choice_save)
	bad.history[0].flow = "invalid"
	check(player.saves.write("bad-history.json", bad) and not player._load_slot("bad-history.json"), "Reject invalid history snapshot type")
	bad = player.saves.read(choice_save)
	bad.history[0].flow.pc = 0
	check(player.saves.write("bad-history-position.json", bad) and not player._load_slot("bad-history-position.json"), "History state must follow its displayed frame")
	check(player.flow.snapshot() == before and player.current_location.chapter == "manual_start", "Rejected loads preserve current story position")
	check(not player.saves.compatible({"schema": 2, "source_sha256": fixture.source_sha256, "chapter": "manual_start", "cursor": 0, "frame_id": 1}, player.story), "Legacy slot safely rejected for chapter schema 2")
	var migration_store = SaveStore.new("user://legacy-migration-test-%d" % Time.get_ticks_usec())
	var old_hash := "old-sample-hash"
	var legacy_story := {
		"schema": 2,
		"source_sha256": "full-story-hash",
		"entry": "legacy",
		"chapters": {
			"legacy": {
				"dialogue": {"legacy:d00001": {"speaker": "角色", "text": "旧版对白"}},
				"program": [{"op": "frame", "id": "legacy:d00001"}, {"op": "end"}],
			},
		},
		"legacy_migrations": [{
			"source_sha256": old_hash,
			"chapter": "legacy",
			"frame_map": {
				"1": {"id": "legacy:d00001", "cursor": 0, "speaker": "角色", "text": "旧版对白"},
			},
		}],
	}
	var old_save := {
		"schema": 2, "source_sha256": old_hash, "chapter": "legacy",
		"cursor": 0, "frame_id": 1, "speaker": "角色", "text": "旧版对白",
		"saved_unix": 1,
	}
	check(migration_store.write("old-slot.json", old_save), "Write legacy migration fixture")
	migration_store.migrate_legacy(legacy_story, "user://missing-legacy-file.json")
	var converted: Dictionary = migration_store.read("old-slot.json")
	check(converted.get("schema") == 3 and migration_store.compatible(converted, legacy_story),
		"Migrate a validated legacy chapter slot")
	var backup_store = SaveStore.new(migration_store.directory.path_join("legacy-backups"))
	check(backup_store.read("old-slot.json") == JSON.parse_string(JSON.stringify(old_save)), "Migration preserves the original legacy slot in a backup directory")
	check(converted.get("presentation", {}).get("location") == {"chapter": "legacy", "id": "legacy:d00001"}
		and converted.get("flow", {}).get("pc") == 1,
		"Restore migrated dialogue and resume position")
	var ambiguous_story := legacy_story.duplicate(true)
	ambiguous_story.chapters.legacy.program.push_front({"op": "branch", "id": "unknown_old_flag", "pc": 2})
	check(not migration_store.compatible(old_save, ambiguous_story), "Legacy migration must not guess flags before an old dialogue")
	# A legacy slot created after startup must be converted in memory on load.
	player.story["legacy_migrations"] = [{"source_sha256": "late-old-hash", "chapter": "manual_start",
		"frame_map": {"1": {"id": "manual_start:intro", "cursor": 0,
			"speaker": "Narrator", "text": "Choose a route."}}}]
	var late_slot := {"schema": 2, "source_sha256": "late-old-hash", "chapter": "manual_start",
		"cursor": 0, "frame_id": 1, "speaker": "Narrator", "text": "Choose a route."}
	player._choose_option(1)
	check(player.saves.write("late-old.json", late_slot), "Write late legacy slot")
	var late_loaded: bool = player._load_slot("late-old.json")
	check(late_loaded and player.current_location.chapter == "manual_start",
		"Load converts a legacy slot instead of applying its cursor to the current chapter")
	check(player.saves.read("late-old.json").get("schema") == 2, "Load does not overwrite original legacy slot")
	var before_unlock_failure: Dictionary = player.flow.snapshot()
	var unlocks: Dictionary = player.saves.global_flags()
	check(player.saves.write("global-unlocks.json", {"schema": 1, "flags": "invalid"}), "Write corrupt unlock fixture")
	check(not player._load_slot(choice_save) and player.flow.snapshot() == before_unlock_failure,
		"Invalid global unlocks reject load without replacing current flow")
	check(player.saves.write("global-unlocks.json", {"schema": 1, "flags": unlocks}), "Restore unlock fixture")
	var large_program: Array = []
	for index in range(6000):
		large_program.append({"op": "frame", "id": "unused-%d" % index})
	player.chapter_programs["unused_stress_chapter"] = large_program
	var long_history: Array = []
	for _index in range(1000):
		long_history.append(player.history[0].duplicate(true))
	check(player._validate_history(long_history, player.flow), "Validate 1000 history entries with a large chapter program")
	var long_slot: String = player.saves.save_runtime(player.story, player.flow.snapshot(),
		{"location": player.current_location.duplicate(true)}, long_history, "Long history", "long-history.json")
	check(not long_slot.is_empty() and player._load_slot(long_slot) and player.history.size() == 1000,
		"Save and load a 1000-entry history without losing its current frame")
	player.chapter_programs.erase("unused_stress_chapter")
	var failed_store = SaveStore.new("user://legacy-migration-failure-%d" % Time.get_ticks_usec())
	var tampered_save := old_save.duplicate(true)
	tampered_save.text = "内容不匹配"
	check(failed_store.write("old-slot.json", tampered_save), "Write invalid legacy migration fixture")
	failed_store.migrate_legacy(legacy_story, "user://missing-invalid-legacy-file.json")
	var preserved: Dictionary = failed_store.read("old-slot.json")
	check(preserved.get("schema") == 2 and preserved.get("text") == "内容不匹配"
		and preserved.get("source_sha256") == old_hash,
		"Failed legacy migration preserves the original save")
	for store in [migration_store, failed_store]:
		_cleanup_store(store)
	if "--skip-content-checks" not in OS.get_cmdline_user_args() and FileAccess.file_exists("res://content/story.json"):
		var full_story = JSON.parse_string(FileAccess.get_file_as_string("res://content/story.json"))
		check(full_story is Dictionary and player._prepare_story(full_story),
			"Prepare all imported chapter data")
		if full_story is Dictionary:
			check(player._validate_story_assets(), "Validate every imported scene and media asset")
			var full_flow = Flow.new()
			check(full_flow.begin(player.chapter_programs, player.story.entry),
				"Start imported story at its configured entry")
			var first_frame: Dictionary = full_flow.advance()
			check(first_frame.get("kind") == "frame"
				and first_frame.get("chapter") == player.story.entry,
				"Imported story begins at a dialogue frame")
			var sample_data = JSON.parse_string(FileAccess.get_file_as_string("res://content/sample.json"))
			if sample_data is Dictionary and not sample_data.get("frames", []).is_empty():
				var old_frame: Dictionary = sample_data.frames[0]
				var real_migration_store = SaveStore.new(
					"user://real-legacy-migration-test-%d" % Time.get_ticks_usec())
				var real_old_save := {
					"schema": 2,
					"source_sha256": sample_data.source_sha256,
					"chapter": sample_data.chapter,
					"cursor": 0,
					"frame_id": old_frame.id,
					"speaker": old_frame.speaker,
					"text": old_frame.text,
				}
				check(real_migration_store.write("sample-slot.json", real_old_save),
					"Write actual old sample save fixture")
				real_migration_store.migrate_legacy(player.story,
					"user://missing-real-legacy-save.json")
				var real_converted: Dictionary = real_migration_store.read("sample-slot.json")
				check(real_converted.get("schema") == 3
					and real_migration_store.compatible(real_converted, player.story),
					"Migrate a real old sample slot using the generated dialogue map")
				_cleanup_store(real_migration_store)
	check(player._load_slot("missing.json") == false, "Missing save is rejected")
	for id in DirAccess.get_files_at(player.saves.directory):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(player.saves.directory.path_join(id)))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(player.saves.directory))
	print("PLAYER_FLOW: %s" % ("PASS" if failures == 0 else "FAIL"))
	await player._stop_audio()
	await process_frame
	quit(0 if failures == 0 else 1)


func _cleanup_store(store) -> void:
	var backups: String = store.directory.path_join("legacy-backups")
	if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(backups)):
		for id in DirAccess.get_files_at(backups):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(backups.path_join(id)))
		DirAccess.remove_absolute(ProjectSettings.globalize_path(backups))
	for id in DirAccess.get_files_at(store.directory):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(store.directory.path_join(id)))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(store.directory))
