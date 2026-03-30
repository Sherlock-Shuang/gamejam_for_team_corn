extends Control

func _ready():
	_apply_retro_style()
	$ContinueButton.pressed.connect(_on_continue_pressed)

func _apply_retro_style():
	# 彻底干掉那坨黄色背景，改用深木色底
	if has_node("Background"):
		var bg_color = $Background as ColorRect
		bg_color.color = Color(0.1, 0.08, 0.05, 1.0) 
	
	# 添加复古纹理背景，不限制在黄色之上
	var bg_tex = TextureRect.new()
	bg_tex.texture = load("res://assets/sprites/background/背景3.png") # 使用更具氛围感的背景3
	bg_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bg_tex.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg_tex.modulate = Color(0.45, 0.4, 0.35, 1.0) # 调暗背景，让文字突出
	add_child(bg_tex)
	move_child(bg_tex, 0) # 放到最底层渲染
	
	# 标题样式：金色质感
	$Title.add_theme_color_override("font_color", Color(0.95, 0.85, 0.55))
	$Title.add_theme_font_size_override("font_size", 72)
	$Title.add_theme_color_override("font_shadow_color", Color(0.2, 0.1, 0.05))
	$Title.add_theme_constant_override("shadow_offset_x", 6)
	$Title.add_theme_constant_override("shadow_offset_y", 6)
	
	# 故事文本样式：柔和象牙白
	$StoryText.add_theme_color_override("font_color", Color(0.9, 0.85, 0.8))
	$StoryText.add_theme_font_size_override("font_size", 36)
	$StoryText.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.5))
	$StoryText.add_theme_constant_override("shadow_offset_x", 2)
	$StoryText.add_theme_constant_override("shadow_offset_y", 2)
	
	# 按钮样式：复古木质
	var btn_normal = StyleBoxFlat.new()
	btn_normal.bg_color = Color(0.18, 0.14, 0.09, 1.0) # 深褐色木板
	btn_normal.border_width_left = 6
	btn_normal.border_width_top = 6
	btn_normal.border_width_right = 6
	btn_normal.border_width_bottom = 6
	btn_normal.border_color = Color(0.35, 0.25, 0.15, 1.0)
	btn_normal.corner_radius_top_left = 12
	btn_normal.corner_radius_top_right = 12
	btn_normal.corner_radius_bottom_right = 12
	btn_normal.corner_radius_bottom_left = 12
	
	var btn_hover = btn_normal.duplicate()
	btn_hover.bg_color = Color(0.45, 0.35, 0.2, 1.0) # 悬停琥珀色
	btn_hover.border_color = Color(0.7, 0.6, 0.4, 1.0)
	
	var btn_pressed = btn_normal.duplicate()
	btn_pressed.bg_color = Color(0.1, 0.05, 0.02, 1.0)
	
	var btn = $ContinueButton
	btn.add_theme_stylebox_override("normal", btn_normal)
	btn.add_theme_stylebox_override("hover", btn_hover)
	btn.add_theme_stylebox_override("pressed", btn_pressed)
	btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	btn.add_theme_color_override("font_color", Color(0.9, 0.8, 0.7))
	btn.add_theme_font_size_override("font_size", 38)
	btn.custom_minimum_size = Vector2(350, 100)

func _on_continue_pressed():
	get_tree().change_scene_to_file("res://scenes/ui/AnnualRingMenu.tscn")
