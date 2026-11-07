class_name MainNode
extends Node2D

enum UIState { NONE, SHOP, EDITOR }

const HIT_RADIUS := 18.0
const HIT_RADIUS_SQ := HIT_RADIUS * HIT_RADIUS
const CONTACT_RADIUS := 24.0
const CONTACT_RADIUS_SQ := CONTACT_RADIUS * CONTACT_RADIUS

# 商店随机上架开关：true 时从池中随机抽货，购买后下次开店补货；
# false 时所有池内物品一次性全部上架。
const RANDOM_SHOP := true
const SPELL_STOCK_COUNT := 4
const WEAPON_STOCK_COUNT := 2

# ---- 联机 ----
const MP_PLAYER_SCENE := preload("res://scenes/Player.tscn")
const MP_ENEMY_SCENE := preload("res://scenes/Enemy.tscn")
const MP_SNAPSHOT_INTERVAL := 0.1   # 快照频率 10Hz

# 货币成长曲线：起步 2/s，每 60 秒 +1/s，封顶 15/s
const CURRENCY_RATE_BASE := 2.0
const CURRENCY_RATE_CAP := 15.0

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

# 当前上架列表（ShopUI 读取这两个数组）
var shop_spells: Array[SpellData] = []
var shop_spell_prices: Array[int] = []
var shop_weapons: Array[WeaponData] = []
var shop_weapon_prices: Array[int] = []

# 未上架的库存池
var spell_pool: Array[SpellData] = []
var spell_price_pool: Array[int] = []
var weapon_pool: Array[WeaponData] = []
var weapon_price_pool: Array[int] = []

# 调试用：F3 重置
var debug_hits: int = 0

# ---- 联机状态 ----
var _mp_snap_timer: float = 0.0
var _mp_next_enemy_id: int = 1
var _mp_enemy_ids: Dictionary = {}        # 主机：Enemy实例 -> 网络id
var _mp_remote_players: Dictionary = {}   # 主机：peer_id -> Player分身
var _mp_remote_weapons: Dictionary = {}   # 主机：peer_id -> Weapon分身
var _mp_remote_weapon_data: Dictionary = {}  # 主机：peer_id -> WeaponData（远程玩家的武器数据）
var _mp_client_enemies: Dictionary = {}    # 客户端：网络id -> Enemy渲染实例
var _mp_client_avatars: Dictionary = {}   # 客户端：槽位号 -> 其他玩家分身
var _mp_connected: bool = false           # 客户端：收到首个快照后置真
# 玩家用槽位号标识（不用 peer id：PackedFloat32Array 精度只有 24 位，
# 大整数的 peer id 传入快照会被舍入，导致客户端无法识别"哪条数据是自己"）
var _mp_player_slots: Dictionary = {}     # 主机：peer_id -> 槽位号（1,2,3…）
var _mp_next_slot: int = 1
var _mp_my_slot: int = -1                # 客户端：自己的槽位号（收到 mp_assign_slot 前为 -1）

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
		if Net.is_host():
				_mp_host_ready()
		elif Net.is_client():
				_mp_client_ready()

func _init_loadout() -> void:
		# 成长曲线调整：初始武器强度下调，避免前期无双
		var basic := Catalogs.make_projectile("鸡弹", 7.0, 500.0, 1, 0.0, Color(1, 0.9, 0.3))
		owned_spells.append(basic)
		current_weapon = Catalogs.make_weapon("小鸡枪", 2, 0.20)
		current_weapon.slots[0] = basic

