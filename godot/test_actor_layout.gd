# SPDX-License-Identifier: GPL-2.0-only
extends SceneTree
## Artificial asymmetric sprites: checks geometry and actual rendered pixels.

var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)

func visible_rect(layer: TextureRect, source_bounds := Rect2()) -> Rect2:
	var bounds := source_bounds if source_bounds.has_area() else Rect2(layer.texture.get_image().get_used_rect())
	var fit := minf(layer.size.x / layer.texture.get_width(), layer.size.y / layer.texture.get_height())
	var local_start := (layer.size - layer.texture.get_size() * fit) * 0.5 + bounds.position * fit
	return Rect2(layer.position + layer.pivot_offset + (local_start - layer.pivot_offset) * layer.scale,
		bounds.size * fit * layer.scale)

func _run() -> void:
	create_timer(60).timeout.connect(func(): push_error("ACTOR_LAYOUT_TIMEOUT"); quit(1))
	var player = load("res://main.tscn").instantiate()
	root.add_child(player)
	await process_frame
	player.on_title = false
	player.front.hide()
	player.chrome_hidden = true
	player._apply_chrome()
	player.bg.texture = null
	player.bg_fill.color = Color.BLACK
	var image := Image.create(400, 600, false, Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)
	image.fill_rect(Rect2i(20, 40, 180, 560), Color.GREEN)
	var layer: TextureRect = player.actors[0]
	layer.texture = ImageTexture.create_from_image(image)
	layer.show()
	var frame := {"characters": [{"asset": "artificial", "x": 0.5}], "camera": {}}
	for viewport in [Vector2(1280, 720), Vector2(1560, 720), Vector2(1920, 1080), Vector2(1280, 640)]:
		player.size = viewport
		for x in [0.25, 0.5, 0.75]:
			frame.characters[0].x = x
			for zoom in [1.0, 1.4]:
				frame.camera = {"zoom": zoom}
				player._layout_visuals(frame)
				check(is_equal_approx(visible_rect(layer).get_center().x, viewport.x * x),
					"Visible center follows requested x=%s, viewport=%s, zoom=%s" % [x, viewport, zoom])
	player.size = Vector2(1280, 720)
	frame.characters[0] = {"asset": "artificial", "x": 0.5, "y": 60.0}
	frame.camera = {"source_coordinates": true, "offset": [400.0, 0.0]}
	player._layout_visuals(frame)
	check(is_equal_approx(layer.position.y, 72.0), "Source vertical offset uses viewport height / 600")
	check(is_equal_approx(visible_rect(layer).get_center().x, 640.0), "Background crop leaves actor centered")
	frame.characters[0].y = 0.0
	frame.camera = {"offset": [17.0, -9.0]}
	player._layout_visuals(frame)
	check(is_equal_approx(visible_rect(layer).get_center().x, 657.0), "Generic camera translation remains supported")
	frame.camera = {}
	player._layout_visuals(frame)
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var rendered := root.get_texture().get_image()
	var left := -1
	var right := -1
	var y := int(rendered.get_height() * 0.4)
	for x in range(rendered.get_width()):
		if rendered.get_pixel(x, y).is_equal_approx(Color.GREEN):
			if left < 0:
				left = x
			right = x
	check(left >= 0 and absf((left + right + 1) * 0.5 - rendered.get_width() * 0.5) <= 1.0,
		"Rendered asymmetric sprite is visually centered within one pixel")
	rendered.save_png(ProjectSettings.globalize_path("res://../reports/actor-center-synthetic.png"))
	# Changing expressions must invalidate the bounds by texture identity.
	image.fill(Color.TRANSPARENT)
	image.fill_rect(Rect2i(180, 40, 180, 560), Color.GREEN)
	layer.texture = ImageTexture.create_from_image(image)
	player._layout_visuals(frame)
	check(is_equal_approx(visible_rect(layer).get_center().x, 640.0), "Opposite transparent margin after expression change")
	image.fill(Color.TRANSPARENT)
	layer.texture = ImageTexture.create_from_image(image)
	player._layout_visuals(frame)
	check(layer.position.is_finite(), "Fully transparent sprite has finite geometry")
	# Optional raw asset scan avoids importing unrelated audio or story content.
	var audited := 0
	for argument in OS.get_cmdline_user_args():
		if not argument.begins_with("--actor-assets="):
			continue
		var directory := argument.trim_prefix("--actor-assets=")
		for filename in DirAccess.get_files_at(directory):
			if not filename.ends_with(".png"):
				continue
			var source := Image.load_from_file(directory.path_join(filename))
			if source == null or source.get_format() != Image.FORMAT_RGBA8:
				continue
			layer.texture = ImageTexture.create_from_image(source)
			var source_bounds := Rect2(source.get_used_rect())
			for viewport in [Vector2(1280, 720), Vector2(1560, 720), Vector2(1920, 1080), Vector2(1280, 640)]:
				player.size = viewport
				for x in [0.25, 0.5, 0.75]:
					frame.characters[0].x = x
					for zoom in [1.0, 1.4]:
						frame.camera = {"zoom": zoom}
						player._layout_visuals(frame)
						check(absf(visible_rect(layer, source_bounds).get_center().x - viewport.x * x) < 0.01,
							"Asset visible center: %s, x=%s, size=%s, zoom=%s" % [filename, x, viewport, zoom])
			audited += 1
			if audited % 50 == 0:
				await process_frame
	print("ACTOR_ASSETS_AUDITED: %d" % audited)
	print("ACTOR_LAYOUT: %s" % ("PASS" if failures == 0 else "FAIL"))
	quit(0 if failures == 0 else 1)
