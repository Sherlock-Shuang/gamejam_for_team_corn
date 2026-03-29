extends CanvasLayer

func _ready():
	# 确保在暂停状态下这个节点依然运行
	process_mode = Node.PROCESS_MODE_ALWAYS
	
	$Panel/VBoxContainer/ContinueButton.pressed.connect(_on_continue_pressed)
	$Panel/VBoxContainer/ReturnButton.pressed.connect(_on_return_pressed)
	$Panel/VBoxContainer/QuitButton.pressed.connect(_on_quit_pressed)
	
	# 加入一个小型的年轮UI作为装饰
	var ring_drawer = Control.new()
	ring_drawer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ring_drawer.connect("draw", func():
		# 画在屏幕上半部分中间
		var center = Vector2(960, 240)
		for i in range(1, GameData.current_max_stage + 1):
			var r = 15.0 + i * 15.0
			var color = Color(0.65, 0.75, 0.2, 0.8) if i == GameData.current_playing_stage else Color(0.35, 0.25, 0.15, 0.5)
			ring_drawer.draw_arc(center, r, 0, TAU, 32, color, 6.0, true)
			
			if GameData.skill_history_per_stage.has(i):
				var skills = GameData.skill_history_per_stage[i]
				for j in range(skills.size()):
					var angle = i * 0.5 + j * (TAU/max(1, skills.size()))
					ring_drawer.draw_circle(center + Vector2.RIGHT.rotated(angle) * r, 3.0, Color(0.1, 0.9, 0.8))
	)
	add_child(ring_drawer)


func _on_continue_pressed():
	get_tree().paused = false
	queue_free()

func _on_return_pressed():
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/ui/AnnualRingMenu.tscn")

func _on_quit_pressed():
	get_tree().quit()
