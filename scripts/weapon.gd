class_name Weapon
extends Node2D

var main: Node = null
var bullet_pool: BulletPool = null
var weapon_data: WeaponData = null
var touch_controls = null
var _cooldown: float = 0.0

# ---- 联机：远程玩家的武器（瞄准与开火来自网络输入）----
var remote_controlled: bool = false
var net_aim: Vector2 = Vector2.RIGHT
var net_firing: bool = false

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
        if remote_controlled and not net_firing:
                return
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
        if remote_controlled:
                return net_aim
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
