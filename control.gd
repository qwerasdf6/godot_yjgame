extends Control


func _input(event):
	# 检测触摸按下事件（安卓）
	if event is InputEventScreenTouch and event.pressed:
		get_viewport().set_input_as_handled()
		start_game()
		# 标记输入已处理，防止同一帧重复触发
		

func start_game():
	# 防止重复调用
	set_process_input(false)
	
	# 这里写你的开始游戏逻辑，例如切换场景
	get_tree().change_scene_to_file('res://scenes/Main.tscn')
	print("游戏开始！")
