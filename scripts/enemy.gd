class_name Enemy
extends CharacterBody2D

var health: float = 30.0
var max_health: float = 30.0
var speed: float = 60.0
var dead: bool = false
var target: Node2D = null

@onready var sprite: Sprite2D = $Sprite2D
@onready var health_bar: ProgressBar = $HealthBar

func _ready() -> void:
	add_to_group("enemies")
	if health_bar:
		health_bar.max_value = max_health
		health_bar.value = health
		health_bar.visible = false

func setup(hp: float, spd: float, visual_scale: float, color: Color, diff_mult: float) -> void:
	max_health = hp * diff_mult
	health = max_health
	speed = spd * clamp(diff_mult * 0.5 + 0.5, 1.0, 2.0)
	
	if sprite:
		sprite.scale = Vector2(visual_scale, visual_scale)
		sprite.modulate = color
	
	if health_bar:
		health_bar.max_value = max_health
		health_bar.value = health
		health_bar.visible = false

func _physics_process(_delta: float) -> void:
	if dead or target == null:
		return
	var dir := (target.global_position - global_position).normalized()
	velocity = dir * speed
	move_and_slide()

func take_damage(amount: float) -> void:
	if dead:
		return
	
	health -= amount
	
	if health_bar:
		health_bar.value = max(health, 0.0)
		health_bar.visible = true
	
	_spawn_damage_number(amount)
	
	if health <= 0.0:
		_die()

func _die() -> void:
	dead = true
	velocity = Vector2.ZERO
	if health_bar:
		health_bar.value = 0
	await get_tree().create_timer(0.15).timeout
	queue_free()

func _spawn_damage_number(amount: float, is_crit: bool = false) -> void:
	var parent := get_parent()
	if not is_instance_valid(parent):
		return
	
	var label := Label.new()
	label.text = str(int(round(amount)))
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.modulate = Color.ORANGE if is_crit else Color.WHITE
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 4)
	if is_crit:
		label.add_theme_font_size_override("font_size", 32)
	
	parent.add_child(label)
	label.global_position = global_position + Vector2(0, -30)
	
	var lifetime := 0.7
	var tween := label.create_tween()
	tween.set_parallel(true)
	tween.tween_property(label, "position:y", label.position.y - 40.0, lifetime) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tween.tween_property(label, "modulate:a", 0.0, lifetime * 0.5) \
		.set_delay(lifetime * 0.5)
	tween.finished.connect(label.queue_free)
