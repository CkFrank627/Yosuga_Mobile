# SPDX-License-Identifier: GPL-2.0-only
extends Control

const CONTENT := "res://content/"
const SaveStore = preload("res://save_store.gd")
const StoryFlow = preload("res://story_flow.gd")
const READER_FONT = preload("res://fonts/NotoSansCJKsc-Regular.otf")
const FrontMenu = preload("res://front_menu.gd")
const NativePresentation = preload("res://native_presentation.gd")
const DisplayPreview = preload("res://display_preview.gd")
const UITouch = preload("res://ui_touch.gd")
const ThumbSlider = preload("res://thumb_slider.gd")
var native_visuals: Control
var presentation_busy := false
var native_dialogue_styles: Dictionary = {}
var front: Control
var on_title := false
var font_size := 30
var text_speed := 32.0
var auto_delay := 3.0
var dialogue_color := Color(0.035, 0.055, 0.08, 1.0)
var dialogue_opacity := 0.88
var dialogue_mode := "classic"
var classic_fallback_style: StyleBoxFlat
var preferences_panel: PanelContainer
var dialogue_mode_buttons: Array[Button] = []
var dialogue_color_picker: ColorPickerButton
var music_volume := 0.8
var voice_volume := 1.0
var effect_volume := 0.8
var display_mode := "original"
var scene_color_mode := "light"
var color_mode_buttons: Array[Button] = []
var image_color_material: ShaderMaterial
var display_mode_buttons: Array[Button] = []
var ui_touch = UITouch.new()
var outside_mouse_start := Vector2.ZERO
var outside_mouse_tracking := false
var dialogue_style: StyleBoxFlat
var reveal_progress := 0.0
var revealed_for := 0.0
var settings_save_delay := -1.0
var preferences_preview: RichTextLabel
var saves = SaveStore.new()
var flow = StoryFlow.new()
var frame_lookup: Dictionary = {}
var history: Array = []
var history_cursor := -1
var current_location: Dictionary = {}
var choice_visible := false
var chapter_programs: Dictionary = {}
var unsupported_notified: Dictionary = {}
var chapter_frame_cache: Dictionary = {}
var transition_tweens: Array[Tween] = []
var show_progress := false
var book_mode := OS.has_feature("ios") or OS.has_feature("android")
var chrome_hidden := false
var notice_remaining := 0.0
var newest_first := true
var save_mode := false
var tap_surface: Control
var modal_shade: ColorRect
var hint: Label
var mouse_start := Vector2.ZERO
var mouse_tracking := false
var touch_start := Vector2.ZERO
var touch_index := -1
var touches: Dictionary = {}
var gesture_cancelled := false
var touch_travel := 0.0
var settings_path := "user://reader-settings.json"
var story: Dictionary = {}
var frames: Array = []
var cursor := 0
var elapsed := 0.0
var auto_read := false
var muted := false
var failed := false
var ending := false
var bg_fill: ColorRect
var bg: TextureRect
var actors: Array[TextureRect] = []
var actor_center_offsets: Dictionary = {}
var speaker: Label
var body: RichTextLabel
var progress: Label
var notice: Label
var toolbar: HBoxContainer
var dialogue: PanelContainer
var modal: PanelContainer
var modal_box: VBoxContainer
var auto_button: Button
var sound_button: Button
var voice_player: AudioStreamPlayer
var bgm_player: AudioStreamPlayer
var ambient_player: AudioStreamPlayer
var sound_player: AudioStreamPlayer
var last_bgm := ""
var last_ambient := ""
var application_paused := false
var suspended_audio: Dictionary = {}
var catalog_source := ""
var catalog_routes: Array = []
var catalog_route := "main"


func _ready() -> void:
	if "--smoke-test" in OS.get_cmdline_user_args() or "--capture" in OS.get_cmdline_user_args() or "--player-flow-test" in OS.get_cmdline_user_args():
		saves = SaveStore.new("user://smoke-saves-%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()])
		settings_path = saves.directory + "-settings.json"
	else:
		_load_settings()
	if "--mobile-input" in OS.get_cmdline_user_args():
		book_mode = true
	_build_ui()
	if "--player-flow-test" in OS.get_cmdline_user_args():
		return
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(_story_path()))
	if not parsed is Dictionary or (parsed.get("schema") != 1 and parsed.get("schema") != 2):
		_fail("尚未导入章节剧情数据，请先运行对应的内容导入流程。")
		return
	story = parsed
	if not _prepare_story(parsed):
		return
	if not _validate_story_assets():
		return
	var persistent_flags: Dictionary = saves.global_flags()
	if not saves.last_error.is_empty():
		_fail(saves.last_error)
		return
	if not flow.begin(chapter_programs, story.entry, persistent_flags):
		_fail("章节控制流无法启动：" + flow.error)
		return
	frames = _chapter_frames(story.entry)
	for frame in frames:
		if not frame is Dictionary or not frame.has_all(["id", "text", "speaker", "voice", "background", "characters", "bgm", "ambient", "sound"]):
			_fail("剧情数据格式错误。")
			return
	if "--smoke-test" not in OS.get_cmdline_user_args() and "--capture" not in OS.get_cmdline_user_args():
		saves.migrate_legacy(story)
		if not saves.last_error.is_empty():
			_toast(saves.last_error)
	if "--smoke-test" in OS.get_cmdline_user_args() or "--capture" in OS.get_cmdline_user_args():
		_advance_flow()
	else:
		_show_title()
	_layout_safe_area()
	resized.connect(_layout_safe_area)
	if "--smoke-test" in OS.get_cmdline_user_args():
		get_tree().create_timer(30).timeout.connect(func(): push_error("SMOKE_TIMEOUT: test did not complete"); get_tree().quit(1))
		call_deferred("_smoke_test")
	elif "--capture" in OS.get_cmdline_user_args():
		call_deferred("_capture")


func _story_path() -> String:
	if "--smoke-test" in OS.get_cmdline_user_args():
		return CONTENT + "sample.json"
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--story="):
			return argument.trim_prefix("--story=")
	return str(ProjectSettings.get_setting("story/content_path", CONTENT + "story.json"))


func _prepare_story(source: Dictionary) -> bool:
	frame_lookup.clear()
	chapter_programs.clear()
	chapter_frame_cache.clear()
	if source.get("schema") == 2:
		story = source.duplicate(true)
		if not story.get("entry") is String or not story.get("chapters") is Dictionary or not story.get("source_sha256") is String or not story.get("assets") is Dictionary:
			_fail("章节数据缺少入口、资源表或来源校验值。")
			return false
		for chapter_id in story.chapters:
			if not chapter_id is String or not story.chapters[chapter_id] is Dictionary:
				_fail("章节 ID 或章节数据类型错误。")
				return false
			var chapter: Dictionary = story.chapters[chapter_id]
			if not chapter.get("dialogue") is Dictionary or not chapter.get("scenes") is Dictionary or not chapter.get("program") is Array:
				_fail("章节数据格式错误：" + str(chapter_id))
				return false
			if chapter.scenes.size() != chapter.dialogue.size():
				_fail("对白和画面 ID 集合不一致：" + str(chapter_id))
				return false
			for dialogue_id in chapter.dialogue:
				if not dialogue_id is String or not chapter.scenes.has(dialogue_id) or not chapter.dialogue[dialogue_id] is Dictionary or not chapter.scenes[dialogue_id] is Dictionary:
					_fail("对白与画面数据未按稳定 ID 对齐：" + str(chapter_id) + "/" + str(dialogue_id))
					return false
				var line: Dictionary = chapter.dialogue[dialogue_id]
				var scene: Dictionary = chapter.scenes[dialogue_id]
				if not line.get("speaker") is String or not line.get("text") is String or not scene.get("characters", []) is Array:
					_fail("对白或画面字段类型错误：" + str(chapter_id) + "/" + str(dialogue_id))
					return false
				if not _validate_scene(_combine_frame(line, scene)):
					return false
				frame_lookup[_location_key(str(chapter_id), str(dialogue_id))] = _combine_frame(chapter.dialogue[dialogue_id], chapter.scenes[dialogue_id])
			for instruction in chapter.program:
				if instruction is Dictionary and instruction.get("op", "") == "frame" and (
						not instruction.get("id") is String or not chapter.dialogue.has(instruction.id)):
					_fail("控制流引用了不存在的对白：" + str(chapter_id))
					return false
			chapter_programs[chapter_id] = chapter.program
		if not story.chapters.has(story.entry):
			_fail("章节入口不存在：" + str(story.entry))
			return false
		return true
	if source.get("schema") != 1 or not source.get("frames") is Array or source.frames.is_empty():
		_fail("剧情数据格式错误。")
		return false
	var chapter_id := str(source.get("chapter", ""))
	if chapter_id.is_empty():
		_fail("旧版剧情缺少章节 ID。")
		return false
	var dialogue := {}
	var scenes := {}
	var program: Array = []
	for legacy_frame in source.frames:
		if not legacy_frame is Dictionary or not legacy_frame.has_all(["id", "text", "speaker", "voice", "background", "characters", "bgm", "ambient", "sound"]):
			_fail("剧情数据格式错误。")
			return false
		var line_id := "%s:d%05d" % [chapter_id, int(legacy_frame.id)]
		dialogue[line_id] = {"speaker": legacy_frame.speaker, "text": legacy_frame.text,
			"voice": legacy_frame.voice, "sound": legacy_frame.sound}
		scenes[line_id] = {"background": legacy_frame.background, "characters": legacy_frame.characters,
			"bgm": legacy_frame.bgm, "ambient": legacy_frame.ambient}
		frame_lookup[_location_key(chapter_id, line_id)] = legacy_frame.duplicate(true)
		program.append({"op": "frame", "id": line_id})
		# Keep old saves tied to the numeric source line when upgrading the sample runner.
		legacy_frame["runtime_id"] = line_id
	var runtime_chapter := {"dialogue": dialogue, "scenes": scenes, "program": program + [{"op": "end"}]}
	story = source.duplicate(true)
	story["entry"] = chapter_id
	story["chapters"] = {chapter_id: runtime_chapter}
	chapter_programs[chapter_id] = runtime_chapter.program
	return true


func _validate_story_assets() -> bool:
	var assets: Dictionary = story.get("assets", {})
	for chapter_id in story.chapters:
		var chapter: Dictionary = story.chapters[chapter_id]
		for scene in chapter.scenes.values():
			if not scene is Dictionary or not scene.get("characters", []) is Array:
				_fail("人物画面数据格式错误：" + str(chapter_id))
				return false
			for key in ["background", "bgm", "ambient", "sound"]:
				if not _validate_asset_name(str(scene.get(key, "")), assets):
					return false
			for character in scene.get("characters", []):
				var name := str(character) if character is String else str(character.get("asset", ""))
				if not _validate_asset_name(name, assets):
					return false
		for dialogue in chapter.dialogue.values():
			if not dialogue is Dictionary:
				_fail("对白数据格式错误：" + str(chapter_id))
				return false
			for key in ["voice", "sound"]:
				if not _validate_asset_name(str(dialogue.get(key, "")), assets):
					return false
	for asset in assets.values():
		if not ResourceLoader.exists(CONTENT + str(asset)):
			_fail("缺少资源：" + str(asset))
			return false
	return true


func _finite_number(value) -> bool:
	return (value is int or value is float) and is_finite(float(value))


