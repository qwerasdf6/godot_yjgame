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
