extends Control

var main: MainNode = null
var label: Label = null
var shop_btn: Button = null
var editor_btn: Button = null

func setup(m: MainNode) -> void:
	main = m
	label = Label.new()
	label.position = Vector2(14, 10)
	label.add_theme_font_size_override("font_size", 16)
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	label.add_theme_constant_override("shadow_offset_x", 2)
	label.add_theme_constant_override("shadow_offset_y", 2)
	add_child(label)

	shop_btn = _make_button("商店", -280, -150)
	shop_btn.pressed.connect(func(): main.toggle_shop())
	add_child(shop_btn)

	editor_btn = _make_button("编辑", -140, -10)
	editor_btn.pressed.connect(func(): main.toggle_editor())
	add_child(editor_btn)

func _make_button(text: String, x_left: float, x_right: float) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.anchor_left = 1.0
	b.anchor_right = 1.0
	b.offset_left = x_left
	b.offset_right = x_right
	b.offset_top = 10
	b.offset_bottom = 76
	b.add_theme_font_size_override("font_size", 20)
	return b

func _process(_delta: float) -> void:
	if main == null or label == null:
		return
	var t: int = int(main.elapsed)
	var mm := t / 60
	var ss := t % 60
	var hp := int(main.player.hp)
	var wname: String = "?"
	if main.current_weapon != null:
		wname = main.current_weapon.weapon_name
	var bullets := main.bullet_pool.get_active().size()
	var enemies := main.enemy_container.get_child_count()
	var fps := Engine.get_frames_per_second()
	var touch_state := "ON" if main.touch_controls.enabled else "OFF"
	label.text = "时间: %02d:%02d    $%d    赚钱速率 %.1f/s\nHP %d/%d    武器: %s\n子弹实体 %d  怪物实体 %d  FPS %d  Hits %d  Touch[%s]" % [
		mm, ss, int(main.currency), main.rate,
		hp, int(main.player.max_hp), wname,
		bullets, enemies, fps, main.debug_hits, touch_state
	]