func _validate_scene(frame: Dictionary) -> bool:
	for key in ["background", "bgm", "ambient", "voice", "sound"]:
		if not frame.get(key) is String:
			_fail("画面或音频资源名称必须为字符串。")
			return false
	for character in frame.get("characters", []):
		if character is String:
			continue
		if not character is Dictionary or not character.get("asset") is String or not _finite_number(character.get("x", 0.5)) or not _finite_number(character.get("y", 0.0)):
			_fail("人物资源或位置格式错误。")
			return false
	var camera = frame.get("camera", {})
	var transition = frame.get("transition", {})
	if not camera is Dictionary or not transition is Dictionary or not _finite_number(camera.get("zoom", 1.0)) or not _finite_number(transition.get("duration", 0.25)):
		_fail("镜头或转场参数格式错误。")
		return false
	var offset = camera.get("offset", [0.0, 0.0])
	if not offset is Array or offset.size() != 2 or not _finite_number(offset[0]) or not _finite_number(offset[1]):
		_fail("镜头偏移必须为两个数值组成的数组。")
		return false
	var color = frame.get("background_color", [0, 0, 0])
	if not color is Array or color.size() != 3:
		_fail("背景颜色必须为 RGB 三元组。")
		return false
	for component in color:
		if not _finite_number(component) or component < 0 or component > 255:
			_fail("背景颜色分量超出范围。")
			return false
	if not frame.get("hide_characters", []) is Array:
		_fail("隐藏人物列表格式错误。")
		return false
	return true


func _validate_asset_name(name: String, assets: Dictionary) -> bool:
	if name.is_empty() or assets.has(name):
		return true
	_fail("章节引用了未登记的资源：" + name)
	return false


func _location_key(chapter_id: String, dialogue_id: String) -> String:
	return chapter_id + "\u001f" + dialogue_id


func _combine_frame(dialogue: Dictionary, scene: Dictionary) -> Dictionary:
	var frame := {"speaker": "", "text": "", "voice": "", "sound": "",
		"background": "", "background_color": [0, 0, 0],
		"characters": [], "bgm": "", "ambient": ""}
	for key in scene:
		frame[key] = scene[key]
	for key in dialogue:
		frame[key] = dialogue[key]
	return frame


func _chapter_frames(chapter_id: String) -> Array:
	if chapter_frame_cache.has(chapter_id):
		return chapter_frame_cache[chapter_id]
	var result: Array = []
	var chapter: Dictionary = story.get("chapters", {}).get(chapter_id, {})
	for dialogue_id in chapter.get("dialogue", {}):
		var frame: Dictionary = _combine_frame(chapter.dialogue[dialogue_id], chapter.scenes[dialogue_id])
		frame["id"] = dialogue_id
		frame["runtime_id"] = dialogue_id
		result.append(frame)
	result.sort_custom(func(a, b): return str(a.runtime_id) < str(b.runtime_id))
	chapter_frame_cache[chapter_id] = result
	return result


func _runtime_frame(chapter_id: String, dialogue_id: String) -> Dictionary:
	if frame_lookup.has(_location_key(chapter_id, dialogue_id)):
		var cached: Dictionary = frame_lookup[_location_key(chapter_id, dialogue_id)].duplicate(true)
		cached["id"] = dialogue_id
		cached["runtime_id"] = dialogue_id
		return cached
	var chapter: Dictionary = story.chapters.get(chapter_id, {})
	if chapter.has("dialogue") and chapter.dialogue.has(dialogue_id) and chapter.get("scenes", {}).has(dialogue_id):
		var frame := _combine_frame(chapter.dialogue[dialogue_id], chapter.scenes[dialogue_id])
		frame["id"] = dialogue_id
		frame["runtime_id"] = dialogue_id
		return frame
	return {}


func _build_ui() -> void:
	var ui_theme := Theme.new()
	ui_theme.default_font = READER_FONT
	ui_theme.default_font_size = 24
	theme = ui_theme
	bg_fill = ColorRect.new()
	image_color_material = ShaderMaterial.new()
	var image_color_shader := Shader.new()
	image_color_shader.code = NativePresentation.TONE_SHADER
	image_color_material.shader = image_color_shader
	bg_fill.material = image_color_material
	bg_fill.color = Color.BLACK
	bg_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg_fill)
	bg_fill.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg = _image_layer(TextureRect.STRETCH_KEEP_ASPECT_COVERED)
	for _index in range(4):
		actors.append(_image_layer(TextureRect.STRETCH_KEEP_ASPECT_CENTERED))
	native_visuals = NativePresentation.new()
	add_child(native_visuals)
	native_visuals.setup(self)
	native_visuals.hide()
	native_visuals.viewport.render_target_update_mode=SubViewport.UPDATE_DISABLED
	tap_surface = Control.new()
	add_child(tap_surface)
	tap_surface.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	tap_surface.gui_input.connect(_mouse_reading_input)
	toolbar = HBoxContainer.new()
	toolbar.add_theme_constant_override("separation", 12)
	add_child(toolbar)
	_button(toolbar, "重读", _confirm_restart)
	_button(toolbar, "存档", func(): _save_list(true))
	_button(toolbar, "读档", func(): _save_list(false))
	_button(toolbar, "回看", _history)
	_button(toolbar, "章节目录", _chapter_directory)
	auto_button = _button(toolbar, "自动：关", _toggle_auto)
	sound_button = _button(toolbar, "声音：开", _toggle_sound)
	_button(toolbar, "设置", _settings)
	_button(toolbar, "全文", _full_text)
	_button(toolbar, "标题", _confirm_title)
	progress = Label.new()
	progress.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	progress.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(progress)
	progress.visible = show_progress
	dialogue = PanelContainer.new()
	dialogue.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	dialogue_style = style
	style.bg_color = Color(0.035, 0.055, 0.08, 0.88)
	style.border_color = Color(0.65, 0.78, 0.8, 0.65)
	style.set_border_width_all(1)
	style.set_corner_radius_all(12)
	style.content_margin_left = 28
	style.content_margin_right = 28
	style.content_margin_top = 16
	style.content_margin_bottom = 16
	classic_fallback_style = style.duplicate()
	classic_fallback_style.bg_color = Color(0.1,0.35,0.45,dialogue_opacity)
	dialogue.add_theme_stylebox_override("panel", style)
	add_child(dialogue)
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dialogue.add_child(column)
	speaker = Label.new()
	speaker.add_theme_color_override("font_color", Color(0.72, 0.9, 0.92))
	speaker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(speaker)
	body = RichTextLabel.new()
	body.bbcode_enabled = false
	body.visible_characters_behavior = TextServer.VC_CHARS_AFTER_SHAPING
	body.scroll_active = false
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_theme_font_size_override("normal_font_size", 30)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(body)
	hint = Label.new()
	_update_hint()
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hint.add_theme_font_size_override("font_size", 18)
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(hint)
	notice = Label.new()
	notice.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	notice.mouse_filter = Control.MOUSE_FILTER_IGNORE
	notice.z_index = 10
	notice.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	notice.add_theme_constant_override("outline_size", 8)
	add_child(notice)
	modal_shade = ColorRect.new()
	modal_shade.color = Color(0, 0, 0, 0.45)
	modal_shade.visible = false
	modal_shade.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(modal_shade)
	modal_shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	modal_shade.gui_input.connect(func(event):_outside_panel_input(event,modal,modal_shade,_dismiss_modal))
	modal = PanelContainer.new()
	modal.visible = false
	modal.mouse_filter = Control.MOUSE_FILTER_STOP
	var modal_style := style.duplicate()
	modal_style.bg_color = Color(0.035, 0.055, 0.08, 0.99)
	modal.add_theme_stylebox_override("panel", modal_style)
	add_child(modal)
	modal_box = VBoxContainer.new()
	modal_box.add_theme_constant_override("separation", 16)
	modal.add_child(modal_box)
	voice_player = _audio_player()
	bgm_player = _audio_player(-14)
	ambient_player = _audio_player(-18)
	sound_player = _audio_player(-10)
	front = FrontMenu.new()
	add_child(front)
	move_child(front, modal_shade.get_index())
	front.setup(self)
	front.hide()
	_apply_preferences()


func _image_layer(stretch: int) -> TextureRect:
	var layer := TextureRect.new()
	layer.material = image_color_material
	layer.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	layer.stretch_mode = stretch
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(layer)
	layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return layer


func _audio_player(volume := 0.0) -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	player.volume_db = volume
	add_child(player)
	return player


func _button(parent: Node, text: String, action: Callable, role := "auto") -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(100, 52)
	button.focus_mode = Control.FOCUS_NONE
	parent.add_child(button)
	button.pressed.connect(action)
	if role=="auto":
		if "删除" in text:role = "danger"
		elif "覆盖" in text:role = "warning"
		elif text in ["新建存档","确认读取","读取","保存名称","保存并返回标题","从头阅读","重新开始","播放","放大查看","适应屏幕"]:role = "primary"
		elif text.begins_with("返回") or text in ["取消","继续阅读","继续当前进度","重命名"]:role = "secondary"
	if role=="auto":role = "normal"
	_style_action_button(button,role)
	return button


func _style_action_button(button: Button, role: String) -> void:
	var accent: Color = {"primary":Color("238b99"),"danger":Color("ad424b"),"warning":Color("906223"),"secondary":Color("365f78"),"normal":Color("263b49")}.get(role,Color("238b99"))
	button.set_meta("action_role",role)
	button.custom_minimum_size.y = 58
	if role=="primary":button.custom_minimum_size.x = maxf(button.custom_minimum_size.x,160)
	for state in ["normal","hover","pressed","disabled","focus"]:
		var style := StyleBoxFlat.new()
		style.bg_color = accent.darkened(0.65) if role=="secondary" else accent
		if state=="hover":style.bg_color = accent.lightened(0.15)
		if state=="pressed":style.bg_color = accent.darkened(0.2)
		if state=="disabled":style.bg_color = Color("303b42")
		style.border_color = accent.lightened(0.35) if state!="disabled" else Color("53616a")
		style.set_border_width_all(1 if role=="normal" else 2)
		style.set_corner_radius_all(10)
		style.set_content_margin_all(12)
		button.add_theme_stylebox_override(state,style)
	button.add_theme_color_override("font_color",Color.WHITE)
	button.add_theme_color_override("font_hover_color",Color.WHITE)
	button.add_theme_color_override("font_pressed_color",Color.WHITE)


func _scroll_container() -> ScrollContainer:
	var scroll := ScrollContainer.new()
	# UI touch scrolling is owned by ui_touch; disable the competing native
	# mouse-emulation drag. Wheel, trackpad and scrollbar input still work.
	scroll.scroll_deadzone = 1000000
	scroll.get_v_scroll_bar().custom_minimum_size.x = 18
	return scroll


func _outside_panel_input(event: InputEvent, panel: Control, origin: Control, action: Callable) -> void:
	if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT:
		var point: Vector2 = origin.get_global_transform()*event.position
		if event.pressed:
			outside_mouse_start = point
			outside_mouse_tracking = not panel.get_global_rect().has_point(point)
		else:
			var close: bool = outside_mouse_tracking and not event.canceled and not panel.get_global_rect().has_point(point) and point.distance_to(outside_mouse_start)<=20.0
			outside_mouse_tracking = false
			if close:
				origin.accept_event()
				action.call()
	elif event is InputEventMouseMotion and outside_mouse_tracking:
		if (origin.get_global_transform()*event.position).distance_to(outside_mouse_start)>20.0:outside_mouse_tracking = false


func _dismiss_modal() -> void:
	choice_visible = false
	_close_modal(false) # An unresolved choice reopens on the next advance.


