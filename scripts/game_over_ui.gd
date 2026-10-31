extends Control

var main: Node = null
var container: VBoxContainer = null

func setup(m: Node) -> void:
	main = m
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0, 0, 0, 0.8)
	add_child(bg)

	var panel := Panel.new()
	panel.anchor_left = 0.30
	panel.anchor_top = 0.30
	panel.anchor_right = 0.70
	panel.anchor_bottom = 0.70
	add_child(panel)

	container = VBoxContainer.new()
	container.set_anchors_preset(Control.PRESET_FULL_RECT)
	container.offset_left = 20
	container.offset_top = 20
	container.offset_right = -20
	container.offset_bottom = -20
	container.add_theme_constant_override("separation", 10)
	panel.add_child(container)

func refresh() -> void:
	for c in container.get_children():
		c.queue_free()

	var title := Label.new()
	title.text = "GAME OVER"
	title.add_theme_font_size_override("font_size", 32)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	container.add_child(title)

	var t: int = int(main.elapsed)
	var info := Label.new()
	info.text = "生存时长: %02d:%02d" % [t / 60, t % 60]
	info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	container.add_child(info)

	var btn := Button.new()
	btn.text = "重新来过"
	btn.focus_mode = Control.FOCUS_NONE
	btn.pressed.connect(_on_restart)
	container.add_child(btn)

func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if (event as InputEventKey).keycode == KEY_R:
			_on_restart()
			get_viewport().set_input_as_handled()

func _on_restart() -> void:
	main.restart()
