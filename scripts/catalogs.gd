class_name Catalogs
extends RefCounted

static func make_projectile(name: String, dmg: float, spd: float, cnt: int, spread: float, color: Color, pierce := 0) -> SpellData:
		var s := SpellData.new()
		s.spell_name = name
		s.type = SpellData.Type.PROJECTILE
		s.damage = dmg
		s.speed = spd
		s.count = cnt
		s.spread = spread
		s.color = color
		s.pierce = pierce
		return s

static func make_modifier(name: String, dmg_mult: float, spd_mult: float, cnt_add: int, pierce_add := 0, life_mult := 1.0) -> SpellData:
		var s := SpellData.new()
		s.spell_name = name
		s.type = SpellData.Type.MODIFIER
		s.modifier_damage_mult = dmg_mult
		s.modifier_speed_mult = spd_mult
		s.modifier_count_add = cnt_add
		s.modifier_pierce_add = pierce_add
		s.modifier_lifetime_mult = life_mult
		return s

# proj = 插件槽数（1-2），mods = 增益槽数
static func make_weapon(name: String, proj: int, mods: int, delay: float) -> WeaponData:
		var w := WeaponData.new()
		w.weapon_name = name
		w.slot_count = proj
		w.slots.resize(proj)
		w.mod_slot_count = mods
		w.mod_slots.resize(mods)
		w.cast_delay = delay
		return w
