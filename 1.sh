#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="${1:-.}"
cd "$PROJECT_DIR"

if [ ! -f "project.godot" ]; then
  echo "❌ project.godot not found in $(pwd)"
  echo "   Usage: ./apply_touch.sh [project_dir]"
  exit 1
fi

mkdir -p scripts scenes

# ---------------------------------------------------------------- touch_controls.gd
cat > scripts/touch_controls.gd <<'EOF'
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
EOF
echo "✅ scripts/touch_controls.gd"

# ---------------------------------------------------------------- player.gd
cat > scripts/player.gd <<'EOF'
class_name Player
extends CharacterBody2D

signal died

@export var move_speed: float = 220.0

var max_hp: float = 100.0
var hp: float = 100.0
var invuln_timer: float = 0.0
var touch_controls = null

func _physics_process(_delta: float) -> void:
	var input_vec := Vector2.ZERO
	if touch_controls != null and touch_controls.enabled:
		input_vec = touch_controls.move_vector
	else:
		input_vec = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	velocity = input_vec * move_speed
	move_and_slide()

func _process(delta: float) -> void:
	if invuln_timer > 0.0:
		invuln_timer -= delta
		modulate.a = 0.4 if int(invuln_timer * 20.0) % 2 == 0 else 1.0
	else:
		modulate.a = 1.0

func take_damage(amount: float) -> void:
	if invuln_timer > 0.0 or hp <= 0.0:
		return
	hp -= amount
	invuln_timer = 0.5
	if hp <= 0.0:
		hp = 0.0
		died.emit()
EOF
echo "✅ scripts/player.gd"

# ---------------------------------------------------------------- weapon.gd
cat > scripts/weapon.gd <<'EOF'
class_name Weapon
extends Node2D

var main: Node = null
var bullet_pool: BulletPool = null
var weapon_data: WeaponData = null
var touch_controls = null
var _cooldown: float = 0.0

func setup(main_node: Node, pool: BulletPool, data: WeaponData) -> void:
	main = main_node
	bullet_pool = pool
	weapon_data = data
	_cooldown = 0.0

func set_weapon(data: WeaponData) -> void:
	weapon_data = data
	_cooldown = 0.0

func _process(delta: float) -> void:
	if weapon_data == null or bullet_pool == null:
		return
	_cooldown -= delta
	if _cooldown <= 0.0:
		_cooldown = weapon_data.cast_delay
		_cast()

func _cast() -> void:
	var aim := _get_aim_direction()
	if aim == Vector2.ZERO:
		return
	var pending_mods: Array[SpellData] = []
	for i in weapon_data.slot_count:
		var s: SpellData = null
		if i < weapon_data.slots.size():
			s = weapon_data.slots[i]
		if s == null:
			continue
		if s.type == SpellData.Type.MODIFIER:
			pending_mods.append(s)
		else:
			_fire_projectile(s, pending_mods, aim)
			pending_mods.clear()

func _get_aim_direction() -> Vector2:
	if touch_controls != null and touch_controls.enabled:
		if not touch_controls.is_firing:
			return Vector2.ZERO
		return touch_controls.aim_vector.normalized()
	var d := get_global_mouse_position() - global_position
	if d.length_squared() < 1.0:
		return Vector2.RIGHT
	return d.normalized()

func _fire_projectile(spell: SpellData, mods: Array[SpellData], dir: Vector2) -> void:
	var dmg := spell.damage
	var spd := spell.speed
	var cnt := spell.count
	var spr := spell.spread
	var col := spell.color

	for m in mods:
		dmg *= m.modifier_damage_mult
		spd *= m.modifier_speed_mult
		cnt += m.modifier_count_add

	var base_angle := dir.angle()
	for i in cnt:
		var offset := 0.0
		if cnt > 1 and spr > 0.0:
			offset = (i - (cnt - 1) / 2.0) * spr
		var a := base_angle + offset
		bullet_pool.spawn(global_position, Vector2.from_angle(a) * spd, dmg, 2.0, col)
