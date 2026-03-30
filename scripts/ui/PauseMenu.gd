extends CanvasLayer

@export var 点击_sfx: AudioStream
@export var 悬停_sfx: AudioStream


func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS
	
	var continue_btn = $MainContainer/ButtonBox/ContinueButton
	var return_btn = $MainContainer/ButtonBox/OptionsBox/ReturnButton
	var quit_btn = $MainContainer/ButtonBox/OptionsBox/QuitButton
	
	continue_btn.pressed.connect(func(): 
		if 点击_sfx: AudioManager.play_sfx(点击_sfx, 0.0, false)
		_on_continue_pressed()
	)
	return_btn.pressed.connect(func(): 
		if 点击_sfx: AudioManager.play_sfx(点击_sfx, 0.0, false)
		_on_return_pressed()
	)
	quit_btn.pressed.connect(func(): 
		if 点击_sfx: AudioManager.play_sfx(点击_sfx, 0.0, false)
		_on_quit_pressed()
	)
	
	# 为所有按钮添加悬停缩放效果
	var buttons = [continue_btn, return_btn, quit_btn]
	for btn in buttons:
		# 设置中心点以便缩放
		btn.pivot_offset = btn.size / 2
		
		btn.mouse_entered.connect(func():
			if 悬停_sfx: AudioManager.play_sfx(悬停_sfx, -10.0, true)
			var tween = create_tween()
			tween.tween_property(btn, "scale", Vector2(1.1, 1.1), 0.1).set_trans(Tween.TRANS_SINE)
		)
		btn.mouse_exited.connect(func():
			var tween = create_tween()
			tween.tween_property(btn, "scale", Vector2(1.0, 1.0), 0.1).set_trans(Tween.TRANS_SINE)
		)

func _on_continue_pressed():
	get_tree().paused = false
	queue_free()

func _on_return_pressed():
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/ui/AnnualRingMenu.tscn")

func _on_quit_pressed():
	get_tree().quit()
