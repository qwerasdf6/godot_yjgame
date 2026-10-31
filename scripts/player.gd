class_name Player
extends CharacterBody2D

signal died

@export var move_speed: float = 220.0

var max_hp: float = 100.0
var hp: float = 100.0
var invuln_timer: float = 0.0
var touch_controls = null

# ---- 联机：由主机上的远程输入驱动的分身（不读本地键盘）----
var remote_controlled: bool = false
var net_move: Vector2 = Vector2.ZERO

func _ready() -> void:
        add_to_group("player")
        
func _physics_process(_delta: float) -> void:
        var input_vec := Vector2.ZERO
        if remote_controlled:
                input_vec = net_move
        elif touch_controls != null and touch_controls.enabled:
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
        # 联机客户端：伤害由主机结算，本地不扣血
        if Net.is_client():
                return
        if invuln_timer > 0.0 or hp <= 0.0:
                return
        hp -= amount
        
        $AudioStreamPlayer2D.play()
        
        # 无敌帧 0.5 -> 0.8：被怪群围住时有更多反应空间
        invuln_timer = 0.8
        if hp <= 0.0:
                hp = 0.0
                died.emit()
