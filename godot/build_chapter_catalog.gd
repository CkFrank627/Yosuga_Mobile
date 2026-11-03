# SPDX-License-Identifier: GPL-2.0-only
extends SceneTree
## Build navigation metadata using the same flow and stage interpreter as playback.
const Native = preload("res://native_presentation.gd")
const Flow = preload("res://story_flow.gd")

class Host extends Control:
	var application_paused := false
	var on_title := false
	var modal := Control.new()
	var dialogue := Control.new()
	var voice_player := AudioStreamPlayer.new()
	var sound_player := AudioStreamPlayer.new()
	var music_volume := 0.0
	var effect_volume := 0.0
	var story: Dictionary = {}
	var fallback: Texture2D
	func _texture(asset: String) -> Texture2D:
		return null if asset.is_empty() or asset in story.get("source_absent_assets",[]) else fallback
	func _play(audio: AudioStreamPlayer, _asset: String, _loop := false) -> void:audio.stop()

func _initialize() -> void:call_deferred("_run")

func _run() -> void:
	var host := Host.new()
	root.add_child(host)
	for node in [host.modal,host.dialogue,host.voice_player,host.sound_player]:host.add_child(node)
	host.modal.hide()
	var image := Image.create(2,2,false,Image.FORMAT_RGBA8)
	image.fill(Color.WHITE)
	host.fallback = ImageTexture.create_from_image(image)
	host.story = JSON.parse_string(FileAccess.get_file_as_string("res://content/story.json"))
	var native = Native.new()
	host.add_child(native)
	native.setup(host)
	native.fast_test = true
	var programs := {}
	for id in host.story.chapters:programs[id] = host.story.chapters[id].program
	var routes := []
	var covered := {}
	for spec in [["main","主线","z"],["sora","穹线","a"],["nao","奈绪线","b"],
		["akira","瑛线","c"],["kazuha","一叶线","d"],["motoka","初佳线","e"]]:
		var route := {"id":spec[0],"title":spec[1],"entries":[]}
		var flow = Flow.new()
		assert(flow.begin(programs,host.story.entry,{"game_clear":true}))
		native.reset()
		var previous := ""
		var steps := 0
		while steps < 200000:
			steps += 1
			var result: Dictionary = flow.advance()
			if flow.chapter != previous:
				previous = flow.chapter
				var prefix := previous.substr(3,1)
				if spec[2]==prefix or (spec[2]=="e" and prefix=="g"):
					# advance() has yielded the first presentation/frame; rewind its PC.
					assert(result.kind in ["presentation","frame"])
					assert(not native.changed and native.queued.is_empty(),previous)
					route.entries.append({"chapter":previous,"title":spec[1]+str(route.entries.size()+1),
						"flags":flow.flags.duplicate(true),"native_state":native.snapshot()})
					covered[previous] = true
				elif spec[0]=="main":break
			match result.kind:
				"presentation":assert(await native.execute(result.command,result.args),native.error)
				"frame":
					native.state.font = 0
					native.pending.font = 0
				"choice":
					var selected := 1
					if (spec[2]=="a" and flow.chapter=="00_z005") or (spec[2]=="b" and flow.chapter=="00_z008") or (spec[2]=="c" and flow.chapter=="00_z012") or (spec[2]=="d" and flow.chapter=="00_z014"):selected=0
					assert(flow.choose(selected))
				"end":break
				_:assert(false,JSON.stringify(result))
			if steps%500==0:await process_frame
		assert(steps<200000 and not route.entries.is_empty(),spec[0])
		routes.append(route)
		print("CATALOG_ROUTE: ",spec[0]," ",route.entries.size())
	var excluded := []
	for id in programs:
		if not covered.has(id):excluded.append(id)
	# This source fragment has no inbound edge and is not part of normal playback.
	assert(excluded==["00_b18b"],JSON.stringify(excluded))
	var data := {"schema":1,"source_sha256":host.story.source_sha256,"routes":routes,
		"unreachable_source_fragments":excluded}
	var file := FileAccess.open("res://content/chapter_catalog.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(data,"\t"))
	file.close()
	print("CHAPTER_CATALOG_BUILD: PASS; ",covered.size()," reachable source chapters")
	quit()
