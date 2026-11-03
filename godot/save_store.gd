# SPDX-License-Identifier: GPL-2.0-only
extends RefCounted

const StoryFlow = preload("res://story_flow.gd")

var directory := "user://saves"
var last_error := ""


func _init(path := "user://saves") -> void:
	directory = path


func _path(id: String) -> String:
	if id.is_empty() or id.get_file() != id or not id.ends_with(".json") or id.contains("..") or id.contains("\\"):
		return ""
	return directory.path_join(id)


func compatible(data: Dictionary, story: Dictionary) -> bool:
	if data.get("schema") == 3:
		if data.get("source_sha256") != story.get("source_sha256") or not data.get("flow") is Dictionary or not data.get("presentation") is Dictionary or not data.get("history") is Array:
			return false
		var location_data = data.presentation.get("location", {})
		if not location_data is Dictionary:
			return false
		var location: Dictionary = location_data
		var chapters: Dictionary = story.get("chapters", {})
		if not location.get("chapter") is String or not chapters.has(location.chapter):
			return false
		if not chapters[location.chapter] is Dictionary or data.history.is_empty():
			return false
		var last_entry = data.history.back()
		if not last_entry is Dictionary or last_entry.get("location") != location:
			return false
		var chapter: Dictionary = chapters[location.chapter]
		if not chapter.get("dialogue") is Dictionary:
			return false
		var dialogue: Dictionary = chapter.get("dialogue", {})
		return location.get("id") is String and dialogue.has(location.id)
	if story.get("schema") == 2:
		return not _convert_legacy_data(data, story).is_empty()
	if story.get("schema") != 1 or not story.get("frames") is Array or (data.get("schema") != 1 and data.get("schema") != 2) or data.get("source_sha256") != story.get("source_sha256") or data.get("chapter") != story.get("chapter"):
		return false
	var position = data.get("cursor", -1)
	if not (position is int or position is float) or float(position) != floor(float(position)) or position < 0 or position >= story.frames.size():
		return false
	return data.get("frame_id") == story.frames[int(position)].id


func save_runtime(story: Dictionary, flow_state: Dictionary, presentation: Dictionary,
		history: Array, title := "", id := "") -> String:
	last_error = ""
	var location_value = presentation.get("location", {})
	if flow_state.is_empty() or not location_value is Dictionary or location_value.is_empty() or history.is_empty():
		last_error = "剧情位置无效。"
		return ""
	var last_history = history.back()
	if not last_history is Dictionary or last_history.get("location", {}) != location_value:
		last_error = "阅读历史与当前对白不一致。"
		return ""
	if id.is_empty():
		id = "slot-%d-%d.json" % [int(Time.get_unix_time_from_system() * 1000), Time.get_ticks_usec()]
	var location: Dictionary = presentation.location
	var chapter: Dictionary = story.chapters.get(location.get("chapter", ""), {})
	var dialogue: Dictionary = chapter.get("dialogue", {})
	if not dialogue.has(location.get("id", "")):
		last_error = "存档对白不存在。"
		return ""
	var line: Dictionary = dialogue[location.id]
	var data := {"schema": 3, "source_sha256": story.source_sha256,
		"flow": flow_state.duplicate(true), "presentation": presentation.duplicate(true),
		"history": history.duplicate(true), "title": title.strip_edges().left(80),
		"speaker": line.get("speaker", ""), "text": line.get("text", ""),
		"saved_unix": Time.get_unix_time_from_system(), "automatic": id == "autosave.json"}
	return id if write(id, data) else ""


func global_flags() -> Dictionary:
	last_error = ""
	var path := _path("global-unlocks.json")
	if FileAccess.file_exists(path):
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
		if not parsed is Dictionary or parsed.get("schema") != 1 or not parsed.get("flags") is Dictionary:
			last_error = "通关解锁数据损坏。"
			return {}
		for id in parsed.flags:
			if not id is String or not parsed.flags[id] is bool:
				last_error = "通关解锁数据格式错误。"
				return {}
		return parsed.flags.duplicate(true)
	return {}


func merge_global_flags(flags: Dictionary) -> bool:
	var merged := global_flags()
	if not last_error.is_empty():
		return false
	var changed := false
	for id in flags:
		if id is String and flags[id] is bool and flags[id]:
			changed = changed or not merged.get(id, false)
			merged[id] = true
	if not changed:
		return true
	var data := {"schema": 1, "flags": merged}
	if not write("global-unlocks.json", data):
		return false
	return true


func read(id: String) -> Dictionary:
	var path := _path(id)
	if path.is_empty() or not FileAccess.file_exists(path):
		return {}
	var data = JSON.parse_string(FileAccess.get_file_as_string(path))
	return data if data is Dictionary else {}


