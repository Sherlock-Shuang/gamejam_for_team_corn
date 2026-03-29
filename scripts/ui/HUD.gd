extends CanvasLayer
# ═══════════════════════════════════════════════════════════════
#  HUD.gd — 年轮式状态 UI
#  底部半圆"树桩横截面"：外圈=经验进度，中心颜色=生命值
# ═══════════════════════════════════════════════════════════════

@onready var exp_ring: TextureProgressBar = $HUDMargin/HUDContainer/RingContainer/ExpRing
@onready var hp_center: Panel = $HUDMargin/HUDContainer/RingContainer/HpCenter
@onready var level_label: Label = $HUDMargin/HUDContainer/RingContainer/LevelLabel
@onready var wave_label: Label = $HUDMargin/HUDContainer/WaveLabel
@onready var stage_label: Label = $HUDMargin/HUDContainer/StageLabel
@onready var pause_button: Button = $TopRightAnchor/MarginContainer/VBoxContainer/HBoxContainer/PauseButton
@onready var timer_label: Label = $TopRightAnchor/MarginContainer/VBoxContainer/HBoxContainer/TimerLabel

# 血量颜色渐变:
var hp_color_full: Color = Color(0.48, 0.65, 0.42)    # 柔和复古绿
var hp_color_half: Color = Color(0.85, 0.65, 0.25)    # 琥珀黄
var hp_color_low: Color = Color(0.8, 0.25, 0.2)       # 枯红

func _ready():
	# 监听 SignalBus 事件
	SignalBus.on_player_hp_changed.connect(_on_hp_changed)
	SignalBus.on_exp_gained.connect(_on_exp_gained)
	SignalBus.on_level_up.connect(_on_level_up)
	SignalBus.on_wave_started.connect(_on_wave_started)
	
	# 退出按鈕：现在只保留 PauseMenu 的那个
	pause_button.pressed.connect(func(): SignalBus.on_pause_requested.emit())
	
	# 初始化显示
	_update_hp_display(1.0)
	exp_ring.value = 0
	level_label.text = "Lv.1"
	wave_label.text = "WAVE 1"
	
	_apply_hud_styles()
	
	var visual_idx = GameData.current_playing_stage - 1
	if GameData.is_endless_mode:
		visual_idx = GameData.selected_sapling - 1
	if visual_idx >= 0 and visual_idx < GameData.growth_stages.size():
		stage_label.text = GameData.growth_stages[visual_idx]["name"]
	else:
		stage_label.text = "异变神木"

func _apply_hud_styles():
	# 统一 HUD 标签面板样式
	var label_style = StyleBoxFlat.new()
	label_style.bg_color = Color(0.12, 0.08, 0.05, 0.8) # 深棕色半透明底
	label_style.border_width_left = 3
	label_style.border_width_top = 3
	label_style.border_width_right = 3
	label_style.border_width_bottom = 3
	label_style.border_color = Color(0.3, 0.2, 0.1, 1.0)
	label_style.corner_radius_top_left = 8
	label_style.corner_radius_top_right = 8
	label_style.corner_radius_bottom_right = 8
	label_style.corner_radius_bottom_left = 8
	label_style.content_margin_left = 12
	label_style.content_margin_right = 12
	label_style.content_margin_top = 6
	label_style.content_margin_bottom = 6
	label_style.anti_aliasing = false
	
	stage_label.add_theme_stylebox_override("normal", label_style)
	wave_label.add_theme_stylebox_override("normal", label_style)
	timer_label.add_theme_stylebox_override("normal", label_style)
	
	timer_label.add_theme_color_override("font_color", Color(0.9, 0.8, 0.7))
	wave_label.add_theme_color_override("font_color", Color(0.85, 0.65, 0.3))
	stage_label.add_theme_color_override("font_color", Color(0.6, 0.85, 0.4))
	
	# 给 HpCenter 增加树皮一样的深色边框圈
	var hp_style = hp_center.get_theme_stylebox("panel").duplicate() as StyleBoxFlat
	if hp_style:
		hp_style.border_width_left = 6
		hp_style.border_width_top = 6
		hp_style.border_width_right = 6
		hp_style.border_width_bottom = 6
		hp_style.border_color = Color(0.18, 0.12, 0.08, 1.0) # 黑棕色外环
		hp_style.shadow_color = Color(0.0, 0.0, 0.0, 0.5)
		hp_style.shadow_size = 4
		hp_center.add_theme_stylebox_override("panel", hp_style)
	
	# 暂停按钮样式
	var btn_style = label_style.duplicate()
	pause_button.add_theme_stylebox_override("normal", btn_style)
	
	var btn_hover = btn_style.duplicate()
	btn_hover.bg_color = Color(0.3, 0.25, 0.15, 1.0)
	pause_button.add_theme_stylebox_override("hover", btn_hover)
	
	var btn_pressed = btn_style.duplicate()
	btn_pressed.bg_color = Color(0.1, 0.05, 0.02, 1.0)
	pause_button.add_theme_stylebox_override("pressed", btn_pressed)
	pause_button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())


func _on_hp_changed(current_hp: float, max_hp: float):
	var ratio = clampf(current_hp / max_hp, 0.0, 1.0)
	_update_hp_display(ratio)

func _update_hp_display(ratio: float):
	var color: Color
	if ratio > 0.5:
		var t = (ratio - 0.5) / 0.5
		color = hp_color_half.lerp(hp_color_full, t)
	else:
		var t = ratio / 0.5
		color = hp_color_low.lerp(hp_color_half, t)
	hp_center.self_modulate = color

func _on_exp_gained(exp_ratio: float):
	exp_ring.value = exp_ratio * 100.0

func _on_level_up(new_level: int):
	level_label.text = "Lv." + str(new_level)
	exp_ring.value = 0
	_play_level_up_flash()

func _on_wave_started(wave_number: int):
	wave_label.text = "WAVE " + str(wave_number)

func _play_level_up_flash():
	var tween = create_tween()
	var original_color = hp_center.self_modulate
	tween.tween_property(hp_center, "self_modulate", Color.WHITE, 0.15)
	tween.tween_property(hp_center, "self_modulate", original_color, 0.3)

func update_timer(time_left: float):
	timer_label.text = "时间: %.1f s" % time_left