func _layout_safe_area() -> void:
	for option in display_mode_buttons+color_mode_buttons:
		if is_instance_valid(option) and is_instance_valid(option.get_meta("preview_aspect",null)):
			option.get_meta("preview_aspect").ratio = size.x/maxf(size.y,1.0)
	var margin := Vector2(32, 24)
	if OS.has_feature("ios"):
		var window_size := Vector2(DisplayServer.window_get_size())
		var safe := DisplayServer.get_display_safe_area()
		if window_size.x > 0 and window_size.y > 0:
			var ratio := size / window_size
			margin.x = maxf(margin.x, maxf(safe.position.x, window_size.x - safe.end.x) * ratio.x + 12)
			margin.y = maxf(margin.y, maxf(safe.position.y, window_size.y - safe.end.y) * ratio.y + 12)
	toolbar.position = margin
	var toolbar_fit := minf(1.0,(size.x-margin.x*2)/maxf(toolbar.get_combined_minimum_size().x,1.0))
	toolbar.scale = Vector2.ONE*toolbar_fit
	progress.position = Vector2(size.x - margin.x - 270, margin.y + 62)
	progress.size = Vector2(270, 30)
	var dialogue_height := minf(float(font_size * 5 + 80), size.y * 0.55)
	dialogue.position = Vector2(margin.x, size.y - margin.y - dialogue_height)
	dialogue.size = Vector2(size.x - 2 * margin.x, dialogue_height)
	notice.position = Vector2(margin.x, size.y - margin.y - 38)
	notice.size = Vector2(size.x - 2 * margin.x, 36)
	modal.position = Vector2(margin.x + 24, margin.y + 80)
	modal.size = Vector2(size.x - 2 * margin.x - 48, size.y - 2 * margin.y - 100)
	if is_instance_valid(front):
		front.layout(margin)
	if current_location.has_all(["chapter", "id"]):
		var frame := _runtime_frame(current_location.chapter, current_location.id)
		if not frame.is_empty():
			_layout_visuals(frame)


func _texture(name: String) -> Texture2D:
	if name.is_empty():
		return null
	if story.get("native_presentation",false) and name in story.get("source_absent_assets",[]):
		return null
	return load(CONTENT + str(story.assets[name])) as Texture2D


func _play(player: AudioStreamPlayer, name: String, loop := false) -> void:
	player.stop()
	if story.get("native_presentation",false) and name in story.get("source_absent_assets",[]):
		return
	if name.is_empty():
		player.stream = null
		return
	var stream = load(CONTENT + str(story.assets[name]))
	if loop and stream is AudioStreamWAV:
		stream = stream.duplicate()
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_begin = 0
		stream.loop_end = int(stream.get_length() * stream.mix_rate)
	elif loop and stream is AudioStreamOggVorbis:
		stream = stream.duplicate()
		stream.loop = true
		stream.loop_offset = 0.0
	player.stream = stream
	player.play()
	player.stream_paused = application_paused


func _show_frame(index: int) -> void:
	cursor = clampi(index, 0, frames.size() - 1)
	var frame: Dictionary = frames[cursor]
	current_location = {"chapter": str(current_location.get("chapter", story.get("entry", ""))),
		"id": str(frame.get("runtime_id", frame.get("id", "")))}
	_render_frame(frame)
	var code: Array = chapter_programs.get(current_location.chapter, [])
	var linear := true
	for instruction in code:
		if instruction.get("op", "") not in ["frame", "end"]:
			linear = false
			break
	if linear:
		var snapshot := flow.snapshot()
		snapshot.chapter = current_location.chapter
		snapshot.pending = []
		for instruction_index in range(code.size()):
			if code[instruction_index].get("op", "") == "frame" and code[instruction_index].get("id", "") == current_location.id:
				snapshot.pc = instruction_index + 1
				break
		flow.restore(snapshot)
	history = [{"location": current_location.duplicate(true), "flow": flow.snapshot()}]
	history_cursor = 0


func _render_frame(frame: Dictionary) -> void:
	for tween in transition_tweens:
		if tween.is_valid():
			tween.kill()
	transition_tweens.clear()
	elapsed = 0
	reveal_progress = 0.0
	revealed_for = 0.0
	ending = false
	var rgb: Array = frame.get("background_color", [0, 0, 0])
	bg_fill.color = Color8(int(rgb[0]), int(rgb[1]), int(rgb[2]))
	bg.texture = _texture(frame.background)
	var hidden: Array = frame.get("hide_characters", [])
	while actors.size() < frame.characters.size():
		var layer := _image_layer(TextureRect.STRETCH_KEEP_ASPECT_CENTERED)
		move_child(layer, tap_surface.get_index())
		actors.append(layer)
	for index in range(actors.size()):
		var layer := actors[index]
		layer.texture = null
		layer.visible = false
		if index >= frame.characters.size():
			continue
		var character = frame.characters[index]
		var asset := str(character) if character is String else str(character.get("asset", ""))
		var character_id := str(character.get("id", asset)) if character is Dictionary else asset
		if asset.is_empty() or character_id in hidden or (character is Dictionary and not character.get("visible", true)):
			continue
		layer.texture = _texture(asset)
		layer.visible = true
	_layout_visuals(frame)
	var native_mode: bool = story.get("native_presentation",false)
	native_visuals.visible = native_mode
	native_visuals.viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS if native_mode else SubViewport.UPDATE_DISABLED
	if native_mode:
		bg.hide()
		for layer in actors:
			layer.hide()
		if history_cursor >= 0 and history_cursor < history.size() and history[history_cursor].location == current_location and history[history_cursor].has("native_state"):
			native_visuals.restore(history[history_cursor].native_state)
		dialogue.visible = not chrome_hidden
		var native_font: int = int(native_visuals.state.get("font",0))
		body.add_theme_font_size_override("normal_font_size",int(native_font*size.y/600.0) if native_font>0 else font_size)
		_apply_native_window()
		_layout_safe_area()
	else:
		bg.show()
		_apply_dialogue_style()
	speaker.text = "" if frame.speaker == "心の声" else str(frame.speaker)
	body.text = str(frame.text).replace("／","\n").replace("　","  ") if native_mode else frame.text
	body.visible_characters = 0
	progress.text = "%s  %d / %d" % [str(current_location.chapter), cursor + 1, frames.size()]
	_play(voice_player, frame.voice)
	_play(sound_player, frame.sound)
	if last_bgm != frame.bgm:
		last_bgm = frame.bgm
		_play(bgm_player, last_bgm, true)
	if last_ambient != frame.ambient:
		last_ambient = frame.ambient
		_play(ambient_player, last_ambient, true)
	var transition: Dictionary = frame.get("transition", {})
	if transition.get("type", "") == "fade":
		var duration := clampf(float(transition.get("duration", 0.25)), 0.0, 3.0)
		for layer in [bg] + actors:
			if layer.visible:
				layer.modulate.a = 0
				var tween := create_tween()
				transition_tweens.append(tween)
				tween.tween_property(layer, "modulate:a", 1.0, duration)
	else:
		for layer in [bg] + actors:
			layer.modulate.a = 1


func _actor_center_offset(texture: Texture2D) -> float:
	if texture == null:
		return 0.0
	# Cache only the scalar, without retaining every decoded image/texture.
	var key = texture.resource_path if not texture.resource_path.is_empty() else texture.get_instance_id()
	if not actor_center_offsets.has(key):
		var image := texture.get_image()
		if image != null and image.is_compressed():image.decompress()
		var offset := 0.0
		if image != null and not image.is_empty() and not image.is_compressed():
			var bounds := image.get_used_rect()
			if bounds.has_area():
				offset = image.get_width() * 0.5 - (bounds.position.x + bounds.size.x * 0.5)
		actor_center_offsets[key] = offset
	return float(actor_center_offsets[key])


func _layout_visuals(frame: Dictionary) -> void:
	var camera: Dictionary = frame.get("camera", {})
	var zoom := maxf(float(camera.get("zoom", 1.0)), 0.1)
	var offset: Array = camera.get("offset", [0.0, 0.0])
	var camera_offset := Vector2(float(offset[0]), float(offset[1]))
	# Converted source coordinates describe the origin of an 800 x 600
	# background crop. They are not a translation of the foreground scene.
	bg.set_anchors_preset(Control.PRESET_TOP_LEFT)
	if camera.get("source_coordinates", false):
		var source_size := Vector2(800, 600)
		if bg.texture != null:
			source_size = bg.texture.get_size().max(source_size)
		var source_scale := size / Vector2(800, 600)
		var crop_origin := camera_offset.clamp(Vector2.ZERO, source_size - Vector2(800, 600))
		bg.stretch_mode = TextureRect.STRETCH_SCALE
		bg.size = source_size * source_scale
		bg.position = -crop_origin * source_scale
		camera_offset = Vector2.ZERO
	else:
		bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		bg.size = size
		bg.position = camera_offset
	bg.pivot_offset = size * 0.5 - bg.position if camera.get("source_coordinates", false) else size * 0.5
	bg.scale = Vector2.ONE * zoom
	for index in range(actors.size()):
		if index >= frame.characters.size():
			continue
		var layer := actors[index]
		var character = frame.characters[index]
		var default_x := float(index + 1) / float(frame.characters.size() + 1)
		var normalized_x := float(character.get("x", default_x)) if character is Dictionary else default_x
		layer.anchor_left = 0
		layer.anchor_right = 0
		layer.anchor_top = 0
		layer.anchor_bottom = 0
		layer.size = Vector2(size.x * 0.56, size.y)
		var vertical_offset := float(character.get("y", 0.0)) * size.y / 600.0 if character is Dictionary else 0.0
		var center_offset := 0.0
		if layer.texture != null:
			var texture_size := layer.texture.get_size()
			var fit := minf(layer.size.x / texture_size.x, layer.size.y / texture_size.y)
			center_offset = _actor_center_offset(layer.texture) * fit
		# Center the visible pixels, rather than asymmetric transparent padding.
		# Preserve the script's requested x, including multi-character positions.
		layer.position = Vector2(size.x * clampf(normalized_x, 0.0, 1.0) - layer.size.x * 0.5 + center_offset, vertical_offset) + camera_offset
		layer.pivot_offset = layer.size * 0.5 - Vector2(center_offset, 0)
		layer.scale = Vector2.ONE * zoom


func _advance() -> void:
	if presentation_busy:
		native_visuals.skip_requested = true
		return
	if failed or modal.visible or application_paused or on_title:
		return
	if not chrome_hidden and body.visible_characters >= 0 and body.visible_characters < body.get_total_character_count():
		body.visible_characters = -1
		revealed_for = 0.0
		return
	_advance_flow()


func _apply_native_window() -> void:
	_apply_dialogue_style()


func _apply_dialogue_style() -> void:
	dialogue_style.bg_color = Color(dialogue_color,dialogue_opacity)
	dialogue_style.border_color = Color(0.65,0.78,0.8,0.65*dialogue_opacity)
	classic_fallback_style.bg_color = Color(0.1,0.35,0.45,dialogue_opacity)
	classic_fallback_style.border_color = Color(0.65,0.78,0.8,0.65*dialogue_opacity)
	var selected: StyleBox = dialogue_style
	if dialogue_mode=="classic":
		selected = classic_fallback_style
		var type: int = int(native_visuals.state.get("window",0))
		var asset: String = "FRM_0106B" if type==1 else "FRM_0102B"
		if story.get("assets",{}).has(asset):
			if not native_dialogue_styles.has(type):
				var style := StyleBoxTexture.new()
				style.texture = _texture(asset)
				style.content_margin_left = 28
				style.content_margin_right = 28
				style.content_margin_top = 16
				style.content_margin_bottom = 16
				native_dialogue_styles[type] = style
			var original: StyleBoxTexture = native_dialogue_styles[type]
			original.modulate_color = Color(1,1,1,dialogue_opacity)
			selected = original
	dialogue.add_theme_stylebox_override("panel",selected)
	if is_instance_valid(preferences_panel):preferences_panel.add_theme_stylebox_override("panel",selected)
	if is_instance_valid(dialogue_color_picker):dialogue_color_picker.disabled = dialogue_mode!="custom"
	for option in dialogue_mode_buttons:
		if is_instance_valid(option):option.set_pressed_no_signal(option.get_meta("dialogue_mode")==dialogue_mode)


