extends CanvasLayer
# ═══════════════════════════════════════════════════════════════
#  HUD.gd — 年轮式状态 UI (纯净树木版)
#  底部：外圈=经验进度，中心=根据血量切换的树木贴图
# ═══════════════════════════════════════════════════════════════

@onready var exp_ring: TextureProgressBar = $HUDMargin/HUDContainer/RingContainer/ExpRing
@onready var level_label: Label = $HUDMargin/HUDContainer/RingContainer/LevelLabel
@onready var wave_label: Label = $HUDMargin/HUDContainer/WaveLabel
@onready var stage_label: Label = $HUDMargin/HUDContainer/StageLabel
@onready var pause_button: Button = $TopRightAnchor/MarginContainer/VBoxContainer/HBoxContainer/PauseButton

@onready var timer_label: Label = $TopRightAnchor/MarginContainer/VBoxContainer/HBoxContainer/TimerLabel
@onready var tree_hp_display: TextureRect = $TreeHpDisplay

# 🔥 配置不同血量阶段的树木贴图
@export var hp_tree_textures: Array[Texture2D] = []
# 🎵 形态切换音效
@export var 状态切换_sfx: AudioStream 

# 用来记录当前树木处于第几个形态。初始设为 -1 代表“还没初始化”
var current_tree_index: int = -1

var hp_label: Label

func _ready():
	# 监听 SignalBus 事件
	SignalBus.on_player_hp_changed.connect(_on_hp_changed)
	SignalBus.on_exp_gained.connect(_on_exp_gained)
	SignalBus.on_level_up.connect(_on_level_up)
	SignalBus.on_wave_started.connect(_on_wave_started)
	
	# 退出按鈕
	pause_button.pressed.connect(func(): SignalBus.on_pause_requested.emit())
	
	# 初始化显示
	_update_tree_shape(1.0)
	exp_ring.value = 0
	level_label.text = "Lv.1"
	wave_label.text = "WAVE 1"
	
	_apply_hud_styles()
	
	# 动态创建并挂载一个用于显示具体血量数字的Label
	hp_label = Label.new()
	tree_hp_display.add_child(hp_label)
	hp_label.anchor_left = 1.0
	hp_label.anchor_right = 1.0
	hp_label.anchor_top = 0.5
	hp_label.anchor_bottom = 0.5
	hp_label.offset_left = 15.0 # 向右偏移一点
	hp_label.offset_top = -20.0 # 居中对齐稍微往上拉一点
	
	hp_label.add_theme_font_size_override("font_size", 32)
	hp_label.add_theme_color_override("font_color", Color(0.95, 0.35, 0.40, 1.0))
	hp_label.add_theme_color_override("font_outline_color", Color(0.15, 0.05, 0.05, 1.0))
	hp_label.add_theme_constant_override("outline_size", 10)
	
	hp_label.text = str(int(GameData.current_hp)) + " / " + str(int(GameData.player_base_stats.get("max_hp", 100)))
	
	var visual_idx = GameData.current_playing_stage - 1
	if GameData.is_endless_mode:
		visual_idx = GameData.selected_sapling - 1
	if visual_idx >= 0 and visual_idx < GameData.growth_stages.size():
		stage_label.text = GameData.growth_stages[visual_idx]["name"]
	else:
		stage_label.text = "异变神木"

func _apply_hud_styles():
	var label_style = StyleBoxFlat.new()
	label_style.bg_color = Color(0.12, 0.08, 0.05, 0.8) 
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
	_update_tree_shape(ratio)
	
	if is_instance_valid(hp_label):
		hp_label.text = str(int(current_hp)) + " / " + str(int(max_hp))

# 👇 精准匹配 5 张图，并在形态改变时闪光 + 播放音效
func _update_tree_shape(ratio: float):
	if hp_tree_textures.is_empty() or not is_instance_valid(tree_hp_display):
		return
		
	var target_index: int = 0
	
	if ratio <= 0.20:
		target_index = 0
	elif ratio <= 0.40:
		target_index = 1
	elif ratio <= 0.60:
		target_index = 2
	elif ratio <= 0.80:
		target_index = 3
	else:
		target_index = 4
		
	target_index = clampi(target_index, 0, hp_tree_textures.size() - 1)
	
	# 只有当形态发生实质性改变时，才执行后续逻辑
	if target_index != current_tree_index:
		tree_hp_display.texture = hp_tree_textures[target_index]
		
		# 排除掉游戏刚启动时的默认加载
		if current_tree_index != -1:
			# 1. 调用强力闪光弹跳动画
			_play_shape_change_flash()
			
			# 2. 播放全局音效
			if 状态切换_sfx:
				AudioManager.play_sfx(状态切换_sfx, 10, false)
				
		# 更新记忆
		current_tree_index = target_index

# 形态切换时的专属闪耀弹跳特效
func _play_shape_change_flash():
	if not is_instance_valid(tree_hp_display): return
	
	var tween = create_tween().set_parallel(true)
	# 瞬间爆白
	tree_hp_display.modulate = Color(10.0, 10.0, 10.0, 1.0) 
	tween.tween_property(tree_hp_display, "modulate", Color.WHITE, 0.3).set_trans(Tween.TRANS_CUBIC)
	# Q 弹放大
	tree_hp_display.scale = Vector2(1.3, 1.3)
	tween.tween_property(tree_hp_display, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)

func _on_exp_gained(exp_ratio: float):
	exp_ring.value = exp_ratio * 100.0

func _on_level_up(new_level: int):
	level_label.text = "Lv." + str(new_level)
	exp_ring.value = 0
	_play_level_up_flash()

func _on_wave_started(wave_number: int):
	wave_label.text = "WAVE " + str(wave_number)

# 升级时的闪光特效
func _play_level_up_flash():
	if not is_instance_valid(tree_hp_display): return
	var tween = create_tween()
	tween.tween_property(tree_hp_display, "modulate", Color(2.0, 2.0, 2.0, 1.0), 0.15)
	tween.tween_property(tree_hp_display, "modulate", Color.WHITE, 0.3)

func update_timer(time_left: float):
	timer_label.text = "时间: %.1f s" % time_left
