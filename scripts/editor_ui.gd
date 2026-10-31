extends Control

var main: MainNode = null
var container: VBoxContainer = null
var selected_slot: int = -1

const SLOT_COLUMNS := 4
# 垂直滚动条宽度：默认约 8px，太细不便于鼠标拖拽和触屏
const SCROLLBAR_WIDTH := 24
const SPELL_LIST_HEIGHT := 200

func setup(m: MainNode) -> void:
	main = m
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0, 0, 0, 0.7)
	add_child(bg)

	var panel := Panel.new()
	panel.anchor_left = 0.15
	panel.anchor_top = 0.08
	panel.anchor_right = 0.85
	panel.anchor_bottom = 0.92
	add_child(panel)

	container = VBoxContainer.new()
	container.set_anchors_preset(Control.PRESET_FULL_RECT)
	container.offset_left = 20
	container.offset_top = 20
	container.offset_right = -20
	container.offset_bottom = -20
	container.add_theme_constant_override("separation", 6)
	panel.add_child(container)

func refresh() -> void:
	# 先 remove_child 再 queue_free，避免同帧新旧节点并存
	for c in container.get_children():
		container.remove_child(c)
		c.queue_free()

	var w: WeaponData = main.current_weapon
	if w != null:
		_normalize_slots(w)

	if w != null and selected_slot >= w.slot_count:
		selected_slot = -1

	var title := Label.new()
	title.text = "武器编辑系统   (E / Esc 关闭)"
	title.add_theme_font_size_override("font_size", 20)
	container.add_child(title)

	if w == null:
		return

	var info := Label.new()
	info.text = "%s   |   %d 技能槽  |   释放冷却 %.2fs" % [w.weapon_name, w.slot_count, w.cast_delay]
	container.add_child(info)

	var hint := Label.new()
	hint.text = "1) 点击一个槽位   2) 点击下方的一个技能来放置"
	container.add_child(hint)

	container.add_child(_spacer(6))

	# 槽位用 GridContainer 排列，槽多时自动换行
	var slot_grid := GridContainer.new()
	slot_grid.columns = SLOT_COLUMNS
	slot_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slot_grid.add_theme_constant_override("h_separation", 6)
	slot_grid.add_theme_constant_override("v_separation", 6)
	container.add_child(slot_grid)

	for i in w.slot_count:
		var s: SpellData = w.slots[i]
		var btn := Button.new()
		var base_text := "%d: %s" % [i + 1, s.spell_name if s else "(无)"]
		if i == selected_slot:
			btn.text = "▶ " + base_text
			btn.modulate = Color(1.0, 1.0, 0.8)
		else:
			btn.text = base_text
		btn.custom_minimum_size = Vector2(0, 52)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.add_theme_font_size_override("font_size", 18)
		btn.focus_mode = Control.FOCUS_NONE
		btn.pressed.connect(_on_slot_selected.bind(i))
		slot_grid.add_child(btn)

	container.add_child(_spacer(10))

	var clear_btn := Button.new()
	clear_btn.text = "清理技能槽"
	clear_btn.custom_minimum_size = Vector2(0, 46)
	clear_btn.add_theme_font_size_override("font_size", 18)
	clear_btn.focus_mode = Control.FOCUS_NONE
	clear_btn.pressed.connect(_on_clear_slot)
	container.add_child(clear_btn)

	container.add_child(_spacer(6))

	var spell_label := Label.new()
	spell_label.text = "拥有的技能:"
	container.add_child(spell_label)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(0, SPELL_LIST_HEIGHT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	container.add_child(scroll)

	# 关键：加宽垂直滚动条
	_widen_scrollbar(scroll)

	var spell_list := VBoxContainer.new()
	spell_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(spell_list)

	for i in main.owned_spells.size():
		var s: SpellData = main.owned_spells[i]
		var btn := Button.new()
		var prefix := "[插件] " if s.type == SpellData.Type.PROJECTILE else "[增益]  "
		btn.text = "%s%s" % [prefix, s.spell_name]
		btn.custom_minimum_size = Vector2(0, 46)
		btn.add_theme_font_size_override("font_size", 18)
		btn.focus_mode = Control.FOCUS_NONE
		btn.pressed.connect(_on_spell_pick.bind(i))
		spell_list.add_child(btn)

	container.add_child(_spacer(6))

	var close_btn := Button.new()
	close_btn.text = "关闭"
	close_btn.custom_minimum_size = Vector2(0, 52)
	close_btn.add_theme_font_size_override("font_size", 18)
	close_btn.focus_mode = Control.FOCUS_NONE
	close_btn.pressed.connect(func(): main._apply_ui_state(MainNode.UIState.NONE))
	container.add_child(close_btn)

func _spacer(h: int) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	return c

# 保证 slots 长度与 slot_count 一致
func _normalize_slots(w: WeaponData) -> void:
	while w.slots.size() < w.slot_count:
		w.slots.append(null)

# 加宽 ScrollContainer 的垂直滚动条（含滑块），
# 原理：VScrollBar 的宽度 = 它自己的 custom_minimum_size.x，
# grabber 会按该宽度拉伸，因此视觉上也变粗。
func _widen_scrollbar(scroll: ScrollContainer) -> void:
	var vbar := scroll.get_v_scroll_bar()
	if vbar != null:
		vbar.custom_minimum_size = Vector2(SCROLLBAR_WIDTH, 0)

func _on_slot_selected(i: int) -> void:
	selected_slot = i
	refresh()

func _on_spell_pick(i: int) -> void:
	if selected_slot < 0:
		return
	if i < 0 or i >= main.owned_spells.size():
		return
	var w: WeaponData = main.current_weapon
	if w == null:
		return
	_normalize_slots(w)
	if selected_slot >= w.slot_count:
		return
	w.slots[selected_slot] = main.owned_spells[i]
	refresh()

func _on_clear_slot() -> void:
	if selected_slot < 0:
		return
	var w: WeaponData = main.current_weapon
	if w == null:
		return
	_normalize_slots(w)
	if selected_slot >= w.slot_count:
		return
	w.slots[selected_slot] = null
	refresh()
	
