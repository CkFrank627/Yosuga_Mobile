# SPDX-License-Identifier: GPL-2.0-only
extends SceneTree
## Render-only regression fixture: generated color bands, no story media.

var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)


func _run() -> void:
	create_timer(30).timeout.connect(func(): push_error("CAMERA_RENDER_TIMEOUT"); quit(1))
	var player = load("res://main.tscn").instantiate()
	root.add_child(player)
	await process_frame
	player.chrome_hidden = true
	player._apply_chrome()
	var source := Image.create(1766, 600, false, Image.FORMAT_RGB8)
	source.fill(Color.RED)
	source.fill_rect(Rect2i(400, 0, 400, 600), Color.GREEN)
	source.fill_rect(Rect2i(800, 0, 400, 600), Color.BLUE)
	source.fill_rect(Rect2i(1200, 0, 566, 600), Color.YELLOW)
	player.bg.texture = ImageTexture.create_from_image(source)
	var frame := {"camera": {"source_coordinates": true, "offset": [400.0, 0.0]}, "characters": []}
	player._layout_visuals(frame)
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var rendered := root.get_texture().get_image()
	var y := int(rendered.get_height() * 0.4)
	check(rendered.get_pixel(8, y).is_equal_approx(Color.GREEN), "CG crop begins at source x=400; left edge is filled")
	check(rendered.get_pixel(rendered.get_width() - 8, y).is_equal_approx(Color.BLUE), "CG crop ends at source x=1200; right edge is filled")
	rendered.save_png(ProjectSettings.globalize_path("res://../reports/preview-camera-crop.png"))
	frame.camera.offset = [966.0, 0.0]
	player._layout_visuals(frame)
	await process_frame
	await RenderingServer.frame_post_draw
	rendered = root.get_texture().get_image()
	check(rendered.get_pixel(8, y).is_equal_approx(Color.BLUE), "Far-edge crop begins inside the background")
	check(rendered.get_pixel(rendered.get_width() - 8, y).is_equal_approx(Color.YELLOW), "Far-edge crop fills the viewport through the last image column")
	frame.camera = {}
	player._layout_visuals(frame)
	check(player.bg.size.is_equal_approx(player.size) and player.bg.position.is_zero_approx(), "Next ordinary frame resets crop geometry")
	print("CAMERA_RENDER: %s" % ("PASS" if failures == 0 else "FAIL"))
	quit(0 if failures == 0 else 1)