EOF
echo "✅ scripts/weapon.gd"

# ---------------------------------------------------------------- main.gd
cat > scripts/main.gd <<'EOF'
class_name MainNode
extends Node2D

enum UIState { NONE, SHOP, EDITOR }

@onready var player: Player = $Player
@onready var bullet_pool: BulletPool = $BulletPool
@onready var enemy_container: Node2D = $EnemyContainer
@onready var spawner: Spawner = $Spawner
@onready var weapon: Weapon = $Player/Weapon
@onready var hud: Control = $UILayer/HUD
@onready var shop_ui: Control = $UILayer/ShopUI
@onready var editor_ui: Control = $UILayer/EditorUI
@onready var game_over_ui: Control = $UILayer/GameOverUI
@onready var touch_controls: Control = $UILayer/TouchControls

var currency: float = 100.0
var elapsed: float = 0.0
var rate: float = 1.5
var accum: float = 0.0
var game_over: bool = false
var ui_state: UIState = UIState.NONE

var current_weapon: WeaponData
var owned_spells: Array[SpellData] = []

var shop_spells: Array[SpellData] = []
var shop_spell_prices: Array[int] = []
var shop_weapons: Array[WeaponData] = []
var shop_weapon_prices: Array[int] = []

func _ready() -> void:
	_init_loadout()
	_init_shop()
	spawner.setup(self, player, enemy_container)
	weapon.setup(self, bullet_pool, current_weapon)
	hud.setup(self)
	shop_ui.setup(self)
	editor_ui.setup(self)
	game_over_ui.setup(self)
	player.died.connect(_on_player_died)
	player.touch_controls = touch_controls
	weapon.touch_controls = touch_controls
	_apply_ui_state(UIState.NONE)

func _init_loadout() -> void:
	var basic := Catalogs.make_projectile("基础弹", 10.0, 500.0, 1, 0.0, Color(1, 0.9, 0.3))
	owned_spells.append(basic)
	current_weapon = Catalogs.make_weapon("基础枪", 3, 0.15)
	current_weapon.slots[0] = basic

func _init_shop() -> void:
	shop_spells.append(Catalogs.make_projectile("散弹", 6.0, 450.0, 3, 0.3, Color(0.3, 1.0, 0.6)))
	shop_spell_prices.append(80)
	shop_spells.append(Catalogs.make_projectile("重弹", 25.0, 350.0, 1, 0.0, Color(1.0, 0.4, 0.4)))
	shop_spell_prices.append(100)
	shop_spells.append(Catalogs.make_modifier("伤害强化", 1.5, 1.0, 0))
	shop_spell_prices.append(60)
	shop_spells.append(Catalogs.make_modifier("加速修正", 1.0, 1.4, 0))
	shop_spell_prices.append(50)
	shop_spells.append(Catalogs.make_modifier("多重+1", 1.0, 1.0, 1))
	shop_spell_prices.append(120)

	shop_weapons.append(Catalogs.make_weapon("加长枪", 5, 0.15))
	shop_weapon_prices.append(150)
	shop_weapons.append(Catalogs.make_weapon("快枪", 3, 0.08))
	shop_weapon_prices.append(200)

func _process(delta: float) -> void:
	if game_over or get_tree().paused:
		return
	elapsed += delta
	rate = min(3.0, 1.5 + elapsed * 0.005)
	accum += delta * rate
	while accum >= 1.0:
		accum -= 1.0
		currency += 1.0
	_check_contact()

func _check_contact() -> void:
	for node in enemy_container.get_children():
		var e := node as Enemy
		if e == null or e.dead:
			continue
		if player.global_position.distance_squared_to(e.global_position) < 24.0 * 24.0:
			player.take_damage(10.0)
			return