func _advance_flow() -> void:
	if history_cursor >= 0 and history_cursor < history.size() - 1:
		history_cursor += 1
		var next: Dictionary = history[history_cursor]
		if not flow.restore(next.flow):
			_fail("阅读历史中的控制流状态损坏。")
			return
		current_location = next.location.duplicate(true)
		frames = _chapter_frames(current_location.chapter)
		for index in range(frames.size()):
			if frames[index].runtime_id == current_location.id:
				cursor = index
				break
		_render_frame(_runtime_frame(current_location.chapter, current_location.id))
		return
	# Source Font() applies to one Hitret paragraph, then resets its sequence.
	if story.get("native_presentation",false):
		native_visuals.state.font=0
		native_visuals.pending.font=0
	var result: Dictionary = flow.advance()
	while result.get("kind", "") == "presentation":
		if not story.get("native_presentation",false):
			_fail("章节含原版演出指令，但未启用对应播放器。")
			return
		presentation_busy = true
		for button in toolbar.get_children():
			if button is Button:button.disabled = true
		native_visuals.show()
		native_visuals.viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS
		bg.hide()
		for layer in actors:
			layer.hide()
		var success: bool = await native_visuals.execute(result.command,result.args)
		presentation_busy = false
		for button in toolbar.get_children():
			if button is Button:button.disabled = false
		if not success:
			_fail("原版演出执行失败：%s:%s %s" % [result.chapter,result.source_line,native_visuals.error])
			return
		result = flow.advance()
	if not saves.merge_global_flags(flow.global_flags):
		_fail(saves.last_error)
		return
	match result.get("kind", ""):
		"frame":
			current_location = {"chapter": result.chapter, "id": str(result.id)}
			frames = _chapter_frames(current_location.chapter)
			var frame := _runtime_frame(current_location.chapter, current_location.id)
			if frame.is_empty():
				_fail("对白节点不存在：" + _location_key(current_location.chapter, current_location.id))
				return
			cursor = 0
			for index in range(frames.size()):
				if frames[index].runtime_id == current_location.id:
					cursor = index
					break
			_render_frame(frame)
			_remember_frame()
			var unsupported: Dictionary = story.get("unsupported", {}).duplicate(true) if story.get("unsupported", {}) is Dictionary else {}
			var chapter_id: String = current_location.chapter
			var chapter_unsupported = story.chapters.get(chapter_id, {}).get("unsupported", {})
			if chapter_unsupported is Dictionary:
				for instruction in chapter_unsupported:
					unsupported[instruction] = chapter_unsupported[instruction]
			if not unsupported.is_empty() and not unsupported_notified.has(chapter_id):
				unsupported_notified[chapter_id] = true
				print("Unimplemented presentation in %s: %s" % [chapter_id, _unsupported_summary(unsupported)])
				_toast("本章部分画面演出尚未完整还原。")
		"choice":
			_show_choice(result.options)
		"end":
			_show_chapter_end()
		"error":
			_fail("章节控制流错误：" + str(result.get("message", flow.error)))
		_:
			_fail("章节控制流返回了未知状态。")


func _remember_frame() -> void:
	if history_cursor < history.size() - 1:
		history.resize(history_cursor + 1)
	history.append({"location": current_location.duplicate(true), "flow": flow.snapshot()})
	if story.get("native_presentation",false):
		history.back()["native_state"] = native_visuals.snapshot()
	history_cursor = history.size() - 1


func _unsupported_summary(unsupported: Dictionary) -> String:
	var labels: Array[String] = []
	for instruction in unsupported:
		labels.append("%s (%s)" % [str(instruction), str(unsupported[instruction])])
	return ", ".join(labels)


func _show_choice(options: Array) -> void:
	choice_visible = true
	auto_read = false
	auto_button.text = "自动：关"
	_open_modal("请选择")
	if current_location.has_all(["chapter", "id"]):
		_modal_description(_preview_text(_runtime_frame(current_location.chapter, current_location.id)))
	for index in range(options.size()):
		var option: Dictionary = options[index]
		_button(modal_box, str(option.text), _choose_option.bind(index), "primary")
	var actions := HBoxContainer.new()
	modal_box.add_child(actions)
	_button(actions, "保存进度", func(): _save_list(true))
	_button(actions, "读取进度", func(): _save_list(false))


func _choose_option(index: int) -> void:
	if index < 0 or index >= flow.pending.size():
		_fail("选项编号无效。")
		return
	if history_cursor < history.size() - 1:
		history.resize(history_cursor + 1)
	if not flow.choose(index):
		_fail("无法应用所选路线。")
		return
	choice_visible = false
	_close_modal()
	_advance_flow()


func _show_chapter_end() -> void:
	auto_read = false
	auto_button.text = "自动：关"
	ending = true
	_open_modal("章节结束")
	var label := Label.new()
	label.text = str(story.get("chapters", {}).get(current_location.get("chapter", ""), {}).get("title", current_location.get("chapter", "本章"))) + " 已结束。"
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	modal_box.add_child(label)
	_button(modal_box, "从头阅读", func():
		_close_modal()
		if not flow.begin(chapter_programs, story.entry, saves.global_flags()):
			_fail(flow.error)
			return
		history.clear()
		history_cursor = -1
		_advance_flow())
	_button(modal_box, "返回最后一句", _close_modal)
	_button(modal_box, "返回标题", _show_title)


func _confirm_title() -> void:
	_open_modal("返回标题？")
	_modal_description("当前进度会自动保存，也可以从标题页继续阅读。")
	_button(modal_box, "保存并返回标题", _show_title)
	_button(modal_box, "继续阅读", _close_modal)


func _show_title() -> void:
	if not on_title and not current_location.is_empty() and not history.is_empty():
		if _save_current("自动存档", "autosave.json").is_empty():
			return
	on_title = true
	native_visuals.clear_color_previews()
	color_mode_buttons.clear()
	auto_read = false
	auto_button.text = "自动：关"
	chrome_hidden = false
	_reset_gestures()
	modal.hide()
	modal_shade.hide()
	for player in [voice_player, bgm_player, ambient_player, sound_player]:
		player.stop()
		player.stream = null
	last_bgm = ""
	last_ambient = ""
	native_visuals.suspend(true)
	native_visuals.viewport.render_target_update_mode=SubViewport.UPDATE_DISABLED
	front.configure(story)
	front.show_title()
	_apply_preferences()
	_apply_chrome()


func _leave_title() -> void:
	if not on_title:
		return
	on_title = false
	native_visuals.suspend(false)
	native_visuals.viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS if story.get("native_presentation",false) else SubViewport.UPDATE_DISABLED
	front.deactivate()
	chrome_hidden = false
	_apply_chrome()
	_reset_gestures()


func _has_continue() -> bool:
	return not history.is_empty() or saves.compatible(saves.read("autosave.json"), story)


func _continue_from_title() -> void:
	if history.is_empty():
		_load_slot("autosave.json")
		return
	_leave_title()
	_render_frame(_runtime_frame(current_location.chapter, current_location.id))
	body.visible_characters = -1
	if not flow.pending.is_empty():
		_show_choice(flow.pending)


func _new_from_title() -> void:
	if history.is_empty():
		_start_new()
		return
	_open_modal("重新开始阅读？")
	_modal_description("手动存档会保留；本次重新从剧情入口开始。")
	_button(modal_box, "重新开始", _start_new)
	_button(modal_box, "取消", _close_modal)


func _start_new() -> void:
	var persistent := saves.global_flags()
	if not saves.last_error.is_empty():
		_toast(saves.last_error)
		return
	if not flow.begin(chapter_programs, story.entry, persistent):
		_fail(flow.error)
		return
	choice_visible = false
	modal.hide()
	modal_shade.hide()
	history.clear()
	history_cursor = -1
	current_location = {}
	if story.get("native_presentation",false):
		native_visuals.reset()
	_leave_title()
	_advance_flow()


func _chapter_routes() -> Array:
	var source := str(story.get("source_sha256",""))
	if catalog_source==source and not catalog_routes.is_empty():return catalog_routes
	catalog_routes.clear()
	catalog_source = source
	var path := CONTENT+"chapter_catalog.json"
	if FileAccess.file_exists(path):
		var data = JSON.parse_string(FileAccess.get_file_as_string(path))
		if data is Dictionary and data.get("schema")==1 and data.get("source_sha256")==source and data.get("routes") is Array:
			catalog_routes = data.routes
	if catalog_routes.is_empty():
		var entries := []
		for id in chapter_programs:
			entries.append({"chapter":id,"title":"主线"+str(entries.size()+1),"flags":{}})
		catalog_routes = [{"id":"main","title":"主线","entries":entries}]
	return catalog_routes


func _chapter_directory(route_id := "") -> void:
	if presentation_busy or failed:return
	var routes := _chapter_routes()
	if not route_id.is_empty():catalog_route = route_id
	elif not current_location.is_empty():
		for route in routes:
			for entry in route.entries:
				if entry.chapter==current_location.chapter:catalog_route=route.id
	var selected: Dictionary = routes[0]
	for route in routes:
		if route.id==catalog_route:selected=route
	catalog_route = selected.id
	_open_modal("章节目录")
	_modal_description("选择路线，再点击章节即可跳转。跳转前会自动保存当前进度，手动存档保留。")
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation",10)
	modal_box.add_child(tabs)
	for route in routes:
		var tab := _button(tabs,route.title,func():_chapter_directory(route.id),"primary" if route.id==selected.id else "secondary")
		tab.name = "Route_"+str(route.id)
		tab.custom_minimum_size.x = 100
		tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var count := Label.new()
	count.text = "%s · %d 章" % [selected.title,selected.entries.size()]
	modal_box.add_child(count)
	var scroll := _scroll_container()
	scroll.name = "ChapterScroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	modal_box.add_child(scroll)
	var grid := GridContainer.new()
	grid.name = "ChapterGrid"
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation",14)
	grid.add_theme_constant_override("v_separation",14)
	scroll.add_child(grid)
	var arrange := func():grid.columns = clampi(int(scroll.size.x/240.0),1,5)
	scroll.resized.connect(arrange)
	arrange.call_deferred()
	for entry in selected.entries:
		var button := _button(grid,entry.title,func():_jump_to_chapter(entry),"primary" if entry.chapter==current_location.get("chapter","") else "normal")
		button.set_meta("chapter_id",entry.chapter)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.custom_minimum_size = Vector2(210,68)
	_button(modal_box,"返回标题" if on_title else "返回阅读",_close_modal,"secondary")


func _jump_to_chapter(entry: Dictionary) -> void:
	if presentation_busy or failed:return
	var id := str(entry.get("chapter",""))
	if not chapter_programs.has(id):
		_toast("章节不存在。")
		return
	if story.get("native_presentation",false) and not _validate_native_state(entry.get("native_state",{})):
		_toast("章节起始画面数据缺失或无效，请更新章节目录数据。")
		return
	var persistent := saves.global_flags()
	if not saves.last_error.is_empty():
		_toast(saves.last_error)
		return
	var candidate = StoryFlow.new()
	if not candidate.begin(chapter_programs,id,persistent):return
	var position: Dictionary = candidate.snapshot()
	position.flags = entry.get("flags",{}).duplicate(true)
	if not candidate.restore(position):return
	if not history.is_empty() and not current_location.is_empty():
		if _save_current("跳转前自动存档","autosave.json").is_empty():return
	auto_read = false
	auto_button.text = "自动：关"
	choice_visible = false
	_close_modal(false)
	for audio in [voice_player,bgm_player,ambient_player,sound_player]:
		audio.stop()
		audio.stream = null
	last_bgm = ""
	last_ambient = ""
	flow = candidate
	history.clear()
	history_cursor = -1
	current_location = {}
	ending = false
	chrome_hidden = false
	native_visuals.reset()
	_leave_title()
	if story.get("native_presentation",false):native_visuals.restore(entry.native_state)
	_apply_chrome()
	await _advance_flow()