func _init_shop() -> void:
		# ---- 投射物 ----
		_add_spell(Catalogs.make_projectile("散弹", 4.0, 450.0, 3, 0.3, Color(0.3, 1.0, 0.6)), 80)
		_add_spell(Catalogs.make_projectile("重弹", 25.0, 350.0, 1, 0.0, Color(1.0, 0.4, 0.4)), 100)
		_add_spell(Catalogs.make_projectile("蛋壳弹", 8.0, 420.0, 2, 0.15, Color(0.95, 0.93, 0.85)), 70)
		_add_spell(Catalogs.make_projectile("鸡喙刺", 15.0, 700.0, 1, 0.0, Color(1.0, 0.55, 0.1)), 90)
		_add_spell(Catalogs.make_projectile("羽毛扇", 5.0, 600.0, 5, 0.5, Color(0.4, 0.95, 0.95)), 110)
		_add_spell(Catalogs.make_projectile("咯咯散", 3.0, 380.0, 6, 0.8, Color(1.0, 0.6, 0.85)), 100)

		# ---- 修正 ----
		_add_spell(Catalogs.make_modifier("伤害强化", 1.5, 1.0, 0), 60)
		_add_spell(Catalogs.make_modifier("加速修正", 1.0, 1.4, 0), 50)
		_add_spell(Catalogs.make_modifier("多重+1", 1.0, 1.0, 1), 120)
		_add_spell(Catalogs.make_modifier("锋利修正", 1.2, 1.2, 0), 70)
		_add_spell(Catalogs.make_modifier("狂速修正", 0.85, 1.8, 0), 60)
		_add_spell(Catalogs.make_modifier("多重+2", 0.8, 1.0, 2), 160)

		# ---- 武器 ----
		_add_weapon(Catalogs.make_weapon("中鸡枪", 5, 0.15), 150)
		_add_weapon(Catalogs.make_weapon("大鸡枪", 3, 0.08), 200)
		_add_weapon(Catalogs.make_weapon("连发鸡枪", 2, 0.06), 180)
		_add_weapon(Catalogs.make_weapon("鸡王炮", 6, 0.25), 260)
		_add_weapon(Catalogs.make_weapon("精确鸡枪", 1, 0.10), 140)
		_add_weapon(Catalogs.make_weapon("母鸡炮台", 8, 0.30), 320)

		if RANDOM_SHOP:
				_ensure_stock()
		else:
				shop_spells = spell_pool.duplicate()
				shop_spell_prices = spell_price_pool.duplicate()
				shop_weapons = weapon_pool.duplicate()
				shop_weapon_prices = weapon_price_pool.duplicate()

func _add_spell(s: SpellData, price: int) -> void:
		spell_pool.append(s)
		spell_price_pool.append(price)

func _add_weapon(w: WeaponData, price: int) -> void:
		weapon_pool.append(w)
		weapon_price_pool.append(price)

func _process(delta: float) -> void:
		if Net.is_client():
				_mp_client_process(delta)
				return
		if get_tree().paused:
				return
		elapsed += delta
		# 货币曲线：起步 2/s，每 60 秒 +1/s，封顶 15/s
		rate = min(CURRENCY_RATE_CAP, CURRENCY_RATE_BASE + elapsed / 60.0)
		accum += delta * rate
		while accum >= 1.0:
				accum -= 1.0
				currency += 1.0
		_check_contact()
		if Net.is_host():
				_mp_host_snapshot(delta)

func _physics_process(_delta: float) -> void:
		if Net.is_client():
				_mp_client_physics(_delta)
				return
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
						# 目前对所有敌人使用统一命中半径；
						# 若 Enemy 将来支持不同体型，可改为 e.hit_radius。
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
				# 直线不相交；若起点在圆内（如整段都在圆内）仍算命中
				return c <= 0.0
		var sq := sqrt(disc)
		var inv := 1.0 / (2.0 * a)
		var t1 := (-b - sq) * inv
		var t2 := (-b + sq) * inv
		return (t1 >= 0.0 and t1 <= 1.0) or (t2 >= 0.0 and t2 <= 1.0)

