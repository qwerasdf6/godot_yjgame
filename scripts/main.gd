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
        if get_tree().paused:
                return
        elapsed += delta
        # 货币曲线：起步更慢，让中期购物有节奏
        rate = min(3.0, 1.0 + elapsed * 0.005)
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
        for node in enemy_container.get_children():
                var e := node as Enemy
                if e == null or e.dead:
                        continue
                if player.global_position.distance_squared_to(e.global_position) < CONTACT_RADIUS_SQ:
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
        _sync_pause()
        if state == UIState.SHOP:
                _ensure_stock()
                shop_ui.refresh()
        elif state == UIState.EDITOR:
                editor_ui.refresh()

# 暂停状态统一入口：UI 打开或游戏结束时暂停
func _sync_pause() -> void:
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

func get_difficulty_mult() -> float:
        # 平衡调整：原指数曲线(1.15^(t/60))后期过陡；
        # 改为线性成长 + 上限 4.5：前期温和、中期稳步增长、后期放缓封顶
        return clamp(1.0 + elapsed / 150.0, 1.0, 4.5)

func _on_player_died() -> void:
        game_over = true
        _sync_pause()
        game_over_ui.visible = true
        game_over_ui.refresh()

func restart() -> void:
        get_tree().paused = false
        get_tree().reload_current_scene()
        