func _full_text() -> void:
	if current_location.is_empty() or on_title:
		return
	body.visible_characters = -1
	_open_modal("当前全文")
	var scroll := _scroll_container()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	modal_box.add_child(scroll)
	var text := RichTextLabel.new()
	text.bbcode_enabled = false
	text.fit_content = true
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.add_theme_font_size_override("normal_font_size", font_size)
	text.text = speaker.text + "\n\n" + body.text
	scroll.add_child(text)
	_button(modal_box, "返回阅读", _close_modal)


func _process(delta: float) -> void:
	if not application_paused:ui_touch.tick(delta)
	if settings_save_delay >= 0:
		settings_save_delay -= delta
		if settings_save_delay <= 0:
			_store_settings()
	if notice_remaining > 0:
		notice_remaining = maxf(0, notice_remaining - delta)
		if notice_remaining == 0:
			notice.text = ""
	if failed or frames.is_empty() or modal.visible or chrome_hidden or application_paused or on_title or presentation_busy:
		return
	elapsed += delta
	var remaining_time := 0.0
	if body.visible_characters >= 0 and body.visible_characters < body.get_total_character_count():
		remaining_time = maxf(0.0, body.get_total_character_count() - reveal_progress) / text_speed
		reveal_progress += delta * text_speed
		body.visible_characters = mini(maxi(body.visible_characters, int(reveal_progress)), body.get_total_character_count())
	if body.visible_characters == -1 or body.visible_characters >= body.get_total_character_count():
		revealed_for += maxf(0.0, delta - remaining_time)
	if auto_read and not chrome_hidden and not ending and not voice_player.playing:
		if revealed_for >= auto_delay:
			_advance()


func _unhandled_key_input(event: InputEvent) -> void:
	if on_title and not modal.visible:
		if event.is_action_pressed("ui_cancel"):
			front.show_title()
		elif event.is_action_pressed("ui_accept") and front.page == "music":
			front._toggle_play()
		return
	if event.is_action_pressed("ui_accept"):
		_advance()
	elif event.is_action_pressed("ui_left") and not modal.visible and not failed:
		_previous()
	elif event.is_action_pressed("ui_cancel") and modal.visible and not choice_visible:
		_close_modal()


func _toggle_auto() -> void:
	auto_read = not auto_read
	auto_button.text = "自动：开" if auto_read else "自动：关"


func _toggle_sound() -> void:
	muted = not muted
	AudioServer.set_bus_mute(0, muted)
	sound_button.text = "声音：关" if muted else "声音：开"
	_queue_settings_save()


func _toast(message: String, duration := 2.5) -> void:
	notice.text = message
	notice_remaining = duration


func _load_slot(id: String) -> bool:
	var data: Dictionary = saves.read(id)
	if story.get("schema") == 2 and (data.get("schema") == 1 or data.get("schema") == 2):
		data = saves.convert_legacy(data, story)
	if not saves.compatible(data, story):
		_toast("存档损坏或与当前资源不匹配。")
		return false
	auto_read = false
	auto_button.text = "自动：关"
	choice_visible = not flow.pending.is_empty()
	_close_modal()
	choice_visible = false
	if data.get("schema") == 3:
		var candidate = StoryFlow.new()
		var persistent_flags: Dictionary = saves.global_flags()
		if not saves.last_error.is_empty():
			_toast(saves.last_error)
			if not on_title and not flow.pending.is_empty():
				_show_choice(flow.pending)
			return false
		if not candidate.begin(chapter_programs, story.entry, persistent_flags) or not candidate.restore(data.flow):
			_toast("存档控制流状态无效。")
			if not on_title and not flow.pending.is_empty():
				_show_choice(flow.pending)
			return false
		if not _validate_history(data.get("history", []), candidate) or not _validate_saved_position(data, candidate):
			_toast("存档阅读历史无效。")
			if not on_title and not flow.pending.is_empty():
				_show_choice(flow.pending)
			return false
		flow = candidate
		choice_visible = false
		history = data.history.duplicate(true)
		history_cursor = history.size() - 1
		current_location = data.presentation.location.duplicate(true)
		frames = _chapter_frames(current_location.chapter)
		var frame := _runtime_frame(current_location.chapter, current_location.id)
		if frame.is_empty():
			_toast("存档对白不存在。")
			return false
		for index in range(frames.size()):
			if frames[index].runtime_id == current_location.id:
				cursor = index
				break
		_leave_title()
		_render_frame(frame)
		if not flow.pending.is_empty():
			_show_choice(flow.pending)
	else:
		_leave_title()
		_show_frame(int(data.cursor))
		if not flow.pending.is_empty():
			_show_choice(flow.pending)
	_toast("已读取存档。")
	return true


func _validate_history(saved_history: Array, candidate) -> bool:
	if saved_history.is_empty():
		return false
	# begin() copies the program. Do that once per load, not once per line.
	var checker = StoryFlow.new()
	if not checker.begin(chapter_programs, story.entry, candidate.global_flags):
		return false
	for entry in saved_history:
		if not entry is Dictionary or not entry.has_all(["location", "flow"]) or not entry.location is Dictionary or not entry.flow is Dictionary:
			return false
		if story.get("native_presentation",false) and not _validate_native_state(entry.get("native_state",{})):
			return false
		var location: Dictionary = entry.location
		if _runtime_frame(str(location.get("chapter", "")), str(location.get("id", ""))).is_empty():
			return false
		if not checker.restore(entry.flow):
			return false
		var code: Array = chapter_programs.get(checker.chapter, [])
		if checker.chapter != location.get("chapter") or checker.pc < 1 or not checker.pending.is_empty():
			return false
		var instruction = code[checker.pc - 1]
		if not instruction is Dictionary or instruction.get("op") != "frame" or instruction.get("id") != location.get("id"):
			return false
	return true


func _validate_native_state(value) -> bool:
	if not value is Dictionary or not value.has_all(["background","color","crop","zoom","characters","tone","music","ambient","font","window"]):
		return false
	for key in ["background","music"]:
		if not value[key] is String or (not value[key].is_empty() and not story.assets.has(value[key]) and value[key] not in story.get("source_absent_assets",[])):
			return false
	for pair in [["color",3],["crop",2],["zoom",4]]:
		if not value[pair[0]] is Array or value[pair[0]].size()!=pair[1]:return false
		for number in value[pair[0]]:
			if not _finite_number(number) or absf(float(number))>1000000:return false
	for color in value.color:
		if color<0 or color>255:return false
	if value.zoom[2]<=0 or value.zoom[3]<=0 or value.tone not in ["","NORMAL","MONOCHROME","NEGATIVE","MONO_NEGATIVE"]:
		return false
	if not _finite_number(value.font) or value.font<0 or value.font>256:return false
	if not _finite_number(value.window) or float(value.window)!=floor(float(value.window)) or int(value.window) not in [0,1]:return false
	if not value.characters is Array or value.characters.size()>5 or not value.ambient is Array:return false
	if value.has("music_paused") and not value.music_paused is bool:return false
	for character in value.characters:
		if not character is Dictionary or not character.has_all(["id","asset","pos","fixed","x","y","priority"]):return false
		if not character.asset is String or (not character.asset.is_empty() and not story.assets.has(character.asset) and character.asset not in story.get("source_absent_assets",[])):return false
		if not character.fixed is bool:return false
		if character.has("animation_frame") and (not _finite_number(character.animation_frame) or character.animation_frame<0 or character.animation_frame>26 or float(character.animation_frame)!=floor(float(character.animation_frame))):return false
		for key in ["id","pos","x","y","priority"]:
			if not _finite_number(character[key]) or absf(float(character[key]))>1000000:return false
	for asset in value.ambient:
		if not asset is String or not story.assets.has(asset):return false
	return true


func _same_flow_position(first: Dictionary, second: Dictionary) -> bool:
	for key in ["chapter", "pc", "flags", "pending"]:
		if first.get(key) != second.get(key):
			return false
	return true


func _validate_saved_position(data: Dictionary, candidate) -> bool:
	var last: Dictionary = data.history.back()
	if last.location != data.presentation.location:
		return false
	if _same_flow_position(last.flow, data.flow):
		return true
	# A displayed frame may also be paused at its following choice or ending.
	var checker = StoryFlow.new()
	if not checker.begin(chapter_programs, story.entry, candidate.global_flags) or not checker.restore(last.flow):
		return false
	var result: Dictionary = checker.advance()
	while result.get("kind") == "presentation":
		result = checker.advance()
	return result.get("kind") in ["choice", "end"] and _same_flow_position(checker.snapshot(), data.flow)


func _save_current(title := "", id := "") -> String:
	var presentation := {"location": current_location.duplicate(true)}
	var active_history: Array = history.slice(0, history_cursor + 1)
	# During a timed effect, autosave the last complete dialogue boundary.
	var saved_flow: Dictionary = active_history.back().flow if presentation_busy and not active_history.is_empty() else flow.snapshot()
	var saved := saves.save_runtime(story, saved_flow, presentation, active_history, title, id)
	if saved.is_empty():
		_toast(saves.last_error)
	return saved


func _preview_text(data: Dictionary) -> String:
	var name := str(data.get("speaker", ""))
	if name == "心の声":
		name = "旁白"
	return (name + "：" if not name.is_empty() else "") + str(data.get("text", "无法读取对白预览。"))


func _save_list(writing: bool) -> void:
	if failed or (writing and current_location.is_empty()):
		return
	if not flow.pending.is_empty():
		choice_visible = false
	save_mode = writing
	_open_modal("保存进度" if writing else "读取进度")
	var header := HBoxContainer.new()
	modal_box.add_child(header)
	_button(header, "最新在前" if newest_first else "最早在前", func(): newest_first = not newest_first; _save_list(writing))
	_button(header, "返回阅读", _close_modal)
	if writing:
		var preview := Label.new()
		preview.text = "当前：" + _preview_text(frames[cursor])
		preview.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		preview.max_lines_visible = 2
		modal_box.add_child(preview)
		var new_row := HBoxContainer.new()
		modal_box.add_child(new_row)
		var title := LineEdit.new()
		title.placeholder_text = "存档名称（可选，默认显示对白）"
		title.max_length = 80
		title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		new_row.add_child(title)
		_button(new_row, "新建存档", func():
			if _save_current(title.text).is_empty():
				return
			else:
				_save_list(true)
				_toast("已新建存档。"))
	var scroll := _scroll_container()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	modal_box.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 16)
	scroll.add_child(list)
	var entries: Array = saves.entries(story, newest_first)
	if entries.is_empty():
		var empty := Label.new()
		empty.text = "暂无存档。" + ("可在上方新建存档。" if writing else "请先保存一份阅读进度。")
		list.add_child(empty)
	for entry in entries:
		var card := PanelContainer.new()
		list.add_child(card)
		var column := VBoxContainer.new()
		card.add_child(column)
		var title_label := Label.new()
		var name := str(entry.get("title", ""))
		if name.is_empty():
			name = "自动存档" if entry.get("automatic", false) else "阅读存档"
		var timestamp := "时间未知"
		if float(entry.get("saved_unix", 0)) > 0:
			timestamp = Time.get_datetime_string_from_unix_time(int(entry.saved_unix) + int(Time.get_time_zone_from_system().bias) * 60).replace("T", " ")
		title_label.text = name + "  ·  " + timestamp
		title_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		column.add_child(title_label)
		var preview := Label.new()
		preview.text = _preview_text(entry)
		preview.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		preview.max_lines_visible = 3
		column.add_child(preview)
		if not entry.compatible:
			var warning := Label.new()
			warning.text = "此存档损坏或属于其他资源版本，无法读取。"
			column.add_child(warning)
		var actions := HBoxContainer.new()
		column.add_child(actions)
		var id: String = entry.id
		var load_button := _button(actions, "读取", func(): _confirm_load(id))
		load_button.disabled = not entry.compatible
		if writing and not entry.get("automatic", false):
			_button(actions, "覆盖", func(): _confirm_overwrite(id))
		var rename_button := _button(actions, "重命名", func(): _rename_slot(id))
		rename_button.disabled = entry.get("schema", 0) == 0
		_button(actions, "删除", func(): _confirm_delete(id))