func _check_contact() -> void:
		# 主机上：本机玩家 + 所有远程玩家都可能被怪碰到
		var victims: Array = [player]
		for p in _mp_remote_players.values():
				if is_instance_valid(p):
						victims.append(p)
		for node in enemy_container.get_children():
				var e := node as Enemy
				if e == null or e.dead:
						continue
				for v in victims:
						if v.global_position.distance_squared_to(e.global_position) < CONTACT_RADIUS_SQ:
								v.take_damage(10.0)
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
		# 联机客户端：武器编辑由主机权威管理，客户端禁用
		if Net.is_client():
				return
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
		_sync_pause()
		if state == UIState.SHOP:
				_ensure_stock()
				shop_ui.refresh()
		elif state == UIState.EDITOR:
				editor_ui.refresh()

# 暂停状态统一入口：UI 打开或游戏结束时暂停
# 联机模式下不暂停整棵场景树（主机暂停会让所有玩家卡住），改为实时商店
func _sync_pause() -> void:
		if Net.is_active():
				get_tree().paused = false
				return
		get_tree().paused = (ui_state != UIState.NONE) or game_over

# 从库存池随机抽货补满货架（RANDOM_SHOP 为 true 时生效）
func _ensure_stock() -> void:
		if not RANDOM_SHOP:
				return
		while shop_spells.size() < SPELL_STOCK_COUNT and not spell_pool.is_empty():
				_draw_spell()
		while shop_weapons.size() < WEAPON_STOCK_COUNT and not weapon_pool.is_empty():
				_draw_weapon()

func _draw_spell() -> void:
		if spell_pool.is_empty():
				return
		var idx := randi() % spell_pool.size()
		shop_spells.append(spell_pool[idx])
		shop_spell_prices.append(spell_price_pool[idx])
		spell_pool.remove_at(idx)
		spell_price_pool.remove_at(idx)

func _draw_weapon() -> void:
		if weapon_pool.is_empty():
				return
		var idx := randi() % weapon_pool.size()
		shop_weapons.append(weapon_pool[idx])
		shop_weapon_prices.append(weapon_price_pool[idx])
		weapon_pool.remove_at(idx)
		weapon_price_pool.remove_at(idx)

func buy_spell(index: int) -> void:
		# 客户端：转发给主机结算
		if Net.is_client():
				mp_buy_spell.rpc_id(1, index)
				return
		if index < 0 or index >= shop_spells.size():
				return
		var price := shop_spell_prices[index]
		if currency < price:
				return
		currency -= price
		owned_spells.append(shop_spells[index])
		shop_spells.remove_at(index)
		shop_spell_prices.remove_at(index)
		if Net.is_host():
				mp_sync_shop.rpc(_mp_build_shop_payload())

func buy_weapon(index: int) -> void:
		# 客户端：转发给主机结算
		if Net.is_client():
				mp_buy_weapon.rpc_id(1, index)
				return
		if index < 0 or index >= shop_weapons.size():
				return
		var price := shop_weapon_prices[index]
		if currency < price:
				return
		currency -= price

		var new_weapon: WeaponData = shop_weapons[index].duplicate(true)

		# 先把旧武器槽中的法术收回 owned_spells
		for s in current_weapon.slots:
				if s != null and not owned_spells.has(s):
						owned_spells.append(s)

		# 再把旧武器槽里的法术按顺序填入新武器的前 N 个槽，避免"买武器丢法术"
		var old_slots: Array = current_weapon.slots
		var copy_count := mini(old_slots.size(), new_weapon.slots.size())
		for i in range(copy_count):
				new_weapon.slots[i] = old_slots[i]

		current_weapon = new_weapon
		weapon.set_weapon(current_weapon)

		shop_weapons.remove_at(index)
		shop_weapon_prices.remove_at(index)
		if Net.is_host():
				mp_sync_shop.rpc(_mp_build_shop_payload())

func get_difficulty_mult() -> float:
		# 平衡调整：原指数曲线(1.15^(t/60))后期过陡；
		# 改为线性成长 + 上限 4.5：前期温和、中期稳步增长、后期放缓封顶
		return clamp(1.0 + elapsed / 150.0, 1.0, 4.5)

