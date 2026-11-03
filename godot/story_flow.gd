# SPDX-License-Identifier: GPL-2.0-only
extends RefCounted
## Content-independent chapter control flow. Presentation belongs to the player.
## The caller persists snapshot() together with the displayed frame and history.

var chapters: Dictionary = {}
var chapter := ""
var pc := 0
var flags: Dictionary = {}
var global_flags: Dictionary = {}
var pending: Array = []
var error := ""


func begin(program: Dictionary, entry: String, persistent: Dictionary = {}) -> bool:
	if not program.has(entry) or not program[entry] is Array:
		error = "Invalid entry chapter"
		return false
	chapters = program.duplicate(true)
	chapter = entry
	pc = 0
	flags = {}
	global_flags = persistent.duplicate(true)
	pending = []
	error = ""
	return true


func advance() -> Dictionary:
	if not error.is_empty():
		return {"kind": "error", "message": error}
	if not pending.is_empty():
		return {"kind": "choice", "options": pending.duplicate(true)}
	# Bound non-yielding loops, including cycles across chapters.
	for _step in range(10000):
		if not chapters.has(chapter) or not chapters[chapter] is Array:
			return _fail("Missing chapter")
		var code: Array = chapters[chapter]
		if pc == code.size():
			return {"kind": "end"}
		if pc < 0 or pc > code.size() or not code[pc] is Dictionary:
			return _fail("Invalid program position")
		var instruction: Dictionary = code[pc]
		pc += 1
		match instruction.get("op", ""):
			"presentation":
				if not instruction.get("command") is String or not instruction.get("args") is Array:
					return _fail("Invalid presentation instruction")
				return {"kind":"presentation", "chapter":chapter, "command":instruction.command,
					"args":instruction.args.duplicate(true), "source_line":instruction.get("source_line",0)}
			"frame":
				if not instruction.has("id"):
					return _fail("Missing frame identifier")
				return {"kind": "frame", "chapter": chapter, "id": instruction.id}
			"flag", "global_flag":
				if not instruction.get("id") is String:
					return _fail("Invalid flag identifier")
				var values: Dictionary = global_flags if instruction.op == "global_flag" else flags
				values[instruction.id] = bool(instruction.get("value", true))
			"jump":
				if not _jump(instruction):
					return _fail("Invalid jump target")
			"branch":
				if not instruction.get("id") is String:
					return _fail("Invalid condition")
				var values: Dictionary = global_flags if instruction.get("global", false) else flags
				if bool(values.get(instruction.id, false)) == bool(instruction.get("value", true)):
					if not _jump(instruction):
						return _fail("Invalid branch target")
			"choice":
				var options = instruction.get("options", [])
				if not options is Array or options.is_empty():
					return _fail("Empty choice")
				for option in options:
					if not option is Dictionary or not option.get("text") is String or not _valid_target(option):
						return _fail("Invalid choice option")
					if option.has("flag") and not option.flag is String:
						return _fail("Invalid choice flag")
				pending = options.duplicate(true)
				return {"kind": "choice", "options": pending.duplicate(true)}
			"end":
				pc = code.size()
				return {"kind": "end"}
			_:
				return _fail("Unsupported control instruction")
	return _fail("Control flow exceeded step limit")


func choose(index: int) -> bool:
	if not error.is_empty() or index < 0 or index >= pending.size():
		return false
	var selected: Dictionary = pending[index]
	if not _jump(selected):
		return false
	if selected.has("flag"):
		flags[selected.flag] = true
	pending = []
	return true


func snapshot() -> Dictionary:
	return {"schema": 1, "chapter": chapter, "pc": pc,
		"flags": flags.duplicate(true), "global_flags": global_flags.duplicate(true),
		"pending": pending.duplicate(true)}


func restore(data: Dictionary) -> bool:
	# Validate fully before mutating the current reading position.
	if data.get("schema") != 1 or not data.has_all(["chapter", "pc", "flags", "global_flags", "pending"]) or not _valid_target(data):
		return false
	for key in ["flags", "global_flags"]:
		if not data.get(key) is Dictionary:
			return false
		for id in data[key]:
			if not id is String or not data[key][id] is bool:
				return false
	if not data.get("pending") is Array:
		return false
	var position := int(data.pc)
	var options: Array = data.pending
	if not options.is_empty():
		# Do not accept arbitrary jump targets smuggled into a save file.
		if position < 1 or not chapters[data.chapter][position - 1] is Dictionary or chapters[data.chapter][position - 1].get("op") != "choice":
			return false
		if options != chapters[data.chapter][position - 1].get("options"):
			return false
	chapter = data.chapter
	pc = position
	flags = data.flags.duplicate(true)
	# Completion unlocks survive loading an earlier save.
	for id in data.global_flags:
		if data.global_flags[id]:
			global_flags[id] = true
	pending = options.duplicate(true)
	error = ""
	return true


func _valid_target(target: Dictionary) -> bool:
	var name = target.get("chapter", chapter)
	var position = target.get("pc", 0)
	return name is String and chapters.has(name) and chapters[name] is Array and (position is int or position is float) and is_finite(float(position)) and float(position) == floor(float(position)) and position >= 0 and position <= chapters[name].size()


func _jump(target: Dictionary) -> bool:
	if not _valid_target(target):
		return false
	chapter = target.get("chapter", chapter)
	pc = int(target.get("pc", 0))
	return true


func _fail(message: String) -> Dictionary:
	error = message
	return {"kind": "error", "message": error}
