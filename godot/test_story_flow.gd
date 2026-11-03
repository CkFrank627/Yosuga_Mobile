# SPDX-License-Identifier: GPL-2.0-only
extends SceneTree

const Flow = preload("res://story_flow.gd")
var failures := 0


func check(condition: bool, message: String) -> void:
	if not condition:
		push_error(message)
		failures += 1


func _initialize() -> void:
	var flow = Flow.new()
	var program := {
		"start": [
			{"op": "frame", "id": "opening"},
			{"op": "choice", "options": [
				{"text": "Route A", "chapter": "a", "flag": "selected_a"},
				{"text": "Route B", "chapter": "b", "flag": "selected_b"}]}],
		"a": [{"op": "flag", "id": "a"}, {"op": "jump", "chapter": "finish"}],
		"b": [{"op": "frame", "id": "b"}, {"op": "jump", "chapter": "finish"}],
		"finish": [
			{"op": "branch", "id": "a", "chapter": "finish", "pc": 3},
			{"op": "frame", "id": "ending_b"}, {"op": "end"},
			{"op": "global_flag", "id": "completed_a"},
			{"op": "frame", "id": "ending_a"}, {"op": "end"}]
	}
	check(flow.begin(program, "start"), "Entry")
	check(flow.advance().get("id") == "opening", "Opening")
	check(flow.advance().kind == "choice", "Choice suspends execution")
	var saved: Dictionary = flow.snapshot()
	check(flow.advance().kind == "choice", "Repeated advance cannot skip choice")
	check(not flow.choose(2), "Out-of-range choice")
	check(flow.choose(0), "Choose A")
	check(flow.flags.get("selected_a", false), "Choice selection flag")
	check(flow.advance().get("id") == "ending_a", "Branch and cross-chapter jumps")
	check(flow.advance().kind == "end", "End A")
	check(flow.global_flags.get("completed_a", false), "Persistent flag")
	check(flow.restore(saved), "Restore at choice")
	check(flow.global_flags.get("completed_a", false), "Loading an old save preserves completion unlocks")
	check(not flow.flags.has("a"), "Restore resets route flags")
	check(flow.choose(1), "Choose B after restore")
	check(flow.flags.get("selected_b", false), "Restored choice selection flag")
	check(flow.advance().get("id") == "b", "Other route")
	check(flow.advance().get("id") == "ending_b", "False branch")
	var before: Dictionary = flow.snapshot()
	var invalid: Dictionary = saved.duplicate(true)
	invalid.erase("chapter")
	check(not flow.restore(invalid), "Reject missing chapter")
	invalid = saved.duplicate(true)
	invalid.pc = 1.5
	check(not flow.restore(invalid), "Reject fractional position")
	invalid = saved.duplicate(true)
	invalid.pending[0].chapter = "finish"
	check(not flow.restore(invalid), "Reject modified saved choice")
	check(flow.snapshot() == before, "Rejected restore is atomic")
	check(flow.begin({"loop": [{"op": "jump", "chapter": "loop"}]}, "loop"), "Loop setup")
	check(flow.advance().kind == "error", "Cycle bounded")
	check(flow.begin({"bad": [{"op": "jump", "chapter": "absent"}]}, "bad"), "Missing target setup")
	check(flow.advance().kind == "error", "Missing target rejected")
	print("STORY_FLOW: %s" % ("PASS" if failures == 0 else "FAIL"))
	quit(0 if failures == 0 else 1)
