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
@onready var hp_bar: ProgressBar = $HUDMargin/HUDContainer/HpBarContainer/HpBar
@onready var hp_label: Label = $HUDMargin/HUDContainer/HpBarContainer/HpLabel
@onready var pause_button: Button = $TopRightAnchor/MarginContainer/VBoxContainer/HBoxContainer/PauseButton
@onready var timer_label: Label = $TopRightAnchor/MarginContainer/VBoxContainer/HBoxContainer/TimerLabel

# 血量颜色渐变: 绿(满血) → 黄(半血) → 红(低血)
var hp_color_full: Color = Color(0.2, 0.7, 0.15)    # 翠绿
var hp_color_half: Color = Color(0.85, 0.75, 0.1)    # 琥珀黄
var hp_color_low: Color = Color(0.8, 0.15, 0.1)      # 枯红

func _ready():
	# 监听 SignalBus 事件
	SignalBus.on_player_hp_changed.connect(_on_hp_changed)
	SignalBus.on_level_up.connect(_on_level_up)
	SignalBus.on_wave_started.connect(_on_wave_started)
	
	# 退出按鈕：现在只保留 PauseMenu 的那个
	pause_button.pressed.connect(func(): SignalBus.on_pause_requested.emit())
	
	# 初始化显示
	_update_hp_display(1.0)
	_on_hp_changed(GameData.current_hp, GameData.player_base_stats["max_hp"])
	level_label.text = "Lv.1"
	wave_label.text = "WAVE 1"
	
	var visual_idx = GameData.current_playing_stage - 1
	if GameData.is_endless_mode:
		visual_idx = GameData.selected_sapling - 1
	if visual_idx >= 0 and visual_idx < GameData.growth_stages.size():
		stage_label.text = GameData.growth_stages[visual_idx]["name"]
	else:
		stage_label.text = "异变神木"


func _on_hp_changed(current_hp: float, max_hp: float):
	var ratio = clampf(current_hp / max_hp, 0.0, 1.0)
	exp_ring.max_value = max_hp
	exp_ring.value = current_hp
	hp_bar.max_value = max_hp
	hp_bar.value = current_hp
	hp_label.text = "HP %d / %d" % [int(current_hp), int(max_hp)]
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
	exp_ring.tint_progress = color

func _on_exp_gained(exp_ratio: float):
	pass

func _on_level_up(new_level: int):
	level_label.text = "Lv." + str(new_level)
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