func _confirm_load(id: String) -> void:
	_open_modal("读取这份存档？")
	_modal_description(_preview_text(saves.read(id)) + "\n尚未保存的当前进度不会自动写入手动存档。")
	_button(modal_box, "确认读取", func(): _load_slot(id))
	_button(modal_box, "取消", func(): _save_list(save_mode))


func _confirm_overwrite(id: String) -> void:
	_open_modal("覆盖这份存档？")
	_modal_description("原存档：" + _preview_text(saves.read(id)) + "\n替换为：" + _preview_text(frames[cursor]))
	_button(modal_box, "确认覆盖", func():
		var title := str(saves.read(id).get("title", ""))
		if _save_current(title, id).is_empty():
			return
		else:
			_save_list(true)
			_toast("已覆盖存档。"))
	_button(modal_box, "取消", func(): _save_list(true))


func _confirm_delete(id: String) -> void:
	_open_modal("删除这份存档？")
	_modal_description(_preview_text(saves.read(id)) + "\n删除后无法恢复。")
	_button(modal_box, "确认删除", func():
		if saves.delete_slot(id):
			_save_list(save_mode)
			_toast("已删除存档。")
		else:
			_toast(saves.last_error))
	_button(modal_box, "取消", func(): _save_list(save_mode))


func _rename_slot(id: String) -> void:
	_open_modal("重命名存档")
	var title := LineEdit.new()
	title.max_length = 80
	title.text = str(saves.read(id).get("title", ""))
	title.placeholder_text = "输入名称；留空使用默认名称"
	modal_box.add_child(title)
	_button(modal_box, "保存名称", func():
		if saves.rename_slot(id, title.text):
			_save_list(save_mode)
			_toast("已修改名称。")
		else:
			_toast(saves.last_error))
	_button(modal_box, "取消", func(): _save_list(save_mode))


func _modal_description(text: String) -> void:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.max_lines_visible = 5
	modal_box.add_child(label)


func _settings() -> void:
	_open_modal("阅读设置")
	var scroll := _scroll_container()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	modal_box.add_child(scroll)
	var options := VBoxContainer.new()
	options.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	options.add_theme_constant_override("separation", 12)
	scroll.add_child(options)
	var preview_panel := PanelContainer.new()
	preferences_panel = preview_panel
	preview_panel.add_theme_stylebox_override("panel", dialogue_style)
	options.add_child(preview_panel)
	preferences_preview = RichTextLabel.new()
	preferences_preview.bbcode_enabled = false
	preferences_preview.fit_content = true
	preferences_preview.text = "预览：轻触补全文字，再次轻触进入下一句。"
	preview_panel.add_child(preferences_preview)
	var mute_toggle := CheckButton.new()
	mute_toggle.text = "静音全部声音"
	mute_toggle.button_pressed = muted
	mute_toggle.toggled.connect(func(value): muted = value; _apply_preferences(); _queue_settings_save())
	options.add_child(mute_toggle)
	var slider_hint := Label.new()
	slider_hint.text = "滑动页面不会改变数值；拖动圆形滑块来调整。"
	slider_hint.add_theme_font_size_override("font_size",18)
	slider_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	options.add_child(slider_hint)
	_setting_slider(options, "背景音乐音量", 0, 1, 0.05, music_volume, func(value): music_volume = value; _apply_preferences())
	_setting_slider(options, "角色语音音量", 0, 1, 0.05, voice_volume, func(value): voice_volume = value; _apply_preferences())
	_setting_slider(options, "音效／环境音量", 0, 1, 0.05, effect_volume, func(value): effect_volume = value; _apply_preferences())
	_display_options(options)
	_color_options(options)
	var progress_toggle := CheckButton.new()
	progress_toggle.text = "显示章节进度"
	progress_toggle.button_pressed = show_progress
	progress_toggle.toggled.connect(func(value): show_progress = value; _apply_chrome(); _store_settings())
	options.add_child(progress_toggle)
	var mode_toggle := CheckButton.new()
	mode_toggle.text = "电子书操作（手机默认开启）"
	mode_toggle.button_pressed = book_mode
	mode_toggle.toggled.connect(func(value): book_mode = value; _update_hint(); _store_settings())
	options.add_child(mode_toggle)
	_setting_slider(options, "字体大小", 24, 46, 1, font_size, func(value): font_size = int(value); _apply_preferences())
	_setting_slider(options, "文字速度（字／秒）", 5, 100, 1, text_speed, func(value): text_speed = value)
	_setting_slider(options, "全文显示后自动等待（秒）", 0.5, 10, 0.5, auto_delay, func(value): auto_delay = value)
	_setting_slider(options, "对话框不透明度", 0, 1, 0.05, dialogue_opacity, func(value): dialogue_opacity = value; _apply_preferences())
	var modes := HBoxContainer.new()
	options.add_child(modes)
	var mode_group := ButtonGroup.new()
	for kind in ["classic","custom"]:
		var option := _button(modes,"经典模式" if kind=="classic" else "自设模式",func():pass,"secondary")
		option.toggle_mode = true
		option.button_group = mode_group
		option.set_meta("dialogue_mode",kind)
		dialogue_mode_buttons.append(option)
		option.toggled.connect(func(selected):
			if selected:
				dialogue_mode = kind
				_apply_preferences()
				_queue_settings_save())
	var color_row := HBoxContainer.new()
	options.add_child(color_row)
	var color_label := Label.new()
	color_label.text = "自设颜色（自设模式下可用）"
	color_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	color_row.add_child(color_label)
	var picker := ColorPickerButton.new()
	dialogue_color_picker = picker
	picker.custom_minimum_size = Vector2(180, 48)
	picker.edit_alpha = false
	picker.color = dialogue_color
	picker.color_changed.connect(func(value): dialogue_color = value; _apply_preferences(); _queue_settings_save())
	color_row.add_child(picker)
	var explanation := Label.new()
	explanation.text = "右侧／向左滑：逐字显示中补全当前句，显示完后进入下一句。\n左侧／向右滑：立即显示上一句。中间区域隐藏或恢复界面。"
	explanation.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	options.add_child(explanation)
	_button(options, "恢复阅读默认值", func():
		font_size = 30; text_speed = 32.0; auto_delay = 3.0
		dialogue_color = Color(0.035, 0.055, 0.08); dialogue_opacity = 0.88
		dialogue_mode = "classic"
		music_volume = 0.8; voice_volume = 1.0; effect_volume = 0.8
		display_mode = "original"
		scene_color_mode = "light"
		_apply_preferences(); _store_settings(); _settings())
	_button(modal_box, "返回标题" if on_title else "返回阅读", func(): _store_settings(); _close_modal())
	_apply_preferences()


func _display_options(parent: Node) -> void:
	var heading := Label.new()
	heading.text = "画面显示"
	parent.add_child(heading)
	var cards := HBoxContainer.new()
	cards.add_theme_constant_override("separation",16)
	parent.add_child(cards)
	var group := ButtonGroup.new()
	for mode in ["original","crop"]:
		var card := Button.new()
		card.name = "DisplayOriginal" if mode=="original" else "DisplayCrop"
		card.toggle_mode = true
		card.button_group = group
		card.set_meta("display_mode",mode)
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card.focus_mode = Control.FOCUS_NONE
		_style_action_button(card,"secondary")
		cards.add_child(card)
		display_mode_buttons.append(card)
		var column := VBoxContainer.new()
		column.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(column)
		column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		column.offset_left = 12; column.offset_right = -12
		column.offset_top = 12; column.offset_bottom = -12
		var caption := Label.new()
		caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
		caption.text = "原始比例" if mode=="original" else "自适应裁剪"
		caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		column.add_child(caption)
		var aspect := AspectRatioContainer.new()
		aspect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		aspect.ratio = size.x/maxf(size.y,1.0)
		card.set_meta("preview_aspect",aspect)
		aspect.custom_minimum_size = Vector2(240,132)
		aspect.size_flags_vertical = Control.SIZE_EXPAND_FILL
		column.add_child(aspect)
		var preview := DisplayPreview.new()
		card.set_meta("preview",preview)
		preview.set_color_mode(scene_color_mode)
		preview.mode = mode
		if native_visuals.visible and not on_title:
			native_visuals.set_preview_active(true)
			preview.scene_texture = native_visuals.viewport.get_texture()
			preview.background_texture = native_visuals.background_viewport.get_texture()
			preview.foreground_texture = native_visuals.foreground_viewport.get_texture()
			preview.effect_texture = native_visuals.effect_viewport.get_texture()
		aspect.add_child(preview)
		var description := Label.new()
		description.mouse_filter = Control.MOUSE_FILTER_IGNORE
		description.text = "完整显示画面，宽屏两侧留边。" if mode=="original" else "只裁剪背景以填满屏幕，立绘大小不变。"
		description.add_theme_font_size_override("font_size",18)
		description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		column.add_child(description)
		card.custom_minimum_size = Vector2(280,240)
		card.toggled.connect(func(selected):
			if selected:
				display_mode = mode
				_apply_preferences()
				_queue_settings_save())
		card.set_pressed_no_signal(display_mode==mode)


func _color_options(parent: Node) -> void:
	var heading := Label.new()
	heading.text = "画面着色"
	parent.add_child(heading)
	var cards := HBoxContainer.new()
	cards.add_theme_constant_override("separation",16)
	parent.add_child(cards)
	var textures := {}
	if native_visuals.visible and not on_title:textures = native_visuals.create_color_previews()
	var group := ButtonGroup.new()
	for kind in ["light","dark"]:
		var card := Button.new()
		card.name = "ColorLight" if kind=="light" else "ColorDark"
		card.toggle_mode = true
		card.button_group = group
		card.focus_mode = Control.FOCUS_NONE
		card.set_meta("color_mode",kind)
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_style_action_button(card,"secondary")
		cards.add_child(card)
		color_mode_buttons.append(card)
		var column := VBoxContainer.new()
		column.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(column)
		column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		column.offset_left = 12;column.offset_right = -12
		column.offset_top = 12;column.offset_bottom = -12
		var caption := Label.new()
		caption.text = "浅色模式" if kind=="light" else "深色模式"
		caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
		caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		column.add_child(caption)
		var aspect := AspectRatioContainer.new()
		aspect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		aspect.ratio = size.x/maxf(size.y,1.0)
		aspect.custom_minimum_size = Vector2(240,132)
		aspect.size_flags_vertical = Control.SIZE_EXPAND_FILL
		column.add_child(aspect)
		card.set_meta("preview_aspect",aspect)
		var preview := DisplayPreview.new()
		preview.mode = display_mode
		preview.set_color_mode(kind)
		if textures.has(kind):
			preview.background_texture = textures[kind].background
			preview.foreground_texture = textures[kind].foreground
		aspect.add_child(preview)
		card.set_meta("preview",preview)
		var description := Label.new()
		description.text = "素材原色，更贴近原作。" if kind=="light" else "旧着色效果，画面更暗、颜色更浓。"
		description.mouse_filter = Control.MOUSE_FILTER_IGNORE
		description.add_theme_font_size_override("font_size",18)
		description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		column.add_child(description)
		card.custom_minimum_size = Vector2(280,240)
		card.toggled.connect(func(selected):
			if selected:
				scene_color_mode = kind
				_apply_preferences()
				_queue_settings_save())
		card.set_pressed_no_signal(scene_color_mode==kind)


