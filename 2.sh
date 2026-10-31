#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="${1:-.}"
cd "$PROJECT_DIR"

if [ ! -f "project.godot" ]; then
  echo "❌ project.godot not found in $(pwd)"
  echo "   Usage: ./fix_hits.sh [project_dir]"
  exit 1
fi

# ---------------------------------------------------------------- bullet.gd
cat > scripts/bullet.gd <<'EOF'
class_name Bullet
extends Sprite2D

var velocity: Vector2 = Vector2.ZERO
var damage: float = 10.0
var lifetime: float = 2.0
var active: bool = false
var prev_position: Vector2 = Vector2.ZERO
var pool = null

func spawn(pos: Vector2, vel: Vector2, dmg: float, life: float, color: Color, owner_pool) -> void:
	global_position = pos
	prev_position = pos
	velocity = vel
	damage = dmg
	lifetime = life
	modulate = color
	pool = owner_pool
	active = true
	visible = true
	set_process(true)

func _process(delta: float) -> void:
	if not active:
		return
	prev_position = global_position
	global_position += velocity * delta
	lifetime -= delta
	if lifetime <= 0.0:
		pool.recycle(self)
EOF
echo "✅ scripts/bullet.gd"

# ---------------------------------------------------------------- main.gd
cat > scripts/main.gd <<'EOF'
class_name MainNode
extends Node2D

enum UIState { NONE, SHOP, EDITOR }

const HIT_RADIUS := 18.0
const HIT_RADIUS_SQ := HIT_RADIUS * HIT_RADIUS

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

var debug_hits: int = 0

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

func _physics_process(_delta: float) -> void:
	_resolve_collisions()

func _resolve_collisions() -> void:
	if get_tree().paused:
		return
	var snapshot: Array[Bullet] = bullet_pool.get_active().duplicate()
	if snapshot.is_empty():
		return
	var enemy_nodes := enemy_container.get_children()
	if enemy_nodes.is_empty():
		return

	for i in range(snapshot.size() - 1, -1, -1):
		var b: Bullet = snapshot[i]
		if not b.active:
			continue
		var p0 := b.prev_position
		var p1 := b.global_position
		for node in enemy_nodes:
			var e := node as Enemy
			if e == null or e.dead:
				continue
			if _segment_intersects_circle(p0, p1, e.global_position, HIT_RADIUS_SQ):
				e.take_damage(b.damage)
				debug_hits += 1
				bullet_pool.recycle(b)
				break

# 线段 p0->p1 与圆(center, radius) 是否相交
func _segment_intersects_circle(p0: Vector2, p1: Vector2, center: Vector2, radius_sq: float) -> bool:
	var d := p1 - p0
	var f := p0 - center
	var a := d.dot(d)
	if a < 0.0001:
		return f.length_squared() <= radius_sq
	var b := 2.0 * f.dot(d)
	var c := f.length_squared() - radius_sq
	var disc := b * b - 4.0 * a * c
	if disc < 0.0:
		return c <= 0.0
	var sq := sqrt(disc)
	var inv := 1.0 / (2.0 * a)
	var t1 := (-b - sq) * inv
	var t2 := (-b + sq) * inv
	return (t1 >= 0.0 and t1 <= 1.0) or (t2 >= 0.0 and t2 <= 1.0)

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
		elif key.keycode == KEY_F3:
			debug_hits = 0

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
	var bullets := main.bullet_pool.get_active().size()
	var enemies := main.enemy_container.get_child_count()
	var fps := Engine.get_frames_per_second()
	var touch_state := "ON" if main.touch_controls.enabled else "OFF"
	label.text = "Time %02d:%02d    $%d    Rate %.1f/s\nHP %d/%d    Weapon: %s\nBullets %d  Enemies %d  FPS %d  Hits %d  Touch[%s]" % [
		mm, ss, int(main.currency), main.rate,
		hp, int(main.player.max_hp), wname,
		bullets, enemies, fps, main.debug_hits, touch_state
	]
EOF
echo "✅ scripts/hud.gd"

echo ""
echo "============================================"
echo "✅ Fixed. Changes:"
echo "  • bullet.gd   → tracks prev_position every frame"
echo "  • main.gd     → line-segment vs circle detection"
echo "                  (no more tunneling at low FPS)"
echo "                  + snapshot of active list before looping"
echo "                  + debug_hits counter (F3 resets it)"
echo "  • hud.gd      → shows Bullets / Enemies / FPS / Hits / Touch"
echo ""
echo "If monsters still don't die, look at the HUD:"
echo "  1. Bullets > 0?              → yes = bullets are spawning"
echo "  2. Hits increasing over time? → no = collision is failing"
echo "  3. FPS very low (<20)?        → yes = reduce bullet_speed"
echo "                                   in weapon.gd, or raise the"
echo "                                   18.0 radius in main.gd"
echo "  4. Touch[ON] while on desktop?→ press F2 to turn it off"
echo "============================================"