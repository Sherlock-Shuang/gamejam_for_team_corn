extends Control

func _ready():
	$ContinueButton.pressed.connect(_on_continue_pressed)
	_apply_styles()

func _apply_styles():
	# 统一背景色
	if has_node("Background"):
		var bg_color = Color(0.1, 0.08, 0.05, 1) # 深木色
		$Background.color = bg_color
	
	# 统一标题颜色
	if has_node("Title"):
		$Title.add_theme_color_override("font_color", Color(0.95, 0.85, 0.55, 1))
		$Title.add_theme_color_override("font_shadow_color", Color(0.2, 0.1, 0.05, 1))
		$Title.add_theme_color_override("font_outline_color", Color(0.3, 0.15, 0.05, 1))
		$Title.add_theme_constant_override("shadow_offset_x", 8)
		$Title.add_theme_constant_override("shadow_offset_y", 8)
		$Title.add_theme_constant_override("outline_size", 12)
		
	if has_node("StoryText"):
		$StoryText.add_theme_color_override("font_color", Color(0.85, 0.75, 0.65, 1))
	
	# 给按钮套上原木面板样式
	var btn_normal = StyleBoxFlat.new()
	btn_normal.bg_color = Color(0.18, 0.14, 0.09, 1)
	btn_normal.border_width_left = 4
	btn_normal.border_width_top = 4
	btn_normal.border_width_right = 4
	btn_normal.border_width_bottom = 4
	btn_normal.border_color = Color(0.35, 0.25, 0.15, 1)
	btn_normal.corner_radius_top_left = 8
	btn_normal.corner_radius_top_right = 8
	btn_normal.corner_radius_bottom_right = 8
	btn_normal.corner_radius_bottom_left = 8
	
	var btn_hover = btn_normal.duplicate()
	btn_hover.bg_color = Color(0.45, 0.35, 0.2, 1)
	btn_hover.border_color = Color(0.65, 0.55, 0.35, 1)
	btn_hover.shadow_color = Color(0.1, 0.15, 0.05, 1)
	btn_hover.shadow_offset = Vector2(0, 4)
	
	var btn_pressed = btn_normal.duplicate()
	btn_pressed.bg_color = Color(0.15, 0.12, 0.08, 1)
	
	$ContinueButton.add_theme_color_override("font_color", Color(0.85, 0.75, 0.65, 1))
	$ContinueButton.add_theme_stylebox_override("normal", btn_normal)
	$ContinueButton.add_theme_stylebox_override("hover", btn_hover)
	$ContinueButton.add_theme_stylebox_override("pressed", btn_pressed)
	$ContinueButton.add_theme_stylebox_override("focus", StyleBoxEmpty.new())

func _on_continue_pressed():
	get_tree().change_scene_to_file("res://scenes/ui/AnnualRingMenu.tscn")
