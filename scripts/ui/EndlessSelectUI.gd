extends Control

func _ready():
	_apply_styles()
	$HBoxContainer/StartButton.pressed.connect(_on_start_pressed)
	$HBoxContainer/ReturnButton.pressed.connect(_on_return_pressed)

func _apply_styles():
	# 统一背景
	$ColorRect.color = Color(0.1, 0.08, 0.05, 1)
	
	# 标题样式
	$Title.add_theme_color_override("font_color", Color(0.95, 0.85, 0.55, 1))
	$Title.add_theme_color_override("font_shadow_color", Color(0.2, 0.1, 0.05, 1))
	$Title.add_theme_constant_override("shadow_offset_x", 8)
	$Title.add_theme_constant_override("shadow_offset_y", 8)
	$Title.add_theme_constant_override("outline_size", 12)
	
	# 规则文字样式
	$RulesPanel/RulesTitle.add_theme_color_override("font_color", Color(0.85, 0.75, 0.65, 1))
	$RulesPanel/RulesText.add_theme_color_override("font_color", Color(0.8, 0.75, 0.6, 1))
	
	# 按钮样式统一 (复用复古原木风)
	var btn_normal = StyleBoxFlat.new()
	btn_normal.bg_color = Color(0.18, 0.14, 0.09, 1)
	btn_normal.border_width_left = 6
	btn_normal.border_width_right = 6
	btn_normal.border_color = Color(0.35, 0.25, 0.15, 1)
	btn_normal.corner_radius_top_left = 8
	btn_normal.corner_radius_top_right = 8
	btn_normal.corner_radius_bottom_right = 8
	btn_normal.corner_radius_bottom_left = 8
	
	var btn_hover = btn_normal.duplicate()
	btn_hover.bg_color = Color(0.45, 0.35, 0.2, 1)
	btn_hover.border_color = Color(0.65, 0.55, 0.35, 1)
	
	var btn_pressed = btn_normal.duplicate()
	btn_pressed.bg_color = Color(0.15, 0.12, 0.08, 1)
	
	var buttons = [$HBoxContainer/StartButton, $HBoxContainer/ReturnButton]
	for btn in buttons:
		btn.add_theme_color_override("font_color", Color(0.85, 0.75, 0.65, 1))
		btn.add_theme_stylebox_override("normal", btn_normal)
		btn.add_theme_stylebox_override("hover", btn_hover)
		btn.add_theme_stylebox_override("pressed", btn_pressed)
		btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())

func _on_start_pressed():
	print("[Endless] 开始挑战挑战无尽模式")
	GameData.is_endless_mode = true
	get_tree().change_scene_to_file("res://Main.tscn")

func _on_return_pressed():
	get_tree().change_scene_to_file("res://scenes/ui/AnnualRingMenu.tscn")