func write(id: String, data: Dictionary) -> bool:
	last_error = ""
	var path := _path(id)
	if path.is_empty():
		last_error = "存档名称无效。"
		return false
	var error := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	if error != OK:
		last_error = "无法创建存档目录。"
		return false
	var file := FileAccess.open(path + ".tmp", FileAccess.WRITE)
	if file == null:
		last_error = "无法写入存档。"
		return false
	file.store_string(JSON.stringify(data))
	file.flush()
	var write_error := file.get_error()
	file.close()
	if write_error != OK:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path + ".tmp"))
		last_error = "存档未完整写入，已保留原存档。"
		return false
	error = DirAccess.rename_absolute(ProjectSettings.globalize_path(path + ".tmp"), ProjectSettings.globalize_path(path))
	if error != OK:
		last_error = "无法替换存档文件。"
		return false
	return true


func save(story: Dictionary, position: int, title := "", id := "") -> String:
	if position < 0 or position >= story.frames.size():
		last_error = "剧情位置无效。"
		return ""
	if id.is_empty():
		id = "slot-%d-%d.json" % [int(Time.get_unix_time_from_system() * 1000), Time.get_ticks_usec()]
	var frame: Dictionary = story.frames[position]
	var data := {"schema": 2, "source_sha256": story.source_sha256,
		"chapter": story.chapter, "cursor": position, "frame_id": frame.id,
		"title": title.strip_edges().left(80), "speaker": frame.speaker,
		"text": frame.text, "saved_unix": Time.get_unix_time_from_system(),
		"automatic": id == "autosave.json"}
	return id if write(id, data) else ""


func entries(story: Dictionary, newest_first := true) -> Array:
	var result: Array = []
	if not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(directory)):
		return result
	for id in DirAccess.get_files_at(directory):
		if not id.ends_with(".json") or id == "global-unlocks.json":
			continue
		var data := read(id)
		data["id"] = id
		data["compatible"] = compatible(data, story)
		result.append(data)
	result.sort_custom(func(a, b):
		var first := float(a.get("saved_unix", 0))
		var second := float(b.get("saved_unix", 0))
		if first == second:
			return str(a.id) > str(b.id) if newest_first else str(a.id) < str(b.id)
		return first > second if newest_first else first < second)
	return result


func rename_slot(id: String, title: String) -> bool:
	var data := read(id)
	if data.is_empty():
		last_error = "无法重命名损坏或不存在的存档。"
		return false
	data["title"] = title.strip_edges().left(80)
	return write(id, data)


func delete_slot(id: String) -> bool:
	var path := _path(id)
	if path.is_empty():
		last_error = "存档名称无效。"
		return false
	if DirAccess.remove_absolute(ProjectSettings.globalize_path(path)) != OK:
		last_error = "删除存档失败。"
		return false
	return true


func _legacy_location(data: Dictionary, story: Dictionary) -> Dictionary:
	if data.get("schema") != 1 and data.get("schema") != 2:
		return {}
	var cursor = data.get("cursor", -1)
	var frame_id = data.get("frame_id", -1)
	if not (cursor is int or cursor is float) or not (frame_id is int or frame_id is float):
		return {}
	if not is_finite(float(cursor)) or floor(float(cursor)) != float(cursor):
		return {}
	if not is_finite(float(frame_id)) or floor(float(frame_id)) != float(frame_id):
		return {}
	if cursor < 0 or cursor > 1000000 or frame_id < 1 or frame_id > 1000000:
		return {}
	for migration in story.get("legacy_migrations", []):
		if not migration is Dictionary or migration.get("source_sha256") != data.get("source_sha256"):
			continue
		if migration.get("chapter") != data.get("chapter") or not migration.get("frame_map") is Dictionary:
			continue
		var mapped_frame = migration.frame_map.get(str(int(frame_id)), {})
		if not mapped_frame is Dictionary:
			return {}
		var old_frame: Dictionary = mapped_frame
		var mapped_cursor = old_frame.get("cursor", -1)
		if not (mapped_cursor is int or mapped_cursor is float) or not is_finite(float(mapped_cursor)) or float(mapped_cursor) != float(cursor):
			return {}
		if old_frame.is_empty():
			return {}
		if old_frame.get("speaker") != data.get("speaker", "") or old_frame.get("text") != data.get("text", ""):
			return {}
		var target_chapter := str(migration.chapter)
		var target_id := str(old_frame.get("id", ""))
		var chapter_data: Dictionary = story.get("chapters", {}).get(target_chapter, {})
		if target_id.is_empty() or not chapter_data.get("dialogue", {}).has(target_id):
			return {}
		return {"chapter": target_chapter, "id": target_id}
	return {}


