extends Node2D
# ═══════════════════════════════════════════════════════════════
#  AnnualRingMenu.gd — 年轮选关界面 (大地图)
#  通过 5 层树木年轮的 _small / _big 贴图切换实现关卡选择。
# ═══════════════════════════════════════════════════════════════

@export var UI交互_sfx :AudioStream
@export var click_sfx :AudioStream

var center: Vector2 = Vector2(960, 540)
var hovered_stage: int = -1
var time_elapsed: float = 0.0

@onready var ring_container: Node2D = $RingContainer
@onready var shell: Sprite2D = $RingContainer/Shell
@onready var endless_crack: Sprite2D = $RingContainer/EndlessCrack
@onready var layers = {
	1: $RingContainer/Layer1,
	2: $RingContainer/Layer2,
	3: $RingContainer/Layer3,
	4: $RingContainer/Layer4
}

# 旋转控速 (改为独立变量，确保 Tween 路径解析 100% 成功)
var rot_speed_1: float = 0.0
var rot_speed_2: float = 0.0
var rot_speed_3: float = 0.0
var rot_speed_4: float = 0.0
var endless_rot_speed: float = 0.0

# 纹理池 (对应 .tscn 中的 ExtResource ID)
var textures_small = {}
var textures_big = {}

# 判定半径 最终精准版：直接应用用户指定的精确区间
const BASE_RADII = {
	"ENDLESS": 60.0,
	1: 130.0,
	2: 200.0,
	3: 270.0,
	4: 330.0
}

@onready var subtitle = $UI/Control/Subtitle
@onready var quit_button = $UI/Control/QuitButton

# 纹理映射：将技能 ID 与对应的 UI 图标关联
const SKILL_ICONS = {
	"thorn_shot": "res://assets/sprites/effects/毒刺.png",
	"exploding_fruit": "res://assets/sprites/effects/爆炸果.png",
	"lightning_field": "res://assets/sprites/effects/flash1.png",
	"vine_spread": "res://assets/sprites/effects/4rattan.png",
	"seed_bomb": "res://assets/sprites/effects/种子.png",
	"fire_enchant": "res://assets/sprites/effects/4fruits.png", 
	"ice_enchant": "res://assets/sprites/effects/flash3.png", 
	"lightning_enchant": "res://assets/sprites/effects/electric.png", # 区分于球状闪电
	"thick_bark": "res://assets/sprites/trees/1h.png",
	"deep_roots": "res://assets/sprites/effects/4rattan.png", # 使用藤蔓图标
	"wide_canopy": "res://assets/sprites/trees/1l.png",
	"elastic_trunk": "res://assets/sprites/trees/2h.png",
	"photosynthesis": "res://assets/sprites/effects/shade.png"
}

# 针对某些“太小”的图标进行特异性缩放增强
const SKILL_SCALES = {
	"lightning_field": 1.5,   # 紫色球状闪电，用户反馈太小，放大
	"photosynthesis": 1.4,    # 可能是另一个紫色图标
	"lightning_enchant": 1.2,
	"fire_enchant": 1.4,
	"ice_enchant": 1.4,
	"vine_spread": 1.3,
	"deep_roots": 1.3
}

func _ready():
	print("[Menu] 欢迎来到精准版年轮界面。解锁关卡: ", GameData.current_max_stage)
	quit_button.pressed.connect(func(): 
		if click_sfx: AudioManager.play_sfx(click_sfx, 0.0, false, 1)
		get_tree().quit()
	)
	GameData.is_endless_mode = false
	
	# 初始化纹理缓存
	textures_small = {
		1: load("res://assets/sprites/UI/wood/1small.png"),
		2: load("res://assets/sprites/UI/wood/2_small.png"),
		3: load("res://assets/sprites/UI/wood/3_small.png"),
		4: load("res://assets/sprites/UI/wood/4_small.png"),
		-2: load("res://assets/sprites/UI/wood/hurt_small.png")
	}
	textures_big = {
		1: load("res://assets/sprites/UI/wood/1_big.png"),
		2: load("res://assets/sprites/UI/wood/2_big.png"),
		3: load("res://assets/sprites/UI/wood/3_big.png"),
		4: load("res://assets/sprites/UI/wood/4_big.png"),
		-2: load("res://assets/sprites/UI/wood/hurt_big.png")
	}
	
	# 初始化显示状态 (锁定即隐藏)
	_update_layer_visibility()
	
	# 确保容器状态与层中心对齐
	ring_container.scale = Vector2(1.3, 1.3)
	for layer in layers.values():
		layer.position = Vector2.ZERO
		layer.centered = true
	
	_update_positions()

