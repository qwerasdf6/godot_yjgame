extends Control

const STICK_RADIUS := 90.0
const KNOB_RADIUS := 36.0
const FIRE_THRESHOLD := 15.0

var enabled := false

var left_index: int = -1
var left_active := false
var left_center := Vector2.ZERO
var left_offset := Vector2.ZERO

var right_index: int = -1
var right_active := false
var right_center := Vector2.ZERO
var right_offset := Vector2.ZERO

var move_vector := Vector2.ZERO
var aim_vector := Vector2.ZERO
var is_firing := false

func _ready() -> void:
	enabled = DisplayServer.is_touchscreen_available() or OS.has_feature("mobile")
	visible = enabled
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process_input(enabled)

func set_enabled(v: bool) -> void:
	enabled = v
	visible = v
	set_process_input(v)
	if not v:
		_reset_sticks()

func _input(event: InputEvent) -> void:
	if not enabled:
		return
	if event is InputEventScreenTouch:
		_handle_touch(event)
	elif event is InputEventScreenDrag:
		_handle_drag(event)
	queue_redraw()

func _handle_touch(e: InputEventScreenTouch) -> void:
	var view := get_viewport_rect().size
	var pos := e.position
	if pos.y < view.y * 0.5:
		return
	var is_left := pos.x < view.x * 0.5
	if e.pressed:
		if is_left and not left_active:
			left_active = true
			left_index = e.index
			left_center = pos
			left_offset = Vector2.ZERO
		elif not is_left and not right_active:
			right_active = true
			right_index = e.index
			right_center = pos
			right_offset = Vector2.ZERO
	else:
		if left_active and e.index == left_index:
			left_active = false
			left_index = -1
			left_offset = Vector2.ZERO
			move_vector = Vector2.ZERO
		elif right_active and e.index == right_index:
			right_active = false
			right_index = -1
			right_offset = Vector2.ZERO
			aim_vector = Vector2.ZERO
			is_firing = false

func _handle_drag(e: InputEventScreenDrag) -> void:
	if left_active and e.index == left_index:
		left_offset = _clamp_offset(e.position - left_center)
		move_vector = left_offset / STICK_RADIUS
	elif right_active and e.index == right_index:
		right_offset = _clamp_offset(e.position - right_center)
		var mag := right_offset.length()
		if mag >= FIRE_THRESHOLD:
			aim_vector = right_offset.normalized()
			is_firing = true
		else:
			is_firing = false

func _clamp_offset(v: Vector2) -> Vector2:
	if v.length() > STICK_RADIUS:
		return v.normalized() * STICK_RADIUS
	return v

func _reset_sticks() -> void:
	left_active = false
	right_active = false
	left_index = -1
	right_index = -1
	left_offset = Vector2.ZERO
	right_offset = Vector2.ZERO
	move_vector = Vector2.ZERO
	aim_vector = Vector2.ZERO
	is_firing = false
	queue_redraw()

func _draw() -> void:
	if not enabled:
		return
	if left_active:
		_draw_stick(left_center, left_offset)
	if right_active:
		_draw_stick(right_center, right_offset)

func _draw_stick(center: Vector2, offset: Vector2) -> void:
	draw_circle(center, STICK_RADIUS, Color(1, 1, 1, 0.08))
	draw_arc(center, STICK_RADIUS, 0.0, TAU, 40, Color(1, 1, 1, 0.3), 2.0)
	draw_circle(center + offset, KNOB_RADIUS, Color(1, 1, 1, 0.28))