func _setting_slider(parent: Node, caption: String, minimum: float, maximum: float, step: float, value: float, changed: Callable) -> void:
	var label := Label.new()
	label.text = caption + "：" + str(snappedf(value, step))
	parent.add_child(label)
	var slider := ThumbSlider.new()
	slider.min_value = minimum
	slider.max_value = maximum
	slider.step = step
	slider.value = value
	slider.custom_minimum_size.y = 36
	parent.add_child(slider)
	slider.value_changed.connect(func(number):
		label.text = caption + "：" + str(snappedf(number, step))
		changed.call(number)
		_queue_settings_save())


func _queue_settings_save() -> void:
	settings_save_delay = 0.35


func _apply_preferences() -> void:
	if not is_instance_valid(body):
		return
	body.add_theme_font_size_override("normal_font_size", font_size)
	_apply_dialogue_style()
	var light_background := dialogue_mode=="custom" and dialogue_color.get_luminance() > 0.6
	body.add_theme_color_override("default_color", Color(0.06, 0.09, 0.12) if light_background else Color(0.96, 0.97, 0.98))
	hint.add_theme_color_override("font_color", Color(0.06, 0.09, 0.12) if light_background else Color(0.8, 0.86, 0.9))
	speaker.add_theme_color_override("font_color", Color(0.04, 0.25, 0.32) if light_background else Color(0.72, 0.9, 0.92))
	if is_instance_valid(preferences_preview):
		preferences_preview.add_theme_font_size_override("normal_font_size", font_size)
		preferences_preview.add_theme_color_override("default_color", body.get_theme_color("default_color"))
	AudioServer.set_bus_mute(0, muted)
	sound_button.text = "声音：关" if muted else "声音：开"
	for entry in [[voice_player, voice_volume, 0.0], [bgm_player, music_volume, -14.0], [ambient_player, effect_volume, -18.0], [sound_player, effect_volume, -10.0]]:
		if is_instance_valid(entry[0]):
			entry[0].volume_db = float(entry[2]) + linear_to_db(maxf(0.0001, float(entry[1])))
	if is_instance_valid(front) and is_instance_valid(front.music):
		front.music.volume_db = -14.0 + linear_to_db(maxf(music_volume, 0.0001))
	if is_instance_valid(native_visuals):
		native_visuals.apply_volumes()
		native_visuals.set_color_mode(scene_color_mode)
		native_visuals.set_display_mode(display_mode)
	if is_instance_valid(image_color_material):image_color_material.set_shader_parameter("dark_mode",scene_color_mode=="dark")
	for option in display_mode_buttons:
		if is_instance_valid(option):
			option.set_pressed_no_signal(option.get_meta("display_mode")==display_mode)
			if is_instance_valid(option.get_meta("preview",null)):option.get_meta("preview").set_color_mode(scene_color_mode)
	for option in color_mode_buttons:
		if is_instance_valid(option):
			option.set_pressed_no_signal(option.get_meta("color_mode")==scene_color_mode)
			option.get_meta("preview").mode = display_mode
			option.get_meta("preview").queue_redraw()
	_layout_safe_area()


func _load_settings() -> void:
	if not FileAccess.file_exists(settings_path):
		return
	var data = JSON.parse_string(FileAccess.get_file_as_string(settings_path))
	if data is Dictionary:
		if data.get("show_progress") is bool:
			show_progress = data.show_progress
		if data.get("book_mode") is bool:
			book_mode = data.book_mode
		if data.get("muted") is bool:
			muted = data.muted
		if data.get("display_mode") in ["original","crop"]:display_mode = data.display_mode
		scene_color_mode = str(data.get("scene_color_mode","light")) if data.get("scene_color_mode","light") in ["light","dark"] else "light"
		if data.get("dialogue_mode") in ["classic","custom"]:dialogue_mode = data.dialogue_mode
		font_size = int(_preference_number(data, "font_size", font_size, 24, 46))
		text_speed = _preference_number(data, "text_speed", text_speed, 5, 100)
		auto_delay = _preference_number(data, "auto_delay", auto_delay, 0.5, 10)
		dialogue_opacity = _preference_number(data, "dialogue_opacity", dialogue_opacity, 0, 1)
		music_volume = _preference_number(data, "music_volume", music_volume, 0, 1)
		voice_volume = _preference_number(data, "voice_volume", voice_volume, 0, 1)
		effect_volume = _preference_number(data, "effect_volume", effect_volume, 0, 1)
		if data.get("dialogue_color") is String and Color.html_is_valid(data.dialogue_color):
			dialogue_color = Color.html(data.dialogue_color)
	_apply_preferences()


func _preference_number(data: Dictionary, key: String, fallback: float, minimum: float, maximum: float) -> float:
	var value = data.get(key, fallback)
	return clampf(float(value), minimum, maximum) if _finite_number(value) else fallback


func _store_settings() -> void:
	settings_save_delay = -1.0
	var file := FileAccess.open(settings_path + ".tmp", FileAccess.WRITE)
	if file == null:
		_toast("无法保存阅读设置。")
		return
	file.store_string(JSON.stringify({"schema": 2, "show_progress": show_progress, "book_mode": book_mode, "muted": muted,
		"font_size": font_size, "text_speed": text_speed, "auto_delay": auto_delay,"scene_color_mode":scene_color_mode,
		"dialogue_color": dialogue_color.to_html(false), "dialogue_opacity": dialogue_opacity,
		"music_volume": music_volume, "voice_volume": voice_volume, "effect_volume": effect_volume, "display_mode":display_mode,"dialogue_mode":dialogue_mode}))
	file.flush()
	var error := file.get_error()
	file.close()
	if error != OK or DirAccess.rename_absolute(ProjectSettings.globalize_path(settings_path + ".tmp"), ProjectSettings.globalize_path(settings_path)) != OK:
		_toast("阅读设置未完整保存，保留原设置。")


func _update_hint() -> void:
	hint.text = "左：上一句  ·  中：隐藏界面  ·  右：补全文字／下一句" if book_mode else "点击补全／继续  ·  空格继续  ·  ← 上一句"


func _apply_chrome() -> void:
	toolbar.visible = not chrome_hidden and not on_title
	dialogue.visible = not chrome_hidden and not on_title
	progress.visible = show_progress and not chrome_hidden and not on_title
	notice.visible = not chrome_hidden


func _previous() -> void:
	if failed or modal.visible or frames.is_empty() or application_paused or on_title or presentation_busy:
		return
	if history_cursor <= 0:
		return
	history_cursor -= 1
	var previous: Dictionary = history[history_cursor]
	if not flow.restore(previous.flow):
		_fail("无法恢复上一句的控制流状态。")
		return
	current_location = previous.location.duplicate(true)
	frames = _chapter_frames(current_location.chapter)
	for index in range(frames.size()):
		if frames[index].runtime_id == current_location.id:
			cursor = index
			break
	_render_frame(_runtime_frame(current_location.chapter, current_location.id))
	if book_mode:
		body.visible_characters = -1


func _reading_gesture(start: Vector2, finish: Vector2, cancelled := false, travel := 0.0) -> void:
	if failed or modal.visible or cancelled or application_paused or on_title:
		return
	var movement := finish - start
	var threshold := maxf(48, size.x * 0.04)
	if book_mode and absf(movement.x) >= threshold and absf(movement.x) > absf(movement.y) * 1.3:
		if movement.x < 0:
			_advance()
		else:
			_previous()
	elif movement.length() <= 20 and travel <= 30:
		if not book_mode:
			_advance()
		elif start.x < size.x / 3:
			_previous()
		elif start.x > size.x * 2 / 3:
			_advance()
		else:
			chrome_hidden = not chrome_hidden
			_apply_chrome()


func _mouse_reading_input(event: InputEvent) -> void:
	# Real touch is handled separately; its emulated mouse must not flip twice.
	if event.device == -1:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			mouse_start = event.position
			mouse_tracking = true
		elif mouse_tracking:
			mouse_tracking = false
			_reading_gesture(mouse_start, event.position)


func _input(event: InputEvent) -> void:
	if application_paused:return
	if ui_touch.handle(self,event):
		get_viewport().set_input_as_handled()
		return
	if on_title:
		return
	if event is InputEventScreenTouch:
		var point: Vector2 = get_global_transform_with_canvas().affine_inverse() * event.position
		if event.pressed:
			touches[event.index] = true
			if touches.size() > 1:
				gesture_cancelled = true
				return
			if modal.visible or (toolbar.visible and toolbar.get_global_rect().has_point(point)):
				return
			touch_index = event.index
			touch_start = point
			touch_travel = 0
			gesture_cancelled = false
			get_viewport().set_input_as_handled()
		else:
			touches.erase(event.index)
			if event.index == touch_index:
				touch_index = -1
				_reading_gesture(touch_start, point, gesture_cancelled or event.canceled, touch_travel)
				get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag and event.index == touch_index:
		touch_travel += (get_global_transform_with_canvas().affine_inverse().basis_xform(event.relative)).length()
		get_viewport().set_input_as_handled()


func _open_modal(title: String) -> void:
	_reset_gestures()
	color_mode_buttons.clear()
	native_visuals.clear_color_previews()
	display_mode_buttons.clear()
	dialogue_mode_buttons.clear()
	native_visuals.set_preview_active(false)
	for child in modal_box.get_children():
		modal_box.remove_child(child)
		child.queue_free()
	var heading := Label.new()
	heading.text = title
	heading.add_theme_font_size_override("font_size", 30)
	modal_box.add_child(heading)
	modal.visible = true
	modal_shade.visible = true
	voice_player.stop()


func _close_modal(resume_choice := true) -> void:
	_reset_gestures()
	color_mode_buttons.clear()
	native_visuals.clear_color_previews()
	if settings_save_delay >= 0:_store_settings()
	display_mode_buttons.clear()
	dialogue_mode_buttons.clear()
	native_visuals.set_preview_active(false)
	modal.visible = false
	modal_shade.visible = false
	if resume_choice and not choice_visible and not flow.pending.is_empty() and not failed and not on_title:
		call_deferred("_resume_choice")


func _resume_choice() -> void:
	# Another action (load/restart/choose) may run before this deferred callback.
	if not modal.visible and not choice_visible and not flow.pending.is_empty() and not failed and not on_title:
		_show_choice(flow.pending)


func _confirm_restart() -> void:
	if failed:
		return
	_open_modal("重新从入口开始阅读？")
	_button(modal_box, "从头阅读", func():
		choice_visible = not flow.pending.is_empty()
		_close_modal()
		if not flow.begin(chapter_programs, story.entry, saves.global_flags()):
			_fail(flow.error)
			return
		choice_visible = false
		history.clear()
		history_cursor = -1
		if story.get("native_presentation",false):native_visuals.reset()
		_advance_flow())
	_button(modal_box, "继续当前进度", _close_modal)