func _process(delta):
	time_elapsed += delta
	_update_positions()
	
	# 如果是真结局剧情演绎期间，强制清空悬停状态并加速旋转
	if GameData.just_finished_final_stage:
		_on_hover_changed(-1)
		_apply_rotations(delta)
		return
		
	_apply_rotations(delta)
	
	# 副标题呼吸动效
	if subtitle:
		var alpha = (sin(time_elapsed * 2.0) + 1.0) / 2.0 * 0.4 + 0.3 # 保持浅色基调
		if GameData.just_finished_final_stage:
			subtitle.text = "【 宿命流转：遗落的森林正在重现... 】"
			subtitle.modulate = Color(1.0, 0.9, 0.3, alpha)
		else:
			subtitle.modulate.a = alpha

func _apply_rotations(delta):
	if layers.has(1): layers[1].rotation += rot_speed_1 * delta
	if layers.has(2): layers[2].rotation += rot_speed_2 * delta
	if layers.has(3): layers[3].rotation += rot_speed_3 * delta
	if layers.has(4): layers[4].rotation += rot_speed_4 * delta
	if endless_rot_speed != 0 and is_instance_valid(endless_crack):
		endless_crack.rotation += endless_rot_speed * delta
	
	if GameData.just_finished_final_stage:
		return # 结局期间不需要鼠标判定
		
	# 鼠标判定逻辑
	var mouse_pos = get_global_mouse_position()
	var dist = mouse_pos.distance_to(center) / ring_container.scale.x
	
	var current_hover = -1
	
	if dist < BASE_RADII["ENDLESS"]:
		current_hover = -2
	elif dist < BASE_RADII[1]:
		current_hover = 1
	elif dist < BASE_RADII[2]:
		current_hover = 2
	elif dist < BASE_RADII[3]:
		current_hover = 3
	elif dist < BASE_RADII[4]:
		current_hover = 4
	
	# 【核心规则】：只能挑战当前正在挑战的唯一关卡，或者深渊裂痕(无尽模式)
	var is_fully_unlocked = GameData.is_endless_unlocked
	
	if current_hover == -2:
		# 无尽模式必须解锁才行
		if not is_fully_unlocked: current_hover = -1
	elif current_hover != -1:
		# 普通关卡逻辑
		if is_fully_unlocked:
			# 全通关后：允许选中第 1 关重新开始，或者挑战无尽模式
			if current_hover != 1:
				current_hover = -1
		else:
			# 还没通关：允许选中第 1 关（随时轮回）或者当前的最高进度关卡
			if current_hover != 1 and current_hover != GameData.current_max_stage:
				current_hover = -1
		
	if current_hover != hovered_stage:
		_on_hover_changed(current_hover)

func _update_positions():
	var viewport_size = get_viewport_rect().size
	center = viewport_size / 2.0
	if ring_container:
		ring_container.position = center
	if has_node("Background"):
		$Background.size = viewport_size
	if has_node("Camera2D"):
		$Camera2D.position = center

func _on_hover_changed(new_stage: int):
	_set_node_state(hovered_stage, false)
	hovered_stage = new_stage
	_set_node_state(hovered_stage, true)
	
	# 🎵 新增：如果悬停到了有效的关卡（1~4 或者是深渊 -2），播放悬停音效
	if hovered_stage != -1 and UI交互_sfx:
		AudioManager.play_sfx(UI交互_sfx, -5.0, true, 2)
	
	if hovered_stage == -2:
		subtitle.text = "【 深渊裂痕：开启无尽挑战 】"
	elif hovered_stage != -1:
		subtitle.text = "点击进入 关卡 " + str(hovered_stage)
	else:
		subtitle.text = "悬停选择年轮节点，点击进入挑战"

func _set_node_state(stage_id: int, active: bool):
	if stage_id == -1: return
	
	var node: Sprite2D = null
	if stage_id == -2: node = endless_crack
	elif layers.has(stage_id): node = layers[stage_id]
	
	if node and textures_small.has(stage_id) and textures_big.has(stage_id):
		node.texture = textures_big[stage_id] if active else textures_small[stage_id]
		
		# 细微的呼吸/亮度提升。注：非活跃层在 _update_layer_visibility 中调节了基础亮度
		var tween = create_tween().set_parallel(true)
		var base_color = node.modulate # 获取当前层的基础显示色
		var target_mod = base_color * 1.3 if active else base_color
		tween.tween_property(node, "modulate", target_mod, 0.15)