func _unhandled_input(event: InputEvent) -> void:
	if game_over:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var key := event as InputEventKey
		if key.keycode == KEY_TAB:
			toggle_shop()
			get_viewport().set_input_as_handled()
		elif key.keycode == KEY_E:
			toggle_editor()
			get_viewport().set_input_as_handled()
		elif key.keycode == KEY_ESCAPE and ui_state != UIState.NONE:
			_apply_ui_state(UIState.NONE)
			get_viewport().set_input_as_handled()
		elif key.keycode == KEY_F2:
			touch_controls.set_enabled(not touch_controls.enabled)
			get_viewport().set_input_as_handled()

func toggle_shop() -> void:
	_toggle_ui(UIState.SHOP)

func toggle_editor() -> void:
	_toggle_ui(UIState.EDITOR)

func _toggle_ui(target: UIState) -> void:
	if ui_state == target:
		_apply_ui_state(UIState.NONE)
	else:
		_apply_ui_state(target)

func _apply_ui_state(state: UIState) -> void:
	ui_state = state
	shop_ui.visible = state == UIState.SHOP
	editor_ui.visible = state == UIState.EDITOR
	get_tree().paused = state != UIState.NONE
	if state == UIState.SHOP:
		shop_ui.refresh()
	elif state == UIState.EDITOR:
		editor_ui.refresh()

func buy_spell(index: int) -> void:
	if index < 0 or index >= shop_spells.size():
		return
	var price := shop_spell_prices[index]
	if currency < price:
		return
	currency -= price
	owned_spells.append(shop_spells[index])
	shop_spells.remove_at(index)
	shop_spell_prices.remove_at(index)

func buy_weapon(index: int) -> void:
	if index < 0 or index >= shop_weapons.size():
		return
	var price := shop_weapon_prices[index]
	if currency < price:
		return
	currency -= price
	var new_weapon: WeaponData = shop_weapons[index].duplicate(true)
	for s in current_weapon.slots:
		if s != null and not owned_spells.has(s):
			owned_spells.append(s)
	current_weapon = new_weapon
	weapon.set_weapon(current_weapon)
	shop_weapons.remove_at(index)
	shop_weapon_prices.remove_at(index)

func get_difficulty_mult() -> float:
	return clamp(pow(1.15, elapsed / 60.0), 1.0, 10.0)

func _on_player_died() -> void:
	game_over = true
	get_tree().paused = true
	game_over_ui.visible = true
	game_over_ui.refresh()

func restart() -> void:
	get_tree().paused = false
	get_tree().reload_current_scene()
EOF
echo "✅ scripts/main.gd"

# ---------------------------------------------------------------- hud.gd
cat > scripts/hud.gd <<'EOF'
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

	shop_btn = _make_button("Shop", -280, -150)
	shop_btn.pressed.connect(func(): main.toggle_shop())
	add_child(shop_btn)

	editor_btn = _make_button("Editor", -140, -10)
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
	label.text = "Time %02d:%02d    $%d    Rate %.1f/s\nHP %d/%d    Weapon: %s\n[Tab] Shop    [E] Editor    [F2] Touch debug" % [
		mm, ss, int(main.currency), main.rate,
		hp, int(main.player.max_hp), wname
	]
EOF
echo "✅ scripts/hud.gd"

# ---------------------------------------------------------------- shop_ui.gd
cat > scripts/shop_ui.gd <<'EOF'
extends Control

var main: MainNode = null
var container: VBoxContainer = null

func setup(m: MainNode) -> void:
	main = m
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.7)
	bg.size = Vector2(1152, 648)
	bg.position = Vector2.ZERO
	add_child(bg)

	var panel := Panel.new()
	panel.size = Vector2(620, 520)
	panel.position = Vector2((1152 - 620) / 2.0, (648 - 520) / 2.0)
	add_child(panel)

	container = VBoxContainer.new()
	container.position = Vector2(20, 20)
	container.size = Vector2(580, 480)
	container.add_theme_constant_override("separation", 6)
	panel.add_child(container)

