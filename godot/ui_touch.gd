# SPDX-License-Identifier: GPL-2.0-only
extends RefCounted
## Own UI touch gestures; native mouse/wheel/trackpad input remains unchanged.
const MOUSE_DEVICE := -42
var suppress_emulated := false
var pointer := -1
var start := Vector2.ZERO
var last := Vector2.ZERO
var travel := 0.0
var dragging := false
var scroll: ScrollContainer
var direct: Control
var mouse_down := false
var velocity := Vector2.ZERO
var last_motion := 0
var blocked: Dictionary = {}
var viewport: Viewport

func _mouse(point: Vector2, pressed: bool, canceled := false) -> void:
	var event := InputEventMouseButton.new()
	event.device = MOUSE_DEVICE
	event.position = point
	event.global_position = point
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	event.canceled = canceled
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	viewport.push_input(event,true)

func _motion(point: Vector2, relative: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.device = MOUSE_DEVICE
	event.position = point
	event.global_position = point
	event.relative = relative
	event.button_mask = MOUSE_BUTTON_MASK_LEFT
	viewport.push_input(event,true)

func reset() -> void:
	var release := mouse_down
	mouse_down = false
	pointer = -1
	dragging = false
	velocity = Vector2.ZERO
	if is_instance_valid(scroll):scroll.propagate_notification(Control.NOTIFICATION_SCROLL_END)
	if release and is_instance_valid(viewport):
		if is_instance_valid(direct):direct.notification(Control.NOTIFICATION_SCROLL_BEGIN)
		_mouse(last,false,true)
	scroll = null
	direct = null
	blocked.clear()

func _find(node: Node, point: Vector2, want_scroll: bool) -> Control:
	if node is Viewport:return null # Native popup windows own their own input.
	if node is Control:
		if not node.is_visible_in_tree() or node.is_queued_for_deletion():return null
		if (node.clip_contents or node is ScrollContainer) and not node.get_global_rect().has_point(point):return null
	var children := node.get_children()
	children.reverse()
	for child in children:
		var found := _find(child,point,want_scroll)
		if found != null:return found
	if node is Control and node.get_global_rect().has_point(point):
		if want_scroll and node is ScrollContainer:return node
		if not want_scroll and (node is Slider or node is ScrollBar or node is LineEdit):return node
	return null

func handle(host: Control, event: InputEvent) -> bool:
	if event.device == MOUSE_DEVICE:return false
	if event.device == -1 and suppress_emulated and (event is InputEventMouseButton or event is InputEventMouseMotion):return true
	if not (event is InputEventScreenTouch or event is InputEventScreenDrag):
		if event is InputEventPanGesture or (event is InputEventMouseButton and event.pressed):velocity = Vector2.ZERO
		return false
	viewport = host.get_viewport()
	var ui: Control = host.modal if host.modal.visible else (host.front if host.on_title else null)
	if event is InputEventScreenTouch:
		if not blocked.is_empty():
			if event.pressed and blocked.has(event.index):reset()
			else:
				if event.pressed:blocked[event.index] = true
				else:blocked.erase(event.index)
				return true
		if event.pressed:
			if pointer >= 0 and pointer != event.index:
				var old := pointer
				reset()
				blocked = {old:true,event.index:true}
				return true
			reset() # A fresh press always interrupts momentum and stale state.
			suppress_emulated = ui != null
			if ui == null:return false
			pointer = event.index
			start = event.position
			last = start
			travel = 0.0
			last_motion = Time.get_ticks_usec()
			var canvas_point := host.get_global_transform_with_canvas().affine_inverse() * start
			scroll = _find(ui,canvas_point,true) as ScrollContainer
			direct = _find(ui,canvas_point,false)
			if direct != null:
				mouse_down = true
				_mouse(start,true)
			return true
		if event.index != pointer:return suppress_emulated
		var point: Vector2 = event.position
		var was_dragging := dragging
		var was_direct := mouse_down
		var canceled: bool = event.canceled
		var tap := not canceled and not was_dragging and travel <= 20.0 and start.distance_to(point) <= 20.0
		pointer = -1 # Callbacks may replace the entire modal tree.
		mouse_down = false
		dragging = false
		if canceled or Time.get_ticks_usec()-last_motion>100000:velocity = Vector2.ZERO
		if was_dragging and is_instance_valid(scroll):scroll.propagate_notification(Control.NOTIFICATION_SCROLL_END)
		if was_direct:
			if canceled and is_instance_valid(direct):direct.notification(Control.NOTIFICATION_SCROLL_BEGIN)
			_mouse(point,false,canceled)
		elif tap:
			_mouse(point,true)
			_mouse(point,false)
		return true
	if event.index != pointer:return suppress_emulated
	var relative: Vector2 = event.position-last
	last = event.position
	travel += relative.length()
	var distance: Vector2 = last-start
	var can_drag := is_instance_valid(scroll) and not (direct is ScrollBar)
	if direct is HSlider or direct is LineEdit:can_drag = can_drag and absf(distance.y)>absf(distance.x)*1.2
	if not dragging and can_drag and distance.length()>12.0:
		dragging = true
		scroll.propagate_notification(Control.NOTIFICATION_SCROLL_BEGIN)
		if mouse_down:
			mouse_down = false
			_mouse(last,false,true)
	if dragging and is_instance_valid(scroll):
		var local := scroll.get_global_transform_with_canvas().affine_inverse().basis_xform(relative)
		_shift(-local)
		var now := Time.get_ticks_usec()
		var dt := clampf(float(now-last_motion)/1000000.0,1.0/240.0,0.1)
		velocity = velocity.lerp((-local/dt).limit_length(3500.0),0.5)
		last_motion = now
	elif mouse_down:
		_motion(last,relative)
	return true

func _shift(delta: Vector2) -> void:
	if scroll.horizontal_scroll_mode != ScrollContainer.SCROLL_MODE_DISABLED:
		var bar := scroll.get_h_scroll_bar()
		bar.value = clampf(bar.value+delta.x,bar.min_value,maxf(bar.min_value,bar.max_value-bar.page))
	if scroll.vertical_scroll_mode != ScrollContainer.SCROLL_MODE_DISABLED:
		var bar := scroll.get_v_scroll_bar()
		bar.value = clampf(bar.value+delta.y,bar.min_value,maxf(bar.min_value,bar.max_value-bar.page))

func tick(delta: float) -> void:
	if pointer >= 0 or velocity.length()<5.0:return
	if not is_instance_valid(scroll) or not scroll.is_visible_in_tree() or scroll.is_queued_for_deletion():
		velocity = Vector2.ZERO
		return
	var before := Vector2(scroll.get_h_scroll_bar().value,scroll.get_v_scroll_bar().value)
	_shift(velocity*delta)
	var after := Vector2(scroll.get_h_scroll_bar().value,scroll.get_v_scroll_bar().value)
	if is_equal_approx(before.x,after.x):velocity.x = 0.0
	if is_equal_approx(before.y,after.y):velocity.y = 0.0
	velocity *= exp(-10.0*delta)
