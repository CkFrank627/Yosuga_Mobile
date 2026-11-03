# SPDX-License-Identifier: GPL-2.0-only
extends Control
var mode := "original"
var scene_texture: Texture2D
var background_texture: Texture2D
var foreground_texture: Texture2D
var effect_texture: Texture2D
var color_mode := "light"
func set_color_mode(value: String) -> void:
	color_mode = value
	queue_redraw()
func _tint(value: Color) -> Color:
	return Color(value.r*value.r,value.g*value.g,value.b*value.b,value.a) if color_mode=="dark" else value
func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	var blend := CanvasItemMaterial.new()
	blend.blend_mode = CanvasItemMaterial.BLEND_MODE_PREMULT_ALPHA
	material = blend
	resized.connect(queue_redraw)
func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO,size),Color.BLACK)
	var source := scene_texture.get_size() if scene_texture != null else Vector2(800,600)
	var factor := minf(size.x/source.x,size.y/source.y) if mode=="original" else maxf(size.x/source.x,size.y/source.y)
	var position := (size-source*factor)*0.5
	if background_texture != null:
		var region := Rect2(-position/factor,size/factor)
		if mode=="crop":draw_texture_rect_region(background_texture,Rect2(Vector2.ZERO,size),region)
		else:draw_texture_rect(background_texture,Rect2(position,source*factor),false)
		var actor_factor := minf(size.x/source.x,size.y/source.y)
		var actor_rect := Rect2((size-source*actor_factor)*0.5,source*actor_factor)
		draw_texture_rect(foreground_texture,actor_rect,false)
		if effect_texture!=null:
			if mode=="crop":draw_texture_rect_region(effect_texture,Rect2(Vector2.ZERO,size),region)
			else:draw_texture_rect(effect_texture,Rect2(position,source*factor),false)
		return
	if scene_texture != null:
		if mode=="original":draw_texture_rect(scene_texture,Rect2(position,source*factor),false)
		else:
			var region := Rect2(-position/factor,size/factor)
			draw_texture_rect_region(scene_texture,Rect2(Vector2.ZERO,size),region)
		return
	# Geometry-only fallback when no reading scene is open.
	draw_set_transform(position,0,Vector2.ONE*factor)
	draw_rect(Rect2(0,0,800,600),_tint(Color("77bdd1")))
	draw_circle(Vector2(650,100),55,_tint(Color("fff0b3")))
	draw_colored_polygon(PackedVector2Array([Vector2(0,420),Vector2(240,160),Vector2(460,420)]),_tint(Color("498b82")))
	draw_colored_polygon(PackedVector2Array([Vector2(320,420),Vector2(600,240),Vector2(800,420)]),_tint(Color("67a58f")))
	draw_rect(Rect2(0,420,800,180),_tint(Color("365e56")))
	var actor_factor := minf(size.x/800.0,size.y/600.0)
	draw_set_transform((size-Vector2(800,600)*actor_factor)*0.5,0,Vector2.ONE*actor_factor)
	for person in [[Vector2(300,350),Color("db9d78")],[Vector2(520,350),Color("b1a1d4")]]:
		draw_circle(person[0]-Vector2(0,90),38,_tint(person[1].lightened(0.2)))
		draw_rect(Rect2(person[0]-Vector2(40,45),Vector2(80,190)),_tint(person[1]))
