# SPDX-License-Identifier: GPL-2.0-only
extends Control
## Content-independent title and music UI. The gallery is deliberately limited
## to backgrounds referenced by the verified, non-explicit opening fixture.

var host
var music: AudioStreamPlayer
var panel: PanelContainer
var box: VBoxContainer
var backdrop: TextureRect
var tracks: Array[String] = []
var track_paths: Dictionary = {}
var pictures: Array[String] = []
var picture_paths: Dictionary = {}
var track_index := -1
var picture_index := 0
var repeat_mode := 1 # 0: stop, 1: all, 2: one
var shuffle := false
var seek_dragging := false
var seek_slider: HSlider
var track_label: Label
var time_label: Label
var play_button: Button
var page := "title"
var picture_zoom := false
var layout_margin := Vector2(32, 24)
var shade: ColorRect
var title_root: Control
var title_logo: Panel
var title_name: Label
var title_caption: Label
var title_version: Label
var title_buttons: Array[Button] = []
const TITLE_SKY = "res://ui/title-sky-v1.png"
const TITLE_TEAL = Color("#246475")


func setup(owner_player) -> void:
	host = owner_player
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	gui_input.connect(func(event):
		if page!="title" and not host.modal.visible:host._outside_panel_input(event,panel,self,show_title))
	backdrop = TextureRect.new()
	backdrop.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	backdrop.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(backdrop)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade = ColorRect.new()
	shade.color = Color(0.015, 0.035, 0.06, 0.72)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel = PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.025, 0.045, 0.065, 0.9)
	style.set_corner_radius_all(18)
	style.set_content_margin_all(24)
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)
	panel.minimum_size_changed.connect(func(): call_deferred("layout", layout_margin))
	box = VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	panel.add_child(box)
	title_root = Control.new()
	title_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(title_root)
	title_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	title_root.hide()
	music = AudioStreamPlayer.new()
	add_child(music)
	music.finished.connect(_track_finished)
	layout(Vector2(32, 24))


func configure(story: Dictionary) -> void:
	tracks.clear()
	track_paths.clear()
	pictures.clear()
	picture_paths.clear()
	# Only background-music assets, never voice or environmental recordings.
	for key in story.get("assets", {}):
		var path = story.assets[key]
		if key is String and key.to_lower().begins_with("bgm") and path is String and path.get_extension().to_lower() in ["ogg", "wav"]:
			_register_track(key, "res://content/" + path)
	var sample_path := "res://content/sample.json"
	if FileAccess.file_exists(sample_path):
		var sample = JSON.parse_string(FileAccess.get_file_as_string(sample_path))
		if sample is Dictionary and sample.get("schema") == 1 and sample.get("frames") is Array and sample.get("assets") is Dictionary:
			for frame in sample.frames:
				if not frame is Dictionary:
					continue
				var bg_name := str(frame.get("background", ""))
				if not bg_name.is_empty() and sample.assets.has(bg_name) and not picture_paths.has(bg_name):
					var path := "res://content/" + str(sample.assets[bg_name])
					if path.get_extension().to_lower() == "png" and ResourceLoader.exists(path):
						pictures.append(bg_name)
						picture_paths[bg_name] = path
				var bgm_name := str(frame.get("bgm", ""))
				if bgm_name.to_lower().begins_with("bgm") and sample.assets.has(bgm_name) and not track_paths.has(bgm_name):
					_register_track(bgm_name, "res://content/" + str(sample.assets[bgm_name]))
	tracks.sort()
	if ResourceLoader.exists(TITLE_SKY):
		backdrop.texture = load(TITLE_SKY) as Texture2D
	elif not pictures.is_empty():
		backdrop.texture = load(picture_paths[pictures[0]]) as Texture2D
	else:
		backdrop.texture = null
	track_index = -1


func _register_track(key: String, path: String) -> void:
	if not track_paths.has(key) and ResourceLoader.exists(path):
		tracks.append(key)
		track_paths[key] = path


func layout(margin: Vector2) -> void:
	layout_margin = margin
	panel.position = margin
	panel.size = size - margin * 2
	if is_instance_valid(title_name):
		_layout_title()


func _clear(new_page: String) -> void:
	host._reset_gestures()
	page = new_page
	title_root.visible = page == "title"
	panel.visible = page != "title"
	shade.visible = page != "title"
	seek_slider = null
	track_label = null
	time_label = null
	play_button = null
	seek_dragging = false
	for child in box.get_children():
		box.remove_child(child)
		child.queue_free()
	call_deferred("layout", layout_margin)


