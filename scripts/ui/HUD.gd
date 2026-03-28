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
@onready var return_button: Button = $TopRightAnchor/MarginContainer/ReturnButton

# 血量颜色渐变: 绿(满血) → 黄(半血) → 红(低血)
var hp_color_full: Color = Color(0.2, 0.7, 0.15)    # 翠绿
var hp_color_half: Color = Color(0.85, 0.75, 0.1)    # 琥珀黄
var hp_color_low: Color = Color(0.8, 0.15, 0.1)      # 枯红

func _ready():
	# 监听 SignalBus 事件
	SignalBus.on_player_hp_changed.connect(_on_hp_changed)
	SignalBus.on_exp_gained.connect(_on_exp_gained)
	SignalBus.on_level_up.connect(_on_level_up)
	SignalBus.on_wave_started.connect(_on_wave_started)
	
	# 退出按鈕：pressed 信号 → SignalBus → 后续用来返回年轮主选单
	return_button.pressed.connect(func(): SignalBus.on_return_requested.emit())
	
	# 初始化显示
	_update_hp_display(1.0)
	exp_ring.value = 0
	level_label.text = "Lv.1"
	wave_label.text = "WAVE 1"
	stage_label.text = "幼苗"

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
	
	var stage = GameData.get_current_growth_stage(new_level)
	stage_label.text = stage["name"]
	
	_play_level_up_flash()

func _on_wave_started(wave_number: int):
	wave_label.text = "WAVE " + str(wave_number)

func _play_level_up_flash():
	var tween = create_tween()
	var original_color = hp_center.self_modulate
	tween.tween_property(hp_center, "self_modulate", Color.WHITE, 0.15)
	tween.tween_property(hp_center, "self_modulate", original_color, 0.3)