func _on_player_died() -> void:
		# 联机（主机）：任一玩家死亡 = 全员结束（合作共享命运）
		if Net.is_host():
				_mp_end_game_for_all()
				return
		game_over = true
		_sync_pause()
		game_over_ui.visible = true
		game_over_ui.refresh()

func restart() -> void:
		if Net.is_active():
				if Net.is_host():
						_mp_restart_all()
				else:
						mp_restart_request.rpc_id(1)
				return
		get_tree().paused = false
		get_tree().reload_current_scene()

# ============================================================
# 联机模块（主机权威 / host-authoritative co-op）
#   - 主机：运行全部模拟（刷怪、子弹、伤害、商店、货币）
#   - 客户端：本地预测自己移动，其余状态来自 10Hz 快照
# ============================================================

# ---------- 主机 ----------
func _mp_host_ready() -> void:
		bullet_pool.net_main = self
		multiplayer.peer_connected.connect(_mp_peer_connected)
		multiplayer.peer_disconnected.connect(_mp_peer_disconnected)

func _mp_peer_connected(id: int) -> void:
		# 为新加入的玩家分配槽位号并生成分身（主机代为模拟）
		if not _mp_player_slots.has(id):
				_mp_player_slots[id] = _mp_next_slot
				_mp_next_slot += 1
		mp_assign_slot.rpc_id(id, int(_mp_player_slots[id]))
		var avatar: Player = MP_PLAYER_SCENE.instantiate()
		avatar.remote_controlled = true
		add_child(avatar)
		avatar.global_position = player.global_position + Vector2(60, 0)
		# 禁用分身相机，避免与主机相机冲突
		var cam := avatar.get_node_or_null("Camera2D")
		if cam:
				cam.enabled = false
		var rw := avatar.get_node("Weapon") as Weapon
		rw.remote_controlled = true
		# 远程玩家从初始小鸡枪开始（与单机一致）
		var basic := Catalogs.make_projectile("鸡弹", 7.0, 500.0, 1, 0.0, Color(1, 0.9, 0.3))
		var wdata := Catalogs.make_weapon("小鸡枪", 2, 0.20)
		wdata.slots[0] = basic
		rw.setup(self, bullet_pool, wdata)
		_mp_remote_weapon_data[id] = wdata
		avatar.died.connect(func(): _mp_remote_died(id))
		_mp_remote_players[id] = avatar
		_mp_remote_weapons[id] = rw
		# 给新玩家同步商店与游戏状态
		mp_sync_shop.rpc_id(id, _mp_build_shop_payload())

func _mp_peer_disconnected(id: int) -> void:
		if _mp_remote_players.has(id):
				var p = _mp_remote_players[id]
				if is_instance_valid(p):
						p.queue_free()
				_mp_remote_players.erase(id)
				_mp_remote_weapons.erase(id)
				_mp_remote_weapon_data.erase(id)
		_mp_player_slots.erase(id)

func _mp_remote_died(id: int) -> void:
		# 任一玩家死亡 = 全员游戏结束（合作共享命运）
		_mp_end_game_for_all()

func _mp_end_game_for_all() -> void:
		mp_game_over.rpc()
		game_over = true
		_sync_pause()
		game_over_ui.visible = true
		game_over_ui.refresh()