func _label(parent: Node, text: String, font_size := 24) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(label)
	return label


func show_title() -> void:
	show()
	_clear("title")
	for child in title_root.get_children():
		title_root.remove_child(child)
		child.queue_free()
	title_buttons.clear()
	title_logo = Panel.new()
	title_logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var logo_style := StyleBoxFlat.new()
	logo_style.bg_color = Color(0.13, 0.40, 0.47, 0.87)
	logo_style.border_color = Color(0.84, 0.96, 0.97, 0.9)
	logo_style.set_border_width_all(2)
	logo_style.set_corner_radius_all(9)
	title_logo.add_theme_stylebox_override("panel", logo_style)
	title_root.add_child(title_logo)
	title_name = _title_label(title_root, "ヨ ス ガ ノ ソ ラ", 54)
	title_name.add_theme_color_override("font_color", Color("#397a89"))
	title_name.add_theme_constant_override("outline_size", 6)
	title_caption = _title_label(title_root, "In solitude, where we are least alone.", 22)
	title_caption.add_theme_color_override("font_color", TITLE_TEAL)
	title_caption.add_theme_constant_override("outline_size", 5)
	title_version = _title_label(title_root, "缘之空  ·  Ver. 1.1.0", 17)
	title_version.add_theme_color_override("font_color", TITLE_TEAL)
	title_version.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_title_button("重新开始", "Start", host._new_from_title)
	var continue_button := _title_button("继续阅读", "Continue", host._continue_from_title)
	continue_button.disabled = not host._has_continue()
	continue_button.modulate.a = 0.42 if continue_button.disabled else 1.0
	_title_button("读取存档", "Load", func(): host._save_list(false))
	_title_button("章节目录", "Chapters", host._chapter_directory)
	_title_button("音乐室", "Music room", show_music)
	_title_button("美术室", "Art gallery", show_gallery)
	_title_button("设置", "Config", host._settings)
	_layout_title()
	if not tracks.is_empty() and (music.stream == null or (not music.playing and not music.stream_paused)):
		play_track(maxi(0, track_index))


