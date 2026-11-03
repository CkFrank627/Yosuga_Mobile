# SPDX-License-Identifier: GPL-2.0-only
extends SceneTree

var failures:=0
func _initialize() -> void:
	call_deferred("_run")
func check(ok: bool, message: String) -> void:
	if not ok:
		failures+=1
		push_error(message)

func _run() -> void:
	create_timer(30).timeout.connect(func():push_error("NATIVE_PLAYER_TIMEOUT");quit(1))
	var player=load("res://main.tscn").instantiate()
	root.add_child(player)
	await process_frame
	player.native_visuals.fast_test=true
	var fixture: Dictionary={"schema":2,"entry":"fixture","source_sha256":"native-artificial-fixture", "assets":{},
		"native_presentation":true,"chapters":{"fixture":{
		"dialogue":{"first":{"speaker":"","text":"First.","voice":""},"second":{"speaker":"","text":"Second.","voice":""}},
		"scenes":{"first":{"native":true},"second":{"native":true}},
		"program":[{"op":"presentation","command":"SetCgRGB","args":[255,0,0]},
			{"op":"presentation","command":"Font","args":[48,""]},
			{"op":"presentation","command":"Commit","args":[]},{"op":"frame","id":"first"},
			{"op":"presentation","command":"SetCgRGB","args":[0,0,255]},
			{"op":"presentation","command":"Commit","args":[]},{"op":"frame","id":"second"},
			{"op":"end"}]}}}
	check(player._prepare_story(fixture) and player._validate_story_assets(),"Native schema validates")
	check(player.flow.begin(player.chapter_programs,fixture.entry),"Native flow starts")
	await player._advance_flow()
	check(player.body.text=="First." and player.native_visuals.state.color==[255,0,0],"Presentation runs before corresponding dialogue")
	check(player.history.back().native_state.color==[255,0,0],"History stores original stage snapshot")
	check(player.history.back().native_state.font==48,"Source Font applies to current paragraph")
	await player._advance_flow()
	check(player.body.text=="Second." and player.native_visuals.state.color==[0,0,255],"Second frame has its own scene")
	check(player.native_visuals.state.font==0,"Source Font resets for the next paragraph")
	player._previous()
	check(player.body.text=="First." and player.native_visuals.state.color==[255,0,0],"Back navigation restores scene without replaying effects")
	await player._advance_flow()
	check(player.native_visuals.state.color==[0,0,255],"Forward history restores scene")
	var slot: String=player._save_current("native-test")
	check(not slot.is_empty(),"Native snapshot saves")
	player.native_visuals.reset()
	check(player._load_slot(slot),"Native snapshot loads with validation")
	check(player.body.text=="Second." and player.native_visuals.state.color[2]==255 and player.native_visuals.state.color[0]==0,"Loaded scene matches displayed dialogue")
	var bad: Dictionary=player.saves.read(slot)
	bad.history.back().native_state.zoom=[400,300,0,600]
	check(player.saves.write("bad-native.json",bad),"Write malformed snapshot fixture")
	check(not player._load_slot("bad-native.json"),"Invalid native zoom is rejected before rendering")
	player.presentation_busy=true
	player.flow.pc+=1
	var paused_slot: String=player._save_current("paused")
	check(not paused_slot.is_empty() and player._same_flow_position(player.saves.read(paused_slot).flow,player.history.back().flow),
		"Background autosave during effect uses completed dialogue boundary")
	player.presentation_busy=false
	player.flow.restore(player.history.back().flow)
	player._notification(Node.NOTIFICATION_APPLICATION_PAUSED)
	var native_clock: float=player.native_visuals.clock
	await process_frame
	await process_frame
	check(player.native_visuals.clock==native_clock,"Player background notification pauses source stage")
	player._notification(Node.NOTIFICATION_APPLICATION_RESUMED)
	player._show_title()
	player._continue_from_title()
	check(player.body.text=="Second." and player.native_visuals.state.color[2]==255 and player.native_visuals.state.color[0]==0,"Title/continue restores native stage")
	print("NATIVE_PLAYER: %s" % ("PASS" if failures==0 else "FAIL"))
	quit(0 if failures==0 else 1)