# 主机每 0.1s 广播一次世界快照
func _mp_host_snapshot(delta: float) -> void:
		if game_over:
				return
		_mp_snap_timer += delta
		if _mp_snap_timer < MP_SNAPSHOT_INTERVAL:
				return
		_mp_snap_timer = 0.0

		# 敌人：给新怪分配网络 id
		var enemies_flat := PackedFloat32Array()
		var nodes := enemy_container.get_children()
		for node in nodes:
				var e := node as Enemy
				if e == null or e.dead:
						continue
				if not _mp_enemy_ids.has(e):
						_mp_enemy_ids[e] = _mp_next_enemy_id
						_mp_next_enemy_id += 1
				enemies_flat.append(float(_mp_enemy_ids[e]))
				enemies_flat.append(e.global_position.x)
				enemies_flat.append(e.global_position.y)
				enemies_flat.append(e.health)
				enemies_flat.append(e.max_health)
				var sc := 1.0
				if e.sprite:
						sc = e.sprite.scale.x
				enemies_flat.append(sc)
				if e.sprite:
						enemies_flat.append(e.sprite.modulate.r)
						enemies_flat.append(e.sprite.modulate.g)
						enemies_flat.append(e.sprite.modulate.b)
				else:
						enemies_flat.append(1.0)
						enemies_flat.append(1.0)
						enemies_flat.append(1.0)
		# 清理已消失敌人的 id
		for e in _mp_enemy_ids.keys():
				if not is_instance_valid(e):
						_mp_enemy_ids.erase(e)

		# 玩家：[槽位号, x, y, hp, max_hp]（主机固定槽位 0，房客从 1 开始）
		var players_flat := PackedFloat32Array()
		players_flat.append(0.0)
		players_flat.append(player.global_position.x)
		players_flat.append(player.global_position.y)
		players_flat.append(player.hp)
		players_flat.append(player.max_hp)
		for pid in _mp_remote_players:
				var p = _mp_remote_players[pid]
				if not is_instance_valid(p):
						continue
				players_flat.append(float(_mp_player_slots.get(pid, 0)))
				players_flat.append(p.global_position.x)
				players_flat.append(p.global_position.y)
				players_flat.append(p.hp)
				players_flat.append(p.max_hp)

		mp_snapshot.rpc(enemies_flat, players_flat, currency, elapsed, rate)

# 主机开火时由 BulletPool 回调：把子弹广播给所有客户端
func mp_broadcast_bullet(pos: Vector2, vel: Vector2, color: Color) -> void:
		mp_bullet.rpc(pos, vel, color)

# ---------- 客户端 ----------
func _mp_client_ready() -> void:
		# 客户端不模拟刷怪/碰撞/开火，只做本地预测和视觉渲染
		weapon.set_process(false)
		spawner.set_process(false)
		# 向主机请求初始商店与状态
		mp_request_state.rpc_id(1)

func _mp_client_process(_delta: float) -> void:
		# 敌人平滑插值（快照 10Hz -> 本地渲染 60Hz）
		for id in _mp_client_enemies:
				var e = _mp_client_enemies[id]
				if not is_instance_valid(e):
						continue
				var target: Vector2 = e.get_meta("target_pos", e.global_position)
				e.global_position = e.global_position.lerp(target, 0.3)
		# 其他玩家分身：向"外推后的目标点"做时间归一的光滑追踪。
		# 目标点 = 快照位置 + 速度 × 一个快照周期，使匀速移动时分身轨迹连续，
		# 消除纯 lerp 追 10Hz 快照时的锯齿抖动
		for slot in _mp_client_avatars:
				var av = _mp_client_avatars[slot]
				if not is_instance_valid(av):
						continue
				var t: Vector2 = av.get_meta("target_pos", av.global_position)
				var v: Vector2 = av.get_meta("target_vel", Vector2.ZERO)
				var ahead: Vector2 = t + v * MP_SNAPSHOT_INTERVAL
				# 平滑系数按帧时间归一（60fps ≈ 0.22，与原 lerp(0.3) 接近但帧率无关）
				var alpha: float = 1.0 - exp(-14.0 * _delta)
				av.global_position = av.global_position.lerp(ahead, alpha)

func _mp_client_physics(_delta: float) -> void:
		if game_over:
				return
		# 采集本地输入并发给主机（移动 + 瞄准 + 开火）
		var move := Vector2.ZERO
		var aim := Vector2.RIGHT
		var firing := true
		if touch_controls != null and touch_controls.enabled:
				move = touch_controls.move_vector
				firing = touch_controls.is_firing
				if touch_controls.aim_vector.length() > 0.1:
						aim = touch_controls.aim_vector.normalized()
		else:
				move = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
				aim = (get_global_mouse_position() - player.global_position).normalized()
		mp_input.rpc_id(1, move, aim, firing)

