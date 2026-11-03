# SPDX-License-Identifier: GPL-2.0-only
extends SceneTree
## Imports/loads real media; does not play or capture the story itself.
var failures:=0
func _initialize() -> void:
	call_deferred("_run")
func check(ok: bool, message: String) -> void:
	if not ok:
		failures+=1
		push_error(message)
func _run() -> void:
	create_timer(90).timeout.connect(func():push_error("RESTORED_MEDIA_TIMEOUT");quit(1))
	var player=load("res://main.tscn").instantiate()
	root.add_child(player)
	await process_frame
	var source=JSON.parse_string(FileAccess.get_file_as_string("res://content/story.json"))
	check(source is Dictionary and player._prepare_story(source) and player._validate_story_assets(),"Full restored story and every registered resource validate")
	check(player.story.chapters.size()==306,"All original chapters available")
	var native=player.native_visuals
	native.fast_test=true
	native.set_display_mode("crop")
	await native.execute("SetCg",["B01A",0,0])
	await native.execute("SetBustup",["CA02_01M",0,0])
	await native.execute("Commit",[])
	check(native.background.texture!=null and native.sprites["4"].texture!=null,"Real background and portrait load through imported asset table")
	var center: float=source.native_actor_centers.CA02_01M.x
	check(is_equal_approx(native.sprites["4"].position.x+center,400.0),"Real portrait visible center follows source center slot")
	player._play(player.sound_player,"SE100")
	check(player.sound_player.stream!=null and player.sound_player.stream.get_length()>0,"Restored sound effect decodes")
	player._play(player.bgm_player,"BGM03")
	check(player.bgm_player.stream is AudioStreamOggVorbis,"Duplicate legacy WAV/OGG music resolves to streaming OGG")
	player.sound_player.stop()
	player.bgm_player.stop()
	var frames:=0
	for animation in source.native_animations.values():
		for asset in animation.frames:
			var texture: Texture2D=player._texture(asset)
			check(texture!=null and texture.get_width()>0 and texture.get_height()>0,"Original animation frame loads")
			frames+=1
		await process_frame
	check(frames==432,"All restored animation frames imported")
	native.fast_test=false
	native.show()
	native.viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	var finished: Array=[false]
	_movie(native,finished)
	for i in range(30):await process_frame
	var videos: Array=native.viewport.get_children().filter(func(child):return child is VideoStreamPlayer)
	check(videos.size()==1 and videos[0].is_playing() and videos[0].get_video_texture()!=null,"Original OP plays as Theora video with decoded frames")
	player._notification(Node.NOTIFICATION_APPLICATION_PAUSED)
	for i in range(3):await process_frame
	check(videos[0].paused,"Video pauses while application is in background")
	player._notification(Node.NOTIFICATION_APPLICATION_RESUMED)
	for i in range(3):await process_frame
	check(not videos[0].paused,"Video resumes after foregrounding")
	native.skip_requested=true
	while not finished[0]:await process_frame
	print("RESTORED_MEDIA: %s (assets=%d, animation_frames=%d)" % ["PASS" if failures==0 else "FAIL",source.assets.size(),frames])
	quit(0 if failures==0 else 1)
func _movie(native, finished: Array) -> void:
	await native._movie("OPENING")
	finished[0]=true
