class_name Catalogs
extends RefCounted

static func make_projectile(name: String, dmg: float, spd: float, cnt: int, spread: float, color: Color) -> SpellData:
	var s := SpellData.new()
	s.spell_name = name
	s.type = SpellData.Type.PROJECTILE
	s.damage = dmg
	s.speed = spd
	s.count = cnt
	s.spread = spread
	s.color = color
	return s

static func make_modifier(name: String, dmg_mult: float, spd_mult: float, cnt_add: int) -> SpellData:
	var s := SpellData.new()
	s.spell_name = name
	s.type = SpellData.Type.MODIFIER
	s.modifier_damage_mult = dmg_mult
	s.modifier_speed_mult = spd_mult
	s.modifier_count_add = cnt_add
	return s

static func make_weapon(name: String, slots: int, delay: float) -> WeaponData:
	var w := WeaponData.new()
	w.weapon_name = name
	w.slot_count = slots
	w.cast_delay = delay
	w.slots.resize(slots)
	return w