# ---------- RPC：客户端 -> 主机 ----------
@rpc("any_peer", "unreliable")
func mp_input(move: Vector2, aim: Vector2, firing: bool) -> void:
		var id := multiplayer.get_remote_sender_id()
		var p = _mp_remote_players.get(id)
		var w = _mp_remote_weapons.get(id)
		if p != null and is_instance_valid(p):
				p.net_move = move
		if w != null and is_instance_valid(w):
				w.net_aim = aim
				w.net_firing = firing

@rpc("any_peer", "reliable")
func mp_buy_spell(index: int) -> void:
		# 主机权威结算：钱与货架都在主机侧校验
		buy_spell(index)

@rpc("any_peer", "reliable")
func mp_buy_weapon(index: int) -> void:
		# 主机权威结算：武器购买归属于发起购买的玩家分身
		var id := multiplayer.get_remote_sender_id()
		if not _mp_remote_players.has(id):
				return
		if index < 0 or index >= shop_weapons.size():
				return
		var price := shop_weapon_prices[index]
		if currency < price:
				return
		currency -= price
		var old: WeaponData = _mp_remote_weapon_data.get(id, null)
		var new_w: WeaponData = shop_weapons[index]
		if old != null:
				# 沿用旧武器前 N 个槽的法术，避免"买武器丢法术"
				var copy_count := mini(old.slots.size(), new_w.slots.size())
				for i in range(copy_count):
						if old.slots[i] != null:
								new_w.slots[i] = old.slots[i]
		_mp_remote_weapon_data[id] = new_w
		var rw = _mp_remote_weapons.get(id)
		if rw != null and is_instance_valid(rw):
				rw.set_weapon(new_w)
		shop_weapons.remove_at(index)
		shop_weapon_prices.remove_at(index)
		mp_sync_shop.rpc(_mp_build_shop_payload())

@rpc("any_peer", "reliable")
func mp_request_state() -> void:
		# 新客户端加入时推送商店与状态
		var id := multiplayer.get_remote_sender_id()
		# 补发槽位号，防止 mp_assign_slot 在极端时序下丢失
		if _mp_player_slots.has(id):
				mp_assign_slot.rpc_id(id, int(_mp_player_slots[id]))
		mp_sync_shop.rpc_id(id, _mp_build_shop_payload())

@rpc("any_peer", "reliable")
func mp_restart_request() -> void:
		if Net.is_host():
				_mp_restart_all()

# ---------- RPC：主机 -> 客户端 ----------
@rpc("authority", "reliable")
func mp_assign_slot(slot: int) -> void:
		# 客户端：主机告知自己的玩家槽位号（快照中据此识别"自己"）
		_mp_my_slot = slot

@rpc("authority", "unreliable")
func mp_snapshot(enemies_flat: PackedFloat32Array, players_flat: PackedFloat32Array,
				cur: float, el: float, rt: float) -> void:
		currency = cur
		elapsed = el
		rate = rt
		_mp_apply_enemies(enemies_flat)
		_mp_apply_players(players_flat)
		if not _mp_connected:
				_mp_connected = true

@rpc("authority", "unreliable")
func mp_bullet(pos: Vector2, vel: Vector2, color: Color) -> void:
		# 客户端：仅生成视觉子弹（伤害由主机结算）
		bullet_pool.spawn(pos, vel, 0.0, 2.0, color)

@rpc("authority", "reliable")
func mp_game_over() -> void:
		game_over = true
		_sync_pause()
		game_over_ui.visible = true
		game_over_ui.refresh()

@rpc("authority", "reliable")
func mp_back_to_menu() -> void:
		Net.reset()
		get_tree().change_scene_to_file("res://start.tscn")