func _flow_at_location(story: Dictionary, location: Dictionary) -> Dictionary:
	var programs := {}
	for chapter_id in story.get("chapters", {}):
		var chapter: Dictionary = story.chapters[chapter_id]
		if not chapter.get("program") is Array:
			return {}
		programs[chapter_id] = chapter.program
	var persistent: Dictionary = global_flags()
	if not last_error.is_empty():
		return {}
	var candidate = StoryFlow.new()
	var start_chapter := str(location.get("chapter", ""))
	if not programs.has(start_chapter):
		return {}
	# The old format contains no route flags. Reject conditional prefixes even
	# when today's flags happen to lead to the mapped dialogue.
	var code: Array = programs[start_chapter]
	var target_found := false
	for instruction in code:
		if not instruction is Dictionary or instruction.get("op", "") not in ["frame", "flag", "global_flag"]:
			return {}
		if instruction.get("op") == "frame" and instruction.get("id") == location.get("id"):
			target_found = true
			break
	if not target_found:
		return {}
	if not candidate.begin(programs, start_chapter, persistent):
		return {}
	for _step in range(100000):
		var result: Dictionary = candidate.advance()
		match result.get("kind", ""):
			"frame":
				if result.get("chapter") == location.get("chapter") and result.get("id") == location.get("id"):
					return candidate.snapshot()
			"choice":
				break
			"end", "error":
				break
	return {}


func convert_legacy(data: Dictionary, story: Dictionary) -> Dictionary:
	# Used for old slots copied into the directory after startup. Conversion is
	# in memory; only the explicit migration pass writes upgraded files.
	return _convert_legacy_data(data, story)


func _convert_legacy_data(data: Dictionary, story: Dictionary) -> Dictionary:
	var location := _legacy_location(data, story)
	if location.is_empty():
		return {}
	var flow_state := _flow_at_location(story, location)
	if flow_state.is_empty():
		return {}
	var chapter: Dictionary = story.chapters[location.chapter]
	var line: Dictionary = chapter.dialogue[location.id]
	var history := [{"location": location.duplicate(true), "flow": flow_state.duplicate(true)}]
	var converted := data.duplicate(true)
	converted["schema"] = 3
	converted["source_sha256"] = story.get("source_sha256", "")
	converted["flow"] = flow_state
	converted["presentation"] = {"location": location}
	converted["history"] = history
	converted["speaker"] = line.get("speaker", "")
	converted["text"] = line.get("text", "")
	return converted


func migrate_legacy(story: Dictionary, path := "user://reading-save.json") -> void:
	last_error = ""
	if story.get("schema") == 2:
		if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(directory)):
			for id in DirAccess.get_files_at(directory):
				if not id.ends_with(".json") or id == "global-unlocks.json":
					continue
				var existing := read(id)
				if existing.get("schema") != 1 and existing.get("schema") != 2:
					continue
				var converted := _convert_legacy_data(existing, story)
				if not converted.is_empty():
					var backup = get_script().new(directory.path_join("legacy-backups"))
					if not FileAccess.file_exists(backup._path(id)) and not backup.write(id, existing):
						last_error = "无法备份旧版存档，已取消迁移：" + backup.last_error
						return
					if not write(id, converted):
						return
		if FileAccess.file_exists(directory.path_join("legacy-imported.marker")) or not FileAccess.file_exists(path):
			return
		var old_chapter_save = JSON.parse_string(FileAccess.get_file_as_string(path))
		if not old_chapter_save is Dictionary:
			return
		var converted_save := _convert_legacy_data(old_chapter_save, story)
		if converted_save.is_empty():
			return
		if read("legacy.json").is_empty() and not write("legacy.json", converted_save):
			return
		var chapter_marker := FileAccess.open(directory.path_join("legacy-imported.marker"), FileAccess.WRITE)
		if chapter_marker == null:
			last_error = "无法标记旧版存档迁移状态。"
			return
		chapter_marker.store_string("imported")
		return
	# Preserve the original single-slot save and only copy it once.
	if story.get("schema") != 1 or FileAccess.file_exists(directory.path_join("legacy-imported.marker")) or not FileAccess.file_exists(path):
		return
	var old = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not old is Dictionary or not compatible(old, story):
		return
	if read("legacy.json").is_empty() and save(story, int(old.cursor), "旧版存档", "legacy.json").is_empty():
		return
	var marker := FileAccess.open(directory.path_join("legacy-imported.marker"), FileAccess.WRITE)
	if marker != null:
		marker.store_string("imported")