func _history() -> void:
	if failed or frames.is_empty():
		return
	_open_modal("对白回看")
	var scroll := _scroll_container()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	modal_box.add_child(scroll)
	var text := RichTextLabel.new()
	text.bbcode_enabled = false
	text.fit_content = true
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.custom_minimum_size.x = 400
	scroll.add_child(text)
	for index in range(history_cursor + 1):
		var location: Dictionary = history[index].location
		var frame := _runtime_frame(location.chapter, location.id)
		text.add_text("%s\n%s\n\n" % ["旁白" if frame.speaker == "心の声" else frame.speaker, frame.text])
	_button(modal_box, "返回", _close_modal)
	await get_tree().process_frame
	scroll.scroll_vertical = int(scroll.get_v_scroll_bar().max_value)


func _fail(message: String) -> void:
	failed = true
	notice.text = message
	push_error(message)
	if "--smoke-test" in OS.get_cmdline_user_args():
		get_tree().quit(1)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		_reset_gestures()
	elif what == NOTIFICATION_APPLICATION_PAUSED and not application_paused:
		application_paused = true
		_reset_gestures()
		for player in _audio_channels():
			if is_instance_valid(player):
				suspended_audio[player.get_instance_id()] = player.stream_paused
				player.stream_paused = true
		if settings_save_delay >= 0:
			_store_settings()
		if not current_location.is_empty() and not failed and not on_title:
			_save_current("自动存档", "autosave.json")
	elif what == NOTIFICATION_APPLICATION_RESUMED and application_paused:
		application_paused = false
		_reset_gestures()
		for player in _audio_channels():
			if is_instance_valid(player):
				player.stream_paused = suspended_audio.get(player.get_instance_id(), false)
		suspended_audio.clear()
	elif what == NOTIFICATION_WM_CLOSE_REQUEST:
		if settings_save_delay >= 0:
			_store_settings()
		if not current_location.is_empty() and not failed and not on_title:
			_save_current("自动存档", "autosave.json")


func _audio_channels() -> Array:
	var result: Array = [voice_player, bgm_player, ambient_player, sound_player]
	if is_instance_valid(native_visuals):
		for child in native_visuals.get_children():
			if child is AudioStreamPlayer:
				result.append(child)
	if is_instance_valid(front) and is_instance_valid(front.music):
		result.append(front.music)
	return result


func _reset_gestures() -> void:
	ui_touch.reset()
	outside_mouse_tracking = false
	touches.clear()
	touch_index = -1
	touch_travel = 0.0
	gesture_cancelled = true
	mouse_tracking = false


func _smoke_test() -> void:
	# Check every imported frame without playing to a physical audio device.
	for index in range(frames.size()):
		_show_frame(index)
		assert(body.text == frames[index].text)
		assert(bg.texture != null or frames[index].background.is_empty())
		assert(voice_player.stream != null or frames[index].voice.is_empty())
		await get_tree().create_timer(0.02).timeout
	_show_frame(mini(14, frames.size() - 1))
	var expected := cursor
	var first: String = saves.save(story, cursor, "测试存档")
	var second: String = saves.save(story, 3, "另一个存档")
	assert(not first.is_empty() and not second.is_empty() and first != second)
	assert(saves.entries(story).size() == 2)
	assert(saves.read(first).text == frames[cursor].text)
	assert(saves.rename_slot(first, "新的名称"))
	assert(saves.read(first).title == "新的名称")
	assert(saves.save(story, expected, "覆盖后的名称", first) == first)
	_show_frame(0)
	assert(_load_slot(first))
	assert(cursor == expected)
	assert(saves.save(story, 5, "自动存档", "autosave.json") == "autosave.json")
	assert(saves.entries(story).size() == 3)
	assert(not saves.write("../escape.json", {}))
	assert(saves.write("bad.json", {"schema": 1, "cursor": -1}))
	assert(not _load_slot("bad.json"))
	for invalid_cursor in [-1, frames.size(), 1.5]:
		assert(saves.write("bad.json", {"schema": 1, "source_sha256": story.source_sha256,
			"chapter": story.chapter, "cursor": invalid_cursor, "frame_id": 1}))
		assert(not _load_slot("bad.json"))
	assert(cursor == expected)
	assert(saves.delete_slot(second))
	assert(saves.read(second).is_empty())
	# Legacy migration must preserve the original file, without resurrecting deletions.
	var legacy_path: String = saves.directory.path_join("old-slot.fixture")
	var legacy := FileAccess.open(legacy_path, FileAccess.WRITE)
	legacy.store_string(JSON.stringify({"schema": 1, "source_sha256": story.source_sha256,
		"chapter": story.chapter, "cursor": 6, "frame_id": story.frames[6].id}))
	legacy.close()
	saves.migrate_legacy(story, legacy_path)
	assert(saves.read("legacy.json").cursor == 6)
	assert(FileAccess.file_exists(legacy_path))
	assert(saves.delete_slot("legacy.json"))
	saves.migrate_legacy(story, legacy_path)
	assert(saves.read("legacy.json").is_empty())
	_save_list(true)
	await get_tree().process_frame
	assert(modal.visible and modal_shade.visible)
	_confirm_overwrite(first)
	_close_modal()
	_save_list(false)
	_confirm_delete(first)
	_close_modal()
	_settings()
	assert(not progress.visible)
	show_progress = true
	_apply_chrome()
	assert(progress.visible)
	_store_settings()
	show_progress = false
	_load_settings()
	assert(show_progress)
	show_progress = false
	_apply_chrome()
	_close_modal()
	_toast("应当自动消失", 0.1)
	_process(0.2)
	assert(notice.text.is_empty())
	# Bundled font must cover every actual story glyph, including the reported 远.
	assert(READER_FONT.has_char(0x8FDC))
	if story.chapter == "00_z001":
		assert("这么远的路" in frames[5].text)
	for frame in frames:
		for glyph in str(frame.text) + str(frame.speaker):
			if glyph.unicode_at(0) > 32:
				assert(READER_FONT.has_char(glyph.unicode_at(0)), "Missing glyph: " + glyph)
	body.visible_characters = -1
	_advance()
	assert(cursor == mini(expected + 1, frames.size() - 1))
	_show_frame(frames.size() - 1)
	body.visible_characters = -1
	_advance()
	assert(modal.visible and ending)
	_close_modal()
	_history()
	await get_tree().process_frame
	assert(modal.visible)
	_close_modal()
	_show_frame(0)
	_toggle_auto()
	_process(100.0)
	assert(cursor == 1)
	_toggle_auto()
	_toggle_sound()
	assert(AudioServer.is_bus_mute(0))
	_toggle_sound()
	assert(not AudioServer.is_bus_mute(0))
	# Exercise actual touch routing, duplicate emulation, modal guard and cancellation.
	book_mode = true
	_show_frame(10)
	var middle := size * Vector2(0.5, 0.5)
	var right := size * Vector2(0.9, 0.5)
	var left := size * Vector2(0.1, 0.5)
	_test_touch(middle, true)
	_test_touch(middle, false)
	assert(chrome_hidden and not toolbar.visible and not dialogue.visible and not notice.visible)
	_test_touch(middle, true)
	_test_touch(middle, false)
	assert(not chrome_hidden and toolbar.visible and dialogue.visible and not progress.visible)
	_test_touch(right, true)
	_test_touch(right, false)
	assert(cursor == 10 and body.visible_characters == -1)
	_test_touch(right, true)
	_test_touch(right, false)
	assert(cursor == 11)
	_test_touch(left, true)
	_test_touch(left, false)
	assert(cursor == 10)
	_test_touch(right, true)
	_test_touch(left, false)
	assert(cursor == 11)
	_test_touch(left, true)
	_test_touch(right, false)
	assert(cursor == 10)
	_test_touch(right, true)
	_test_touch(right, false, true)
	assert(cursor == 10)
	_open_modal("测试")
	_test_touch(right, true)
	_test_touch(right, false)
	assert(cursor == 10)
	_close_modal()
	_test_touch(right, true)
	_test_touch(left, true, false, 1)
	_test_touch(right, false)
	_test_touch(left, false, false, 1)
	assert(cursor == 10)
	var emulated := InputEventMouseButton.new()
	emulated.device = -1
	emulated.button_index = MOUSE_BUTTON_LEFT
	emulated.position = right
	emulated.pressed = true
	_mouse_reading_input(emulated)
	emulated.pressed = false
	_mouse_reading_input(emulated)
	assert(cursor == 10)
	assert(saves.entries(story).size() == 3)
	for id in DirAccess.get_files_at(saves.directory):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(saves.directory.path_join(id)))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(saves.directory))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(settings_path))
	print("SMOKE_OK: %d frames; multi-save CRUD/migration/isolation; settings; transient notices; font glyphs; touch/swipe/hide/cancel/multitouch; media/history/auto" % frames.size())
	await _stop_audio()
	get_tree().quit(0)


func _test_touch(point: Vector2, pressed: bool, canceled := false, index := 0) -> void:
	var event := InputEventScreenTouch.new()
	event.position = get_global_transform_with_canvas() * point
	event.pressed = pressed
	event.canceled = canceled
	event.index = index
	_input(event)


func _stop_audio() -> void:
	# Let the audio thread register the last playback before stopping and exiting.
	await get_tree().create_timer(0.1).timeout
	for player in _audio_channels():
		player.stop()
		player.stream = null
	await get_tree().create_timer(0.2).timeout


func _capture() -> void:
	var selected := 0
	for index in range(frames.size()):
		if not frames[index].characters.is_empty():
			selected = index
			break
	_show_frame(selected)
	var mode := "reading"
	var captured_saves := true
	if "--capture-title" in OS.get_cmdline_user_args() or "--capture-music" in OS.get_cmdline_user_args() or "--capture-gallery" in OS.get_cmdline_user_args():
		_show_title()
		notice.text = ""
		mode = "v11-title"
		if "--capture-music" in OS.get_cmdline_user_args():
			front.show_music()
			mode = "v11-music"
		elif "--capture-gallery" in OS.get_cmdline_user_args():
			front.show_gallery()
			mode = "v11-gallery"
	elif "--capture-text" in OS.get_cmdline_user_args():
		_show_frame(5)
		mode = "text"
	elif "--capture-saves" in OS.get_cmdline_user_args():
		saves = SaveStore.new("user://capture-saves-%d" % Time.get_ticks_usec())
		captured_saves = true
		saves.save(story, 5, "到站后 · 休息一下")
		saves.save(story, 20, "车站前的对话")
		saves.save(story, 40, "自动存档", "autosave.json")
		_save_list("--capture-writing" in OS.get_cmdline_user_args())
		mode = "save-form" if "--capture-writing" in OS.get_cmdline_user_args() else "saves"
	elif "--capture-settings" in OS.get_cmdline_user_args():
		book_mode = true
		_settings()
		mode = "settings"
	elif "--capture-hidden" in OS.get_cmdline_user_args():
		chrome_hidden = true
		_apply_chrome()
		mode = "hidden"
	body.visible_characters = -1
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var output := ProjectSettings.globalize_path("res://../reports/preview-%s.png" % mode)
	get_viewport().get_texture().get_image().save_png(output)
	print("CAPTURE_OK: " + output)
	if captured_saves and DirAccess.dir_exists_absolute(saves.directory):
		for id in DirAccess.get_files_at(saves.directory):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(saves.directory.path_join(id)))
		DirAccess.remove_absolute(ProjectSettings.globalize_path(saves.directory))
	if FileAccess.file_exists(settings_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(settings_path))
	await _stop_audio()
	get_tree().quit(0)
