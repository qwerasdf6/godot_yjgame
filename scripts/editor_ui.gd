extends Control

var main: MainNode = null
var container: VBoxContainer = null
# 选中槽位：0 = 插件槽，1 = 增益槽
var selected_kind: int = -1
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
		if w == null:
				return
		_normalize_slots(w)
		if selected_kind == 0 and selected_slot >= w.slot_count:
				selected_slot = -1
		elif selected_kind == 1 and selected_slot >= w.mod_slot_count:
				selected_slot = -1

		var title := Label.new()
		title.text = "武器编辑系统   (E / Esc 关闭)"
		title.add_theme_font_size_override("font_size", 20)
		container.add_child(title)

		var info := Label.new()
		info.text = "%s   |   插件槽 %d  增益槽 %d  |   释放冷却 %.2fs" % [
				w.weapon_name, w.slot_count, w.mod_slot_count, w.cast_delay]
		container.add_child(info)

		var hint := Label.new()
		hint.text = "插件槽放投射物（1-2 个），增益槽放修正（作用于全部投射物）"
		container.add_child(hint)

		container.add_child(_spacer(6))

		# ---- 插件槽 ----
		var plug_label := Label.new()
		plug_label.text = "插件技能槽（投射物）:"
		container.add_child(plug_label)
		var plug_grid := _make_grid()
		container.add_child(plug_grid)
		for i in w.slot_count:
				plug_grid.add_child(_make_slot_button(w.slots[i], i, 0))

		container.add_child(_spacer(6))

		# ---- 增益槽 ----
		var mod_label := Label.new()
		mod_label.text = "增益技能槽（全局修正）:"
		container.add_child(mod_label)
		var mod_grid := _make_grid()
		container.add_child(mod_grid)
		for i in w.mod_slot_count:
				mod_grid.add_child(_make_slot_button(w.mod_slots[i], i, 1))

		container.add_child(_spacer(10))

		var clear_btn := Button.new()
		clear_btn.text = "清理选中槽位"
		clear_btn.custom_minimum_size = Vector2(0, 46)
		clear_btn.add_theme_font_size_override("font_size", 18)
		clear_btn.focus_mode = Control.FOCUS_NONE
		clear_btn.disabled = selected_slot < 0
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
		_widen_scrollbar(scroll)

		var spell_list := VBoxContainer.new()
		spell_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		scroll.add_child(spell_list)

		for i in main.owned_spells.size():
				var s: SpellData = main.owned_spells[i]
				var btn := Button.new()
				var prefix := "[插件] " if s.type == SpellData.Type.PROJECTILE else "[增益]  "
				btn.text = "%s%s" % [prefix, s.spell_name]
				# 未选中槽位或类型不匹配时禁用
				var is_proj := s.type == SpellData.Type.PROJECTILE
				btn.disabled = selected_slot < 0 or (selected_kind == 0) != is_proj
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

func _make_grid() -> GridContainer:
		var grid := GridContainer.new()
		grid.columns = SLOT_COLUMNS
		grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_theme_constant_override("h_separation", 6)
		grid.add_theme_constant_override("v_separation", 6)
		return grid

func _make_slot_button(s: SpellData, i: int, kind: int) -> Button:
		var btn := Button.new()
		var base_text := "%d: %s" % [i + 1, s.spell_name if s else "(无)"]
		if kind == selected_kind and i == selected_slot:
				btn.text = "▶ " + base_text
				btn.modulate = Color(1.0, 1.0, 0.8)
		else:
				btn.text = base_text
		btn.custom_minimum_size = Vector2(0, 52)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.add_theme_font_size_override("font_size", 18)
		btn.focus_mode = Control.FOCUS_NONE
		btn.pressed.connect(_on_slot_selected.bind(kind, i))
		return btn

func _spacer(h: int) -> Control:
		var c := Control.new()
		c.custom_minimum_size = Vector2(0, h)
		return c

# 保证两类槽位数组长度与计数一致
func _normalize_slots(w: WeaponData) -> void:
		while w.slots.size() < w.slot_count:
				w.slots.append(null)
		while w.mod_slots.size() < w.mod_slot_count:
				w.mod_slots.append(null)

func _widen_scrollbar(scroll: ScrollContainer) -> void:
		var vbar := scroll.get_v_scroll_bar()
		if vbar != null:
				vbar.custom_minimum_size = Vector2(SCROLLBAR_WIDTH, 0)

func _on_slot_selected(kind: int, i: int) -> void:
		# 再次点击同槽位取消选中
		if selected_kind == kind and selected_slot == i:
				selected_kind = -1
				selected_slot = -1
		else:
				selected_kind = kind
				selected_slot = i
		refresh()

func _on_spell_pick(i: int) -> void:
		if selected_slot < 0 or selected_kind < 0:
				return
		if i < 0 or i >= main.owned_spells.size():
				return
		var w: WeaponData = main.current_weapon
		if w == null:
				return
		_normalize_slots(w)
		var s: SpellData = main.owned_spells[i]
		var is_proj := s.type == SpellData.Type.PROJECTILE
		# 类型必须与槽位匹配：插件槽只收投射物，增益槽只收修正
		if (selected_kind == 0) != is_proj:
				return
		var arr: Array = w.slots if selected_kind == 0 else w.mod_slots
		if selected_slot >= arr.size():
				return
		arr[selected_slot] = s
		refresh()

func _on_clear_slot() -> void:
		if selected_slot < 0 or selected_kind < 0:
				return
		var w: WeaponData = main.current_weapon
		if w == null:
				return
		_normalize_slots(w)
		var arr: Array = w.slots if selected_kind == 0 else w.mod_slots
		if selected_slot >= arr.size():
				return
		arr[selected_slot] = null
		refresh()
