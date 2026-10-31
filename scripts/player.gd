class_name Player
extends CharacterBody2D

signal died

@export var move_speed: float = 220.0

var max_hp: float = 100.0
var hp: float = 100.0
var invuln_timer: float = 0.0
var touch_controls = null

func _ready() -> void:
	add_to_group("player")
	
func _physics_process(_delta: float) -> void:
	var input_vec := Vector2.ZERO
	if touch_controls != null and touch_controls.enabled:
		input_vec = touch_controls.move_vector
	else:
		input_vec = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	velocity = input_vec * move_speed
	move_and_slide()

func _process(delta: float) -> void:
	if invuln_timer > 0.0:
		invuln_timer -= delta
		modulate.a = 0.4 if int(invuln_timer * 20.0) % 2 == 0 else 1.0
	else:
		modulate.a = 1.0
	
		#var xy : Vector2 = Input.get_vector("ui_left","ui_right","ui_up","ui_down")
	
	if touch_controls != null and touch_controls.enabled:
		var input_vec1 : Vector2 = touch_controls.move_vector
		if input_vec1:
			$Sprite2D.flip_h = input_vec1.x > 0
			if input_vec1.x != 0:
				$Sprite2D.animation = 'left'
		else:
			$Sprite2D.frame = 0

func take_damage(amount: float) -> void:
	if invuln_timer > 0.0 or hp <= 0.0:
		return
	hp -= amount
	
	$AudioStreamPlayer2D.play()
	
	invuln_timer = 0.5
	if hp <= 0.0:
		hp = 0.0
		died.emit()