func refresh() -> void:
	for c in container.get_children():
		c.queue_free()

	var title := Label.new()
	title.text = "SHOP    (Tab / Esc to close)"
	title.add_theme_font_size_override("font_size", 20)
	container.add_child(title)

	var cur := Label.new()
	cur.text = "Currency: $%d" % int(main.currency)
	container.add_child(cur)

	container.add_child(_spacer(6))

	var h1 := Label.new()
	h1.text = "— Spells —"
	container.add_child(h1)

	if main.shop_spells.is_empty():
		var e := Label.new()
		e.text = "  (all spells purchased)"
		container.add_child(e)
	else:
		for i in main.shop_spells.size():
			var s: SpellData = main.shop_spells[i]
			var price: int = main.shop_spell_prices[i]
			var btn := Button.new()
			var prefix := "[PROJ] " if s.type == SpellData.Type.PROJECTILE else "[MOD]  "
			btn.text = "%s%s    $%d" % [prefix, s.spell_name, price]
			btn.custom_minimum_size = Vector2(0, 52)
			btn.add_theme_font_size_override("font_size", 18)
			btn.disabled = main.currency < price
			btn.focus_mode = Control.FOCUS_NONE
			btn.pressed.connect(_on_buy_spell.bind(i))
			container.add_child(btn)

	container.add_child(_spacer(6))

	var h2 := Label.new()
	h2.text = "— Weapons —"
	container.add_child(h2)

	if main.shop_weapons.is_empty():
		var e := Label.new()
		e.text = "  (all weapons purchased)"
		container.add_child(e)
	else:
		for i in main.shop_weapons.size():
			var w: WeaponData = main.shop_weapons[i]
			var price: int = main.shop_weapon_prices[i]
			var btn := Button.new()
			btn.text = "%s    (%d slots, %.2fs)    $%d" % [w.weapon_name, w.slot_count, w.cast_delay, price]
			btn.custom_minimum_size = Vector2(0, 52)
			btn.add_theme_font_size_override("font_size", 18)
			btn.disabled = main.currency < price
			btn.focus_mode = Control.FOCUS_NONE
			btn.pressed.connect(_on_buy_weapon.bind(i))
			container.add_child(btn)

	var close_btn := Button.new()
	close_btn.text = "Close"
	close_btn.custom_minimum_size = Vector2(0, 52)
	close_btn.add_theme_font_size_override("font_size", 18)
	close_btn.focus_mode = Control.FOCUS_NONE
	close_btn.pressed.connect(func(): main._apply_ui_state(MainNode.UIState.NONE))
	container.add_child(close_btn)

func _spacer(h: int) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	return c

func _on_buy_spell(i: int) -> void:
	main.buy_spell(i)
	refresh()

func _on_buy_weapon(i: int) -> void:
	main.buy_weapon(i)
	refresh()
EOF
echo "✅ scripts/shop_ui.gd"

# ---------------------------------------------------------------- editor_ui.gd
cat > scripts/editor_ui.gd <<'EOF'
extends Control

var main: MainNode = null
var container: VBoxContainer = null
var selected_slot: int = -1

func setup(m: MainNode) -> void:
	main = m
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.7)
	bg.size = Vector2(1152, 648)
	bg.position = Vector2.ZERO
	add_child(bg)

	var panel := Panel.new()
	panel.size = Vector2(660, 560)
	panel.position = Vector2((1152 - 660) / 2.0, (648 - 560) / 2.0)
	add_child(panel)

	container = VBoxContainer.new()
	container.position = Vector2(20, 20)
	container.size = Vector2(620, 520)
	container.add_theme_constant_override("separation", 6)
	panel.add_child(container)

