extends Control

@onready var title1 = $MainVBox/Title1
@onready var title2 = $MainVBox/Title2
@onready var subtitle = $MainVBox/Subtitle
@onready var poem = $MainVBox/Poem
@onready var start_button = $MainVBox/ButtonsHBox/StartButton
@onready var return_button = $MainVBox/ButtonsHBox/ReturnButton
@onready var buttons_hbox = $MainVBox/ButtonsHBox

func _ready():
	_apply_styles()
	start_button.pressed.connect(_on_start_pressed)
	return_button.pressed.connect(_on_return_pressed)

func _apply_styles():
	# 统一背景
	$ColorRect.color = Color(0.1, 0.08, 0.05, 1)
	
	# 标题样式
	for t in [title1, title2]:
		t.add_theme_color_override("font_color", Color(0.95, 0.85, 0.55, 1))
		t.add_theme_color_override("font_shadow_color", Color(0.2, 0.1, 0.05, 1))
		t.add_theme_constant_override("shadow_offset_x", 8)
		t.add_theme_constant_override("shadow_offset_y", 8)
		t.add_theme_constant_override("outline_size", 6)
	
	# 字幕与诗句样式
	subtitle.add_theme_color_override("font_color", Color(0.85, 0.75, 0.65, 1))
	poem.add_theme_color_override("font_color", Color(0.8, 0.75, 0.6, 0.7))
	poem.add_theme_constant_override("line_spacing", 12)
	
	if GameData.has_seen_endless_intro:
		title1.modulate.a = 1.0
		title2.modulate.a = 1.0
		subtitle.modulate.a = 1.0
		poem.modulate.a = 1.0
		buttons_hbox.modulate.a = 1.0
	else:
		GameData.has_seen_endless_intro = true
		title1.modulate.a = 0.0
		title2.modulate.a = 0.0
		subtitle.modulate.a = 0.0
		poem.modulate.a = 0.0
		buttons_hbox.modulate.a = 0.0
		
		var tween = create_tween().set_parallel(true)
		tween.tween_property(title1, "modulate:a", 1.0, 1.5).set_trans(Tween.TRANS_SINE)
		tween.tween_property(title2, "modulate:a", 1.0, 1.5).set_delay(2.0)
		tween.tween_property(subtitle, "modulate:a", 1.0, 2.0).set_delay(4.0)
		tween.tween_property(poem, "modulate:a", 1.0, 3.0).set_delay(5.5)
		tween.tween_property(buttons_hbox, "modulate:a", 1.0, 1.2).set_delay(7.5)
	
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
	
	var buttons = [start_button, return_button]
	for btn in buttons:
		btn.add_theme_color_override("font_color", Color(0.85, 0.75, 0.65, 1))
		btn.add_theme_stylebox_override("normal", btn_normal)
		btn.add_theme_stylebox_override("hover", btn_hover)
		btn.add_theme_stylebox_override("pressed", btn_pressed)
		btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())

func _on_start_pressed():
	print("[Endless] 开始挑战无尽模式")
	GameData.is_endless_mode = true
	GameData.current_playing_stage = 99 # 特殊 ID 用于记录无尽模式技能
	get_tree().change_scene_to_file("res://Main.tscn")

func _on_return_pressed():
	get_tree().change_scene_to_file("res://scenes/ui/AnnualRingMenu.tscn")