@rpc("authority", "reliable")
func mp_sync_shop(payload: Dictionary) -> void:
		_mp_apply_shop_payload(payload)
		if shop_ui.visible:
				shop_ui.refresh()

# ---------- 客户端状态应用 ----------
func _mp_apply_enemies(flat: PackedFloat32Array) -> void:
		var seen := {}
		var i := 0
		var step := 9
		while i + step <= flat.size():
				var id := int(flat[i])
				seen[id] = true
				var e = _mp_client_enemies.get(id)
				if e == null or not is_instance_valid(e):
						e = MP_ENEMY_SCENE.instantiate()
						e.target = null
						enemy_container.add_child(e)
						_mp_client_enemies[id] = e
						# 新建时直接就位，避免从 (0,0) 飞过来
						e.global_position = Vector2(flat[i + 1], flat[i + 2])
				# 已存在：只更新目标位置，由 _mp_client_process 插值平滑过去
				e.set_meta("target_pos", Vector2(flat[i + 1], flat[i + 2]))
				e.health = flat[i + 3]
				e.max_health = flat[i + 4]
				if e.sprite:
						e.sprite.scale = Vector2(flat[i + 5], flat[i + 5])
						e.sprite.modulate = Color(flat[i + 6], flat[i + 7], flat[i + 8])
				if e.health_bar:
						e.health_bar.max_value = e.max_health
						e.health_bar.value = max(e.health, 0.0)
						e.health_bar.visible = e.health < e.max_health
				i += step
		# 移除已消失的敌人
		for id in _mp_client_enemies.keys():
				if not seen.has(id):
						var e = _mp_client_enemies[id]
						if is_instance_valid(e):
								e.queue_free()
						_mp_client_enemies.erase(id)

func _mp_apply_players(flat: PackedFloat32Array) -> void:
		# 客户端：按槽位号区分"自己"与"其他玩家"（槽位由主机分配，见 mp_assign_slot）
		var i := 0
		while i + 5 <= flat.size():
				var slot := int(flat[i])
				var pos := Vector2(flat[i + 1], flat[i + 2])
				var hp := flat[i + 3]
				var max_hp := flat[i + 4]
				if slot == _mp_my_slot and slot >= 0:
						# 自己：本地预测为主，偏差过大时纠正
						player.hp = hp
						player.max_hp = max_hp
						if player.global_position.distance_squared_to(pos) > 100.0 * 100.0:
								player.global_position = pos
				else:
						# 其他玩家（主机或其他客户端）：渲染分身（纯视觉，不做物理模拟）
						var av = _mp_client_avatars.get(slot)
						var is_new := av == null or not is_instance_valid(av)
						if is_new:
								av = MP_PLAYER_SCENE.instantiate()
								av.remote_controlled = true
								# 关闭物理模拟：位置完全由快照插值驱动，
								# 否则 move_and_slide 与快照传送互相打架，表现为"抽风"
								av.set_physics_process(false)
								# 入树前禁用相机，避免抢占当前视角
								var cam: Node = av.get_node_or_null("Camera2D")
								if cam:
										(cam as Camera2D).enabled = false
								add_child(av)
								av.show()
								av.global_position = pos
								_mp_client_avatars[slot] = av
						else:
								# 快照到达：记录目标位置与速度（外推用）
								var prev_target: Vector2 = av.get_meta("target_pos", pos)
								# 速度 = 两次快照位移 / 快照间隔，用于把目标向前外推，
								# 消除"追上目标→停下等下一个快照"造成的锯齿抖动
								var vel: Vector2 = (pos - prev_target) / max(MP_SNAPSHOT_INTERVAL, 0.01)
								if vel.length() > 600.0:
										vel = vel.normalized() * 600.0
								av.set_meta("target_pos", pos)
								av.set_meta("target_vel", vel)
								# 位移小于死区（4px）视为静止：net_move 归零。
								# 否则插值残差（亚像素级）会让分身"原地走路"并轻微抖动
								var step: Vector2 = pos - av.global_position
								if step.length() < 4.0:
										av.net_move = Vector2.ZERO
								else:
										# net_move 取外推速度的方向（归一化限幅）
										av.net_move = (vel / max(220.0, 1.0)).limit_length(1.0)
						av.hp = hp
						av.max_hp = max_hp
				i += 5

