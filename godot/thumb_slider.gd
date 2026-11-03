# SPDX-License-Identifier: GPL-2.0-only
extends HSlider
## Settings sliders accept a drag only when it starts on the visible thumb.
const RADIUS := 14.0
var thumb_dragging := false
var drag_origin := 0.0
var value_origin := 0.0

func _init() -> void:
	editable = false # Native Slider would otherwise seek when the track is hit.
	scrollable = false
	focus_mode = Control.FOCUS_NONE
	custom_minimum_size.y = 44
	var empty := Image.create(1,1,false,Image.FORMAT_RGBA8)
	empty.fill(Color.TRANSPARENT)
	for key in ["grabber","grabber_highlight","grabber_disabled"]:
		add_theme_icon_override(key,ImageTexture.create_from_image(empty))
	for key in ["slider","grabber_area","grabber_area_highlight"]:
		add_theme_stylebox_override(key,StyleBoxEmpty.new())
	value_changed.connect(func(_value):queue_redraw())
	resized.connect(queue_redraw)

func thumb_center() -> Vector2:
	return Vector2(RADIUS+maxf(size.x-2*RADIUS,1.0)*get_as_ratio(),size.y*0.5)

func _draw() -> void:
	var center := thumb_center()
	draw_line(Vector2(RADIUS,center.y),Vector2(size.x-RADIUS,center.y),Color("405760"),6,true)
	draw_line(Vector2(RADIUS,center.y),center,Color("45a5b4"),6,true)
	draw_circle(center,RADIUS,Color("f2fbfc"))
	draw_arc(center,RADIUS,0,TAU,48,Color("45a5b4"),2,true)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT:
		if event.pressed:
			if event.position.distance_to(thumb_center())<=RADIUS+3:
				thumb_dragging = true
				drag_origin = event.position.x
				value_origin = value
				drag_started.emit()
		elif thumb_dragging:
			thumb_dragging = false
			if event.canceled:value = value_origin
			drag_ended.emit(not is_equal_approx(value,value_origin))
		accept_event()
	elif event is InputEventMouseMotion and thumb_dragging:
		value = value_origin+(event.position.x-drag_origin)/maxf(size.x-2*RADIUS,1.0)*(max_value-min_value)
		accept_event()

func _notification(what: int) -> void:
	if what==NOTIFICATION_VISIBILITY_CHANGED and not is_visible_in_tree():thumb_dragging = false
	if what in [NOTIFICATION_WM_WINDOW_FOCUS_OUT,NOTIFICATION_APPLICATION_PAUSED]:thumb_dragging = false
