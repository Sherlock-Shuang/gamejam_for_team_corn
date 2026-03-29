extends Control

func _ready():
	$HBoxContainer/Sapling1.pressed.connect(func(): _start_endless(1))
	$HBoxContainer/Sapling2.pressed.connect(func(): _start_endless(2))
	$HBoxContainer/Sapling3.pressed.connect(func(): _start_endless(3))
	$HBoxContainer/Sapling4.pressed.connect(func(): _start_endless(4))
	$ReturnButton.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/ui/AnnualRingMenu.tscn"))

func _input(event):
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_1: _start_endless(1)
		elif event.keycode == KEY_2: _start_endless(2)
		elif event.keycode == KEY_3: _start_endless(3)
		elif event.keycode == KEY_4: _start_endless(4)

func _start_endless(sapling_id: int):
	print("[Endless] 选择了树苗:", sapling_id)
	
	# 后续可以在 GameData 增加 selected_sapling_id 控制不同的血量/属性
	GameData.is_endless_mode = true
	
	# 跳入战斗场景
	get_tree().change_scene_to_file("res://Main.tscn")