func refresh() -> void:
	for c in container.get_children():
		c.queue_free()

	var w: WeaponData = main.current_weapon
	if w != null and selected_slot >= w.slot_count:
		selected_slot = -1

	var title := Label.new()
	title.text = "WEAPON EDITOR    (E / Esc to close)"
	title.add_theme_font_size_override("font_size", 20)
	container.add_child(title)

	if w == null:
		return

	var info := Label.new()
	info.text = "%s   |   Slots %d   |   Cast delay %.2fs" % [w.weapon_name, w.slot_count, w.cast_delay]
	container.add_child(info)

	var hint := Label.new()
	hint.text = "1) tap a slot   2) tap a spell below to place"
	container.add_child(hint)

	container.add_child(_spacer(6))

	var slot_row := HBoxContainer.new()
	slot_row.add_theme_constant_override("separation", 6)
	container.add_child(slot_row)
	for i in w.slot_count:
		var s: SpellData = w.slots[i] if i < w.slots.size() else null
		var btn := Button.new()
		btn.text = "%d: %s" % [i + 1, s.spell_name if s else "(empty)"]
		btn.custom_minimum_size = Vector2(120, 52)
		btn.add_theme_font_size_override("font_size", 18)
		btn.focus_mode = Control.FOCUS_NONE
		if i == selected_slot:
			btn.modulate = Color(1.0, 1.0, 0.5)
		btn.pressed.connect(_on_slot_selected.bind(i))
		slot_row.add_child(btn)

	container.add_child(_spacer(10))

	var clear_btn := Button.new()
	clear_btn.text = "Clear selected slot"
	clear_btn.custom_minimum_size = Vector2(0, 46)
	clear_btn.add_theme_font_size_override("font_size", 18)
	clear_btn.focus_mode = Control.FOCUS_NONE
	clear_btn.pressed.connect(_on_clear_slot)
	container.add_child(clear_btn)

	container.add_child(_spacer(6))

	var spell_label := Label.new()
	spell_label.text = "Owned spells:"
	container.add_child(spell_label)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(0, 200)
	container.add_child(scroll)

	var spell_list := VBoxContainer.new()
	spell_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(spell_list)

	for i in main.owned_spells.size():
		var s: SpellData = main.owned_spells[i]
		var btn := Button.new()
		var prefix := "[PROJ] " if s.type == SpellData.Type.PROJECTILE else "[MOD]  "
		btn.text = "%s%s" % [prefix, s.spell_name]
		btn.custom_minimum_size = Vector2(0, 46)
		btn.add_theme_font_size_override("font_size", 18)
		btn.focus_mode = Control.FOCUS_NONE
		btn.pressed.connect(_on_spell_pick.bind(i))
		spell_list.add_child(btn)

	container.add_child(_spacer(6))

	var close_btn := Button.new()
	close_btn.text = "Close"
	close_btn.custom_minimum_size = Vector2(0, 52)
	close_btn.add_theme_font_size_override("font_size", 18)
	close_btn.focus_mode = Control.FOCUS_NONE
	close_btn.pressed.connect(func(): main._apply_ui_state(MainNode.UIState.NONE))
	container.add_child(close_btn)

func _spacer(h: int) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	return c

func _on_slot_selected(i: int) -> void:
	selected_slot = i
	refresh()

func _on_spell_pick(i: int) -> void:
	if selected_slot < 0:
		return
	var w: WeaponData = main.current_weapon
	if w == null or selected_slot >= w.slots.size():
		return
	w.slots[selected_slot] = main.owned_spells[i]
	refresh()

func _on_clear_slot() -> void:
	if selected_slot < 0:
		return
	var w: WeaponData = main.current_weapon
	if w == null or selected_slot >= w.slots.size():
		return
	w.slots[selected_slot] = null
	refresh()
EOF
echo "✅ scripts/editor_ui.gd"

# ---------------------------------------------------------------- Main.tscn
cat > scenes/Main.tscn <<'EOF'
[gd_scene load_steps=10 format=3]

[ext_resource type="Script" path="res://scripts/main.gd" id="1_main"]
[ext_resource type="PackedScene" path="res://scenes/Player.tscn" id="2_player"]
[ext_resource type="Script" path="res://scripts/bullet_pool.gd" id="3_pool"]
[ext_resource type="Script" path="res://scripts/spawner.gd" id="4_spawner"]
[ext_resource type="Script" path="res://scripts/hud.gd" id="5_hud"]
[ext_resource type="Script" path="res://scripts/shop_ui.gd" id="6_shop"]
[ext_resource type="Script" path="res://scripts/editor_ui.gd" id="7_editor"]
[ext_resource type="Script" path="res://scripts/game_over_ui.gd" id="8_over"]
[ext_resource type="Script" path="res://scripts/touch_controls.gd" id="9_touch"]

