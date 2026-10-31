extends Control

var player: Node2D = null
var enabled: bool = false   # 开关，默认关闭

func _ready() -> void:
	player = get_tree().get_first_node_in_group("player")
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _process(_delta: float) -> void:
	if enabled:
		queue_redraw()

func _draw() -> void:
	if not enabled:
		return
	if player == null or not is_instance_valid(player):
		return
	
	var player_screen := _to_screen(player.global_position)
	
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(enemy) or enemy.dead:
			continue
		
		var center := _to_screen(enemy.global_position)
		var rect := Rect2(center - Vector2(20, 20), Vector2(40, 40))
		draw_rect(rect, Color.CYAN, false, 2.0)
		draw_line(center, player_screen, Color.RED, 1.5)

func _to_screen(world_pos: Vector2) -> Vector2:
	return get_viewport().get_canvas_transform() * world_pos

func set_enabled(value: bool) -> void:
	if enabled == value:
		return
	enabled = value
	queue_redraw()   # 关闭时立刻重绘一次，清掉残留的方框
