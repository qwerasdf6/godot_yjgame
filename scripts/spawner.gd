class_name Spawner
extends Node

const ENEMY_SCENE := preload("res://scenes/Enemy.tscn")

const TYPE_BASIC = {"hp": 30.0, "speed": 90.0, "scale": 0.3, "color": Color(1, 0.6, 0.6)}
const TYPE_FAST = {"hp": 20.0, "speed": 140.0, "scale": 0.25, "color": Color(0.6, 1, 0.6)}
const TYPE_TANK = {"hp": 100.0, "speed": 50.0, "scale": 0.45, "color": Color(0.6, 0.6, 1)}

var main: Node = null
var player: Node2D = null
var enemy_container: Node2D = null
var timer: float = 0.0
var spawn_interval: float = 0.6
var max_enemies: int = 60
var spawn_radius: float = 600.0

func setup(m: Node, p: Node2D, c: Node2D) -> void:
	main = m
	player = p
	enemy_container = c

func _process(delta: float) -> void:
	timer -= delta
	if timer <= 0.0:
		timer = spawn_interval
		_try_spawn()

func _try_spawn() -> void:
	if player == null or enemy_container == null:
		return
	if enemy_container.get_child_count() >= max_enemies:
		return
	var data := _pick_type()
	var angle := randf() * TAU
	var e := ENEMY_SCENE.instantiate() as Enemy
	enemy_container.add_child(e)
	e.global_position = player.global_position + Vector2(cos(angle), sin(angle)) * spawn_radius
	e.target = player
	e.setup(data.hp, data.speed, data.scale, data.color, main.get_difficulty_mult())

func _pick_type() -> Dictionary:
	var t: float = main.elapsed
	var weights: Array[float] = [1.0]
	if t >= 60.0:
		weights.append(0.3 + (t - 120.0) / 240.0)
	if t >= 180.0:
		weights.append(0.2 + (t - 240.0) / 240.0)
	var total := 0.0
	for w in weights:
		total += w
	var r := randf() * total
	var cum := 0.0
	for i in weights.size():
		cum += weights[i]
		if r <= cum:
			if i == 0:
				return TYPE_BASIC
			if i == 1:
				return TYPE_FAST
			return TYPE_TANK
	return TYPE_BASIC