# ---------- 商店同步 ----------
func _mp_build_shop_payload() -> Dictionary:
		var spell_names: Array[String] = []
		var spell_prices: Array[int] = []
		var spell_types: Array[int] = []   # 0=投射物 1=修正
		for i in shop_spells.size():
				var s: SpellData = shop_spells[i]
				spell_names.append(s.spell_name)
				spell_prices.append(shop_spell_prices[i])
				spell_types.append(1 if s.type == SpellData.Type.MODIFIER else 0)
		var weapon_names: Array[String] = []
		var weapon_slots: Array[int] = []
		var weapon_delays: Array[float] = []
		var weapon_prices: Array[int] = []
		for i in shop_weapons.size():
				var w: WeaponData = shop_weapons[i]
				weapon_names.append(w.weapon_name)
				weapon_slots.append(w.slot_count)
				weapon_delays.append(w.cast_delay)
				weapon_prices.append(shop_weapon_prices[i])
		var owned_names: Array[String] = []
		for s in owned_spells:
				owned_names.append(s.spell_name)
		return {
				"currency": currency,
				"spell_names": spell_names,
				"spell_prices": spell_prices,
				"spell_types": spell_types,
				"weapon_names": weapon_names,
				"weapon_slots": weapon_slots,
				"weapon_delays": weapon_delays,
				"weapon_prices": weapon_prices,
				"owned_names": owned_names,
				"weapon_name": current_weapon.weapon_name,
				"weapon_slot_count": current_weapon.slot_count,
				"weapon_cast_delay": current_weapon.cast_delay,
		}

func _mp_apply_shop_payload(p: Dictionary) -> void:
		currency = p["currency"]
		# 重建货架（仅用于展示与购买索引，真实结算在主机）
		shop_spells.clear()
		shop_spell_prices.clear()
		var spell_names: Array = p["spell_names"]
		var spell_prices: Array = p["spell_prices"]
		var spell_types: Array = p["spell_types"]
		for i in spell_names.size():
				var s: SpellData
				if spell_types[i] == 1:
						s = Catalogs.make_modifier(spell_names[i], 1.0, 1.0, 0)
				else:
						s = Catalogs.make_projectile(spell_names[i], 1.0, 1.0, 1, 0.0, Color.WHITE)
				shop_spells.append(s)
				shop_spell_prices.append(int(spell_prices[i]))
		shop_weapons.clear()
		shop_weapon_prices.clear()
		var weapon_names: Array = p["weapon_names"]
		var weapon_slots: Array = p["weapon_slots"]
		var weapon_delays: Array = p["weapon_delays"]
		var weapon_prices: Array = p["weapon_prices"]
		for i in weapon_names.size():
				var w := Catalogs.make_weapon(weapon_names[i], int(weapon_slots[i]), weapon_delays[i])
				shop_weapons.append(w)
				shop_weapon_prices.append(int(weapon_prices[i]))
		# 已拥有法术（编辑器在客户端禁用，仅作展示）
		owned_spells.clear()
		for n in p["owned_names"]:
				owned_spells.append(Catalogs.make_projectile(n, 1.0, 1.0, 1, 0.0, Color.WHITE))
		# 当前武器（HUD 展示用）
		current_weapon = Catalogs.make_weapon(p["weapon_name"], int(p["weapon_slot_count"]), p["weapon_cast_delay"])

# ---------- 重开 / 返回主菜单 ----------
func _mp_restart_all() -> void:
		# 先通知客户端回主菜单，再关闭网络
		mp_back_to_menu.rpc()
		await get_tree().create_timer(0.2).timeout
		Net.reset()
		get_tree().change_scene_to_file("res://start.tscn")
