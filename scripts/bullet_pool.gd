class_name BulletPool
extends Node2D

const POOL_SIZE := 500
const BULLET_SCENE := preload("res://scenes/Bullet.tscn")

var _available: Array[Bullet] = []
var _active: Array[Bullet] = []

func _ready() -> void:
	for i in POOL_SIZE:
		var b: Bullet = BULLET_SCENE.instantiate()
		add_child(b)
		b.visible = false
		b.set_process(false)
		b.active = false
		b.pool = self
		_available.append(b)

func spawn(pos: Vector2, vel: Vector2, dmg: float, life: float = 2.0, color: Color = Color.WHITE) -> void:
	var b: Bullet
	if _available.is_empty():
		push_warning("BulletPool exhausted, creating extra bullet")
		b = BULLET_SCENE.instantiate()
		add_child(b)
	else:
		b = _available.pop_back()
	b.spawn(pos, vel, dmg, life, color, self)
	_active.append(b)
	$AudioStreamPlayer2D.play()

func recycle(b: Bullet) -> void:
	if not b.active:
		return
	b.active = false
	b.visible = false
	b.set_process(false)
	b.velocity = Vector2.ZERO
	b.global_position = Vector2(-10000, -10000)
	var idx := _active.find(b)
	if idx != -1:
		_active.remove_at(idx)
	_available.append(b)

func get_active() -> Array[Bullet]:
	return _active