func _title_label(parent: Node, text: String, font_size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", Color.WHITE)
	label.add_theme_color_override("font_outline_color", Color(0.96, 1.0, 1.0))
	label.add_theme_constant_override("outline_size", 4)
	parent.add_child(label)
	return label


func _title_button(caption: String, english: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = caption
	button.tooltip_text = caption
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		button.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_disabled_color", "font_hover_pressed_color"]:
		button.add_theme_color_override(state, Color.TRANSPARENT)
	title_root.add_child(button)
	var strip := Panel.new()
	strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = TITLE_TEAL
	style.set_corner_radius_all(4)
	strip.add_theme_stylebox_override("panel", style)
	button.add_child(strip)
	var main := _title_label(button, caption, 30)
	main.add_theme_color_override("font_color", TITLE_TEAL)
	var secondary := _title_label(button, english, 15)
	secondary.add_theme_constant_override("outline_size", 0)
	button.set_meta("strip", strip)
	button.set_meta("main", main)
	button.set_meta("secondary", secondary)
	button.pressed.connect(action)
	var highlight := func(active: bool):
		style.bg_color = Color("#3d8999") if active else TITLE_TEAL
		main.add_theme_color_override("font_color", Color("#3d8999") if active else TITLE_TEAL)
	button.mouse_entered.connect(func(): highlight.call(true))
	button.mouse_exited.connect(func(): highlight.call(button.has_focus()))
	button.focus_entered.connect(func(): highlight.call(true))
	button.focus_exited.connect(func(): highlight.call(false))
	title_buttons.append(button)
	return button


func _layout_title() -> void:
	var scale_factor := clampf(minf(size.x / 1280.0, size.y / 720.0), 0.65, 1.5)
	var left := layout_margin.x + 28 * scale_factor
	var top := layout_margin.y + 40 * scale_factor
	title_logo.position = Vector2(left, top)
	title_logo.size = Vector2(550, 78) * scale_factor
	title_name.position = title_logo.position + Vector2(8, -3) * scale_factor
	title_name.size = Vector2(534, 88) * scale_factor
	title_name.add_theme_font_size_override("font_size", int(52 * scale_factor))
	title_caption.position = title_logo.position + Vector2(0, 82) * scale_factor
	title_caption.size = Vector2(550, 42) * scale_factor
	title_caption.add_theme_font_size_override("font_size", int(22 * scale_factor))
	var button_size := Vector2(306, 60) * scale_factor
	var first_x := size.x - layout_margin.x - button_size.x - 58 * scale_factor
	var first_y := maxf(size.y * 0.30, top + 150 * scale_factor)
	var step_y := minf(68 * scale_factor, (size.y - layout_margin.y - 54 * scale_factor - first_y - button_size.y) / maxf(title_buttons.size()-1,1))
	for index in range(title_buttons.size()):
		var button := title_buttons[index]
		button.position = Vector2(first_x - index * 26 * scale_factor, first_y + index * step_y)
		button.size = button_size
		var strip: Panel = button.get_meta("strip")
		strip.position = Vector2(0, 31) * scale_factor
		strip.size = Vector2(button_size.x, 25 * scale_factor)
		var main: Label = button.get_meta("main")
		main.position = Vector2(0, -2) * scale_factor
		main.size = Vector2(button_size.x, 40 * scale_factor)
		main.add_theme_font_size_override("font_size", int(30 * scale_factor))
		var secondary: Label = button.get_meta("secondary")
		secondary.position = Vector2(0, 35) * scale_factor
		secondary.size = Vector2(button_size.x, 20 * scale_factor)
		secondary.add_theme_font_size_override("font_size", int(15 * scale_factor))
	title_version.position = Vector2(size.x - layout_margin.x - 280 * scale_factor, size.y - layout_margin.y - 30 * scale_factor)
	title_version.size = Vector2(280, 30) * scale_factor
	title_version.add_theme_font_size_override("font_size", int(17 * scale_factor))


func deactivate() -> void:
	hide()
	music.stop()
	music.stream = null


func play_track(index: int) -> void:
	if tracks.is_empty():
		return
	track_index = posmod(index, tracks.size())
	music.stop()
	# Repeat is controlled by finished(), allowing both one-track and list modes.
	var stream = load(track_paths[tracks[track_index]])
	if stream is AudioStreamWAV:
		stream = stream.duplicate()
		stream.loop_mode = AudioStreamWAV.LOOP_DISABLED
	elif stream is AudioStreamOggVorbis:
		stream = stream.duplicate()
		stream.loop = false
	music.stream = stream
	music.play()
	music.stream_paused = host.application_paused
	_update_music()


func _next_track(direction := 1) -> void:
	if shuffle and direction > 0 and tracks.size() > 1:
		play_track(track_index + randi_range(1, tracks.size() - 1))
	else:
		play_track(track_index + direction)


func _track_finished() -> void:
	if not visible or host.application_paused:
		return
	if page == "title" or repeat_mode == 2:
		play_track(track_index)
	elif repeat_mode == 1:
		_next_track()
	_update_music()


func _toggle_play() -> void:
	if music.stream == null:
		play_track(0)
	elif not music.playing:
		music.play()
	else:
		music.stream_paused = not music.stream_paused
	_update_music()


func show_music() -> void:
	_clear("music")
	_label(box, "音乐室", 32)
	track_label = _label(box, "请选择音乐")
	var controls := HBoxContainer.new()
	box.add_child(controls)
	host._button(controls, "上一首", _next_track.bind(-1))
	play_button = host._button(controls, "播放", _toggle_play)
	host._button(controls, "下一首", _next_track)
	var repeat := OptionButton.new()
	for text in ["播放完停止", "列表循环", "单曲循环"]:
		repeat.add_item(text)
	repeat.select(repeat_mode)
	repeat.item_selected.connect(func(index): repeat_mode = index)
	controls.add_child(repeat)
	var random_toggle := CheckButton.new()
	random_toggle.text = "随机"
	random_toggle.button_pressed = shuffle
	random_toggle.toggled.connect(func(value): shuffle = value)
	controls.add_child(random_toggle)
	var mute_toggle := CheckButton.new()
	mute_toggle.text = "静音"
	mute_toggle.button_pressed = host.muted
	mute_toggle.toggled.connect(func(value): host.muted = value; host._apply_preferences(); host._queue_settings_save())
	controls.add_child(mute_toggle)
	seek_slider = HSlider.new()
	seek_slider.step = 0.1
	seek_slider.custom_minimum_size.y = 32
	seek_slider.drag_started.connect(func(): seek_dragging = true)
	seek_slider.drag_ended.connect(func(_changed): seek_dragging = false; _seek_to(seek_slider.value))
	box.add_child(seek_slider)
	time_label = _label(box, "00:00 / 00:00", 18)
	var volume := HSlider.new()
	volume.min_value = 0
	volume.max_value = 1
	volume.step = 0.01
	volume.value = host.music_volume
	volume.custom_minimum_size.y = 28
	volume.value_changed.connect(func(value): host.music_volume = value; host._apply_preferences(); host._queue_settings_save())
	_label(box, "音乐音量", 18)
	box.add_child(volume)
	var scroll: ScrollContainer = host._scroll_container()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	for index in range(tracks.size()):
		host._button(list, "%02d · %s" % [index + 1, tracks[index]], play_track.bind(index))
	if tracks.is_empty():
		_label(list, "没有可播放的背景音乐。")
	for control in controls.get_children():
		if control is Button:
			control.disabled = tracks.is_empty()
	host._button(box, "返回标题", show_title)
	_update_music()


func _seek_to(seconds: float) -> void:
	if music.stream == null:
		return
	var target := clampf(seconds, 0.0, maxf(0, music.stream.get_length() - 0.05))
	if not music.playing:
		music.play(target)
	else:
		music.seek(target)


func _clock(seconds: float) -> String:
	return "%02d:%02d" % [int(seconds) / 60, int(seconds) % 60]


func _update_music() -> void:
	if is_instance_valid(track_label):
		track_label.text = "正在播放：" + tracks[track_index] if track_index >= 0 else "请选择音乐"
	if is_instance_valid(play_button):
		play_button.text = "暂停" if music.playing and not music.stream_paused else "播放"
	if is_instance_valid(seek_slider):
		var length := music.stream.get_length() if music.stream != null else 0.0
		seek_slider.max_value = maxf(length, 0.1)
		seek_slider.editable = length > 0
		if not seek_dragging:
			seek_slider.set_value_no_signal(music.get_playback_position())
		if is_instance_valid(time_label):
			time_label.text = _clock(music.get_playback_position()) + " / " + _clock(length)


func _process(_delta: float) -> void:
	if visible and page == "music" and not host.application_paused:
		_update_music()


func show_gallery() -> void:
	_clear("gallery")
	_label(box, "美术室 · 背景图", 32)
	_label(box, "当前收录已验证的序章背景。", 18)
	var scroll: ScrollContainer = host._scroll_container()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	for index in range(pictures.size()):
		var row := HBoxContainer.new()
		list.add_child(row)
		var thumbnail := TextureButton.new()
		thumbnail.texture_normal = load(picture_paths[pictures[index]]) as Texture2D
		thumbnail.ignore_texture_size = true
		thumbnail.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
		thumbnail.custom_minimum_size = Vector2(200, 110)
		thumbnail.pressed.connect(show_picture.bind(index))
		row.add_child(thumbnail)
		host._button(row, "查看 · " + pictures[index], show_picture.bind(index))
	if pictures.is_empty():
		_label(list, "没有已收录的背景图。")
	host._button(box, "返回标题", show_title)


func show_picture(index: int) -> void:
	if pictures.is_empty():
		return
	picture_index = posmod(index, pictures.size())
	_clear("picture")
	_label(box, "%s · %d / %d" % [pictures[picture_index], picture_index + 1, pictures.size()], 24)
	var scroll: ScrollContainer = host._scroll_container()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(scroll)
	var picture := TextureRect.new()
	picture.texture = load(picture_paths[pictures[picture_index]]) as Texture2D
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	picture.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	picture.size_flags_vertical = Control.SIZE_EXPAND_FILL
	picture.custom_minimum_size = panel.size * Vector2(0.85, 0.65) * (2.0 if picture_zoom else 1.0)
	scroll.add_child(picture)
	var actions := HBoxContainer.new()
	box.add_child(actions)
	host._button(actions, "上一张", func(): show_picture(picture_index - 1))
	host._button(actions, "下一张", func(): show_picture(picture_index + 1))
	host._button(actions, "适应屏幕" if picture_zoom else "放大查看", func(): picture_zoom = not picture_zoom; show_picture(picture_index))
	host._button(actions, "返回列表", show_gallery)
