class_name WeaponData
extends Resource

@export var weapon_name: String = "Weapon"
# 插件槽：放投射物技能，1-2 个
@export var slot_count: int = 1
@export var slots: Array[SpellData] = []
# 增益槽：放修正技能，作用于本武器全部投射物
@export var mod_slot_count: int = 1
@export var mod_slots: Array[SpellData] = []
@export var cast_delay: float = 0.15
