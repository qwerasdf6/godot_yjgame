class_name SpellData
extends Resource

enum Type { PROJECTILE, MODIFIER }

@export var spell_name: String = ""
@export var type: Type = Type.PROJECTILE

# 投射物参数
@export var damage: float = 10.0
@export var speed: float = 500.0
@export var count: int = 1
@export var spread: float = 0.0
@export var color: Color = Color(1, 0.9, 0.3, 1)
@export var pierce: int = 0   # 可穿透的敌人数量（打中后继续飞行）

# 修正参数
@export var modifier_damage_mult: float = 1.0
@export var modifier_speed_mult: float = 1.0
@export var modifier_count_add: int = 0
@export var modifier_pierce_add: int = 0        # 弹药穿透数加成
@export var modifier_lifetime_mult: float = 1.0 # 弹药存留时间倍率
