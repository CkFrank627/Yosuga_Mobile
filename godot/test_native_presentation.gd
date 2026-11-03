# SPDX-License-Identifier: GPL-2.0-only
extends SceneTree

const Native = preload("res://native_presentation.gd")
var failures:=0

class Host extends Control:
	var application_paused:=false
	var on_title:=false
	var modal:=Control.new()
	var dialogue:=Control.new()
	var music_volume:=0.8
	var effect_volume:=0.7
	var voice_player:=AudioStreamPlayer.new()
	var sound_player:=AudioStreamPlayer.new()
	var story: Dictionary={}
	var textures: Dictionary={}
	var fallback: Texture2D
	func _texture(asset: String) -> Texture2D:
		if asset.is_empty() or asset in story.get("source_absent_assets",[]):return null
		return textures.get(asset,fallback)
	func _play(audio: AudioStreamPlayer, _asset: String, _loop:=false) -> void:
		audio.stop()

func _initialize() -> void:
	call_deferred("_run")

func check(value: bool, message: String) -> void:
	if not value:
		failures+=1
		push_error(message)

func _run() -> void:
	create_timer(90).timeout.connect(func():push_error("NATIVE_TIMEOUT");quit(1))
	var host:=Host.new()
	root.add_child(host)
	host.add_child(host.modal)
	host.add_child(host.dialogue)
	host.add_child(host.voice_player)
	host.add_child(host.sound_player)
	host.modal.hide()
	var image:=Image.create(200,600,false,Image.FORMAT_RGBA8)
	image.fill(Color.GREEN)
	host.fallback=ImageTexture.create_from_image(image)
	var native=Native.new()
	host.add_child(native)
	native.setup(host)
	check(is_equal_approx(native._source_curve(0.5,3.0),0.875),"Source acceleration 3 gives cubic ease out")
	check(is_equal_approx(native._source_curve(0.25,0.0),0.15625),"Source acceleration 0 gives cubic smoothstep")
	native.fast_test=true
	await native.execute("SetCgRGB",[255,0,0])
	await native.execute("SetBustup",["CA02_01M",0,0])
	check(native.sprites.is_empty(),"Set commands remain staged until commit")
	await native.execute("Commit",[])
	check(native.sprites["4"].position==Vector2(300,50),"Original portrait uses x=400 and bottom anchor y=600, height-50")
	await native.execute("SetBustup",["CC01_01M",0,0])
	await native.execute("Commit",[])
	check(native.state.characters.filter(func(c):return int(c.id)==2)[0].x==240,"Relation order puts CC at original left automatic slot")
	check(native.state.characters.filter(func(c):return int(c.id)==4)[0].x==560,"Relation order puts CA at original right automatic slot")
	check(native.sprites["4"].z_index>native.sprites["2"].z_index,"Lower Entis priority draws in front")
	await native.execute("SetBustup",["CA02_02M",3,0])
	await native.execute("Commit",[])
	check(native.state.characters.filter(func(c):return int(c.id)==4)[0].x==160,"Positive source slot 3 fixes x=160")
	await native.execute("Down",[4,25,1000,3])
	await native.execute("Commit",[])
	check(native.state.characters.filter(func(c):return int(c.id)==4)[0].y==625,"Down adds source pixels to y")
	await native.execute("Down",[4,-1,0,0])
	await native.execute("Commit",[])
	check(native.state.characters.filter(func(c):return int(c.id)==4)[0].y==600,"Down -1 returns to baseline")
	await native.execute("Jump",[4])
	await native.execute("Shake",[4])
	await native.execute("Commit",[])
	check(native.sprites["4"].position==Vector2(60,50),"Jump/shake finish at original position")
	await native.execute("Scroll",[120,80,1000,0,0])
	check(native.background.position==Vector2(-120,-80),"Scroll changes background source crop only")
	await native.execute("Zoom",[400,300,400,300,1000,0,0])
	check(native.stage.scale.is_equal_approx(Vector2(2.01,2.01)),"Zoom includes source sampling seam allowance")
	var snapshot: Dictionary=native.snapshot()
	native.reset()
	native.restore(snapshot)
	check(native.snapshot()==snapshot and native.stage.scale.is_equal_approx(Vector2(2.01,2.01)),"Native snapshot round trip retains layout and zoom")
	await native.execute("SetCg",["BLACK",0,0])
	await native.execute("Commit",[])
	check(native.state.characters.is_empty() and native.stage.scale==Vector2.ONE,"SetCg resets characters and zoom")
	image=Image.create(400,600,false,Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)
	image.fill_rect(Rect2i(20,40,180,560),Color.GREEN)
	host.textures["CAASYMMETRIC"]=ImageTexture.create_from_image(image)
	host.story["native_actor_centers"]={"CAASYMMETRIC":{"x":110,"width":400,"height":600}}
	await native.execute("SetBustup",["CAASYMMETRIC",0,0])
	await native.execute("Commit",[])
	check(native.sprites["4"].position.x==290,"Source layout centers asymmetric PNG visible pixels at x=400")
	var json_snapshot: Dictionary=JSON.parse_string(JSON.stringify(native.snapshot()))
	native.restore(json_snapshot)
	check(native.sprites["4"].position.x==290,"Actor snapshot survives JSON numeric conversion")
	# Actual transition framebuffer: previous red gives way to blue using a mask.
	native.fast_test=false
	await native.execute("SetCgRGB",[255,0,0])
	await native.execute("Update",[1])
	await process_frame
	await RenderingServer.frame_post_draw
	var rendered: Image=native.viewport.get_texture().get_image()
	check(rendered.get_pixel(400,300).is_equal_approx(Color.RED),"Native source stage renders exact RGB fill")
	image=Image.create(800,600,false,Image.FORMAT_RGB8)
	for x in range(800):image.fill_rect(Rect2i(x,0,1,600),Color(float(x)/799,float(x)/799,float(x)/799))
	host.textures["MASK"]=ImageTexture.create_from_image(image)
	await native.execute("SetCgRGB",[0,0,255])
	await native.execute("Transition",["MASK",300])
	var complete: Array=[false]
	native.set_process(false)
	_commit_later(native,complete)
	while not native.overlay.visible:await process_frame
	native._process(0.15)
	await RenderingServer.frame_post_draw
	rendered=native.viewport.get_texture().get_image()
	check(rendered.get_pixel(30,300).is_equal_approx(Color.BLUE),"Mask reveals new image at leading edge")
	check(rendered.get_pixel(770,300).is_equal_approx(Color.RED),"Mask retains previous image at trailing edge")
	native._process(0.16)
	while not complete[0]:await process_frame
	native.set_process(true)
	check(not native.overlay.visible,"Completed transition removes previous-frame overlay")
	var before: float=native.clock
	host.application_paused=true
	await process_frame
	await process_frame
	check(native.clock==before,"Backgrounding pauses native animation clock")
	host.application_paused=false
	# Execute the entire recovered instruction corpus with artificial textures.
	# This validates dispatch/state without exposing or rendering story imagery.
	var executed:=0
	for arg in OS.get_cmdline_user_args():
		if not arg.begins_with("--native-story="):continue
		host.story=JSON.parse_string(FileAccess.get_file_as_string(arg.trim_prefix("--native-story=")))
		native.fast_test=true
		for chapter in host.story.chapters.values():
			native.reset()
			for instruction in chapter.program:
				if instruction.op!="presentation":continue
				check(await native.execute(instruction.command,instruction.args),"Source command executes: "+instruction.command)
				executed+=1
			await process_frame
	print("NATIVE_CORPUS_INSTRUCTIONS: %d" % executed)
	print("NATIVE_PRESENTATION: %s" % ("PASS" if failures==0 else "FAIL"))
	quit(0 if failures==0 else 1)

func _commit_later(native, complete: Array) -> void:
	await native.execute("Commit",[])
	complete[0]=true