func _update_layer_visibility():
	if endless_crack:
		endless_crack.visible = GameData.is_endless_unlocked
		# 如果解锁了，处于高亮状态，否则半透明
		endless_crack.modulate = Color(1.2, 1.2, 1.1, 1.0) if GameData.is_endless_unlocked else Color(1, 1, 1, 0.2)
		
	for stage_id in layers.keys():
		var layer = layers[stage_id]
		# 规则：已全通关 -> 所有普通年轮变灰褐色进入“历史模式”，但第 1 关保持高亮供重新开始
		if GameData.is_endless_unlocked:
			layer.visible = true
			if stage_id == 1:
				layer.modulate = Color(1.0, 1.0, 1.0, 1.0) # 重新开始的入口
			else:
				layer.modulate = Color(0.4, 0.38, 0.35, 1.0) 
		else:
			# 未通关：第 1 关和当前进度层最亮，其余已通过层变暗，未解锁层隐藏
			if stage_id == 1 or stage_id == GameData.current_max_stage:
				layer.visible = true
				layer.modulate = Color(1.0, 1.0, 1.0, 1.0)
			elif stage_id < GameData.current_max_stage:
				layer.visible = true
				layer.modulate = Color(0.5, 0.45, 0.4, 1.0)
			else:
				layer.visible = false

# ── 神秘时钟启动序列 ───────────────────────────────────────────
func _start_mystic_rotation_sequence():
	var tw = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	
	# 逐层启动，速度由内向外递减
	tw.tween_property(self, "rot_speed_1", 0.35, 1.2)
	tw.parallel().tween_interval(0.5)
	
	tw.chain().tween_property(self, "rot_speed_2", 0.25, 1.2)
	tw.parallel().tween_interval(0.5)
	
	tw.chain().tween_property(self, "rot_speed_3", 0.18, 1.2)
	tw.parallel().tween_interval(0.5)
	
	tw.chain().tween_property(self, "rot_speed_4", 0.12, 1.2)
	tw.parallel().tween_interval(0.8)
	
	# 最后中心斧痕开始“倒计时”逆时针旋转
	tw.chain().tween_property(self, "endless_rot_speed", -1.0, 2.0)
	
	print("[Menu] 终极结局动画：年轮时钟已全速启动")

func _perform_final_scene_transition():
	# 等待所有年轮转速加满 (约 4 秒)，再额外停留 3 秒
	await get_tree().create_timer(7.0).timeout
	
	# 重置标记，防止下次进菜单又自动转场
	GameData.just_finished_final_stage = false
	
	# 华丽的黑屏转场
	var fade = CanvasLayer.new()
	var rect = ColorRect.new()
	rect.color = Color(0, 0, 0, 0)
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	fade.add_child(rect)
	add_child(fade)
	
	var tw = create_tween()
	tw.tween_property(rect, "color:a", 1.0, 1.5)
	await tw.finished
	
	# 进入你创建的森林万木长青场景
	get_tree().change_scene_to_file("res://scenes/world/ForestEnding.tscn")

func _input(event):
	if GameData.just_finished_final_stage:
		return # 结局演绎期间，一切输入无效
		
	if event is InputEventKey and event.pressed:
		# R 键：重置进度为第一关
		if event.keycode == KEY_R:
			print("[Debug] 重置进度为第一关！")
			GameData.current_max_stage = 1
			GameData.is_endless_unlocked = false
			GameData.skill_history_per_stage.clear()
			GameData.save_game()
			_update_layer_visibility()
			
		# U 键：一键解锁全图及无尽模式
		elif event.keycode == KEY_U:
			print("[Debug] 一键全图全解锁！")
			GameData.current_max_stage = 4
			GameData.is_endless_unlocked = true
			_update_layer_visibility()
		
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if hovered_stage >= 1:
			# 🎵 新增：播放确认进入音效
			if click_sfx:
				AudioManager.play_sfx(click_sfx, 0.0, false, 1)
				
			GameData.current_playing_stage = hovered_stage
			get_tree().change_scene_to_file("res://Main.tscn")
			
		elif hovered_stage == -2:
			# 🎵 新增：播放确认进入音效
			if click_sfx:
				AudioManager.play_sfx(click_sfx, 0.0, false, 1)
				
			GameData.is_endless_mode = true
			get_tree().change_scene_to_file("res://scenes/ui/EndlessSelectUI.tscn")