[node name="Main" type="Node2D"]
process_mode = 3
script = ExtResource("1_main")

[node name="Player" parent="." instance=ExtResource("2_player")]
position = Vector2(576, 324)

[node name="BulletPool" type="Node2D" parent="."]
process_mode = 1
script = ExtResource("3_pool")

[node name="EnemyContainer" type="Node2D" parent="."]
process_mode = 1

[node name="Spawner" type="Node" parent="."]
process_mode = 1
script = ExtResource("4_spawner")

[node name="UILayer" type="CanvasLayer" parent="."]

[node name="TouchControls" type="Control" parent="UILayer"]
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
grow_horizontal = 2
grow_vertical = 2
mouse_filter = 2
script = ExtResource("9_touch")

[node name="HUD" type="Control" parent="UILayer"]
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
grow_horizontal = 2
grow_vertical = 2
script = ExtResource("5_hud")

[node name="ShopUI" type="Control" parent="UILayer"]
visible = false
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
grow_horizontal = 2
grow_vertical = 2
script = ExtResource("6_shop")

[node name="EditorUI" type="Control" parent="UILayer"]
visible = false
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
grow_horizontal = 2
grow_vertical = 2
script = ExtResource("7_editor")

[node name="GameOverUI" type="Control" parent="UILayer"]
visible = false
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
grow_horizontal = 2
grow_vertical = 2
script = ExtResource("8_over")
EOF
echo "✅ scenes/Main.tscn"

# ---------------------------------------------------------------- project.godot (Python)
if command -v python3 >/dev/null 2>&1; then
python3 - <<'PY'
import re
p = "project.godot"
txt = open(p).read()

def ensure(txt, section, kv):
    header = f"[{section}]"
    if header in txt:
        pattern = re.compile(
            rf"^({re.escape(header)}[^[]*?)(?=^\[|\Z)",
            re.M | re.S,
        )
        m = pattern.search(txt)
        if m:
            body = m.group(1)
            for k, v in kv.items():
                line = f"{k}={v}"
                if re.search(rf"^{re.escape(k)}=.*$", body, re.M):
                    body = re.sub(rf"^{re.escape(k)}=.*$", line, body, flags=re.M)
                else:
                    if not body.endswith("\n"):
                        body += "\n"
                    body += line + "\n"
            txt = txt[:m.start()] + body + txt[m.end():]
    else:
        if not txt.endswith("\n"):
            txt += "\n"
        txt += header + "\n"
        for k, v in kv.items():
            txt += f"{k}={v}\n"
    return txt

txt = ensure(txt, "display", {
    "window/handheld/orientation": "1",
})
txt = ensure(txt, "input_devices", {
    "pointing/emulate_mouse_from_touch": "true",
    "pointing/emulate_touch_from_mouse": "true",
})
open(p, "w").write(txt)
print("✅ project.godot")
PY
else
  echo "⚠️  python3 not found — please add these manually to project.godot:"
  echo "   [display]"
  echo "   window/handheld/orientation=1"
  echo "   [input_devices]"
  echo "   pointing/emulate_mouse_from_touch=true"
  echo "   pointing/emulate_touch_from_mouse=true"
fi

echo ""
echo "============================================"
echo "✅ Touch support applied to: $(pwd)"
echo ""
echo "Next:"
echo "  • Open the project in Godot and press F5."
echo "  • Desktop: WASD / mouse as usual."
echo "  • Press F2 in-game to toggle touch mode on desktop"
echo "    (mouse-drag simulates dual sticks)."
echo "  • Mobile: touch mode enables automatically; top-right"
echo "    'Shop' / 'Editor' buttons are always tappable."
echo "============================================"