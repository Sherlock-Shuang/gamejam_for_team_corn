extends Node2D
# ═══════════════════════════════════════════════════════════════
#  AnnualRingMenu.gd — 年轮选关界面 (大地图)
#  通过 5 层树木年轮的 _small / _big 贴图切换实现关卡选择。
# ═══════════════════════════════════════════════════════════════

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
	"vine_spread": "res://assets/sprites/effects/vine.png",
	"seed_bomb": "res://assets/sprites/effects/种子.png",
	"fire_enchant": "res://assets/sprites/effects/4fruits.png", # 权宜方案：使用水果包
	"ice_enchant": "res://assets/sprites/effects/flash3.png", # 权宜方案：蓝色闪电
	"lightning_enchant": "res://assets/sprites/effects/flash2.png",
	"thick_bark": "res://assets/sprites/trees/1h.png", # 权宜方案：使用树皮纹理
	"deep_roots": "res://assets/sprites/trees/vine.png",
	"wide_canopy": "res://assets/sprites/trees/1l.png",
	"elastic_trunk": "res://assets/sprites/trees/2h.png",
	"photosynthesis": "res://assets/sprites/effects/shade.png"
}

func _ready():
	print("[Menu] 欢迎来到精准版年轮界面。解锁关卡: ", GameData.current_max_stage)
	quit_button.pressed.connect(func(): get_tree().quit())
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
	
	# 确保容器状态
	ring_container.scale = Vector2(1.3, 1.3)
	
	_update_positions()
	
	# 渲染历史技能效果
	_render_skill_history()

func _render_skill_history():
	# 技能渲染容器
	var overlay = ring_container.get_node_or_null("SkillsOverlay")
	if overlay:
		overlay.queue_free()
	
	overlay = Node2D.new()
	overlay.name = "SkillsOverlay"
	ring_container.add_child(overlay)
	
	# 渲染前四关年轮上的技能
	for stage_id in range(1, 5):
		var skills = GameData.skill_history_per_stage.get(stage_id, [])
		if skills.is_empty(): continue
		
		# 每个年轮的放置半径 (取层半径区间的 50% 处，正中心)
		var inner_r = 0.0
		if stage_id == 1: inner_r = BASE_RADII["ENDLESS"]
		else: inner_r = BASE_RADII[stage_id - 1]
		var outer_r = BASE_RADII[stage_id]
		var radius = inner_r + (outer_r - inner_r) * 0.5
		
		_draw_skills_on_circle(overlay, skills, radius, stage_id)

func _draw_skills_on_circle(parent: Node2D, skills: Array, radius: float, stage_id: int):
	var count = skills.size()
	var angle_step = TAU / count
	# 为每个关卡提供一个基础偏移角，防止图标全叠在一起
	var base_angle = float(stage_id) * 0.8 
	
	for i in range(count):
		var skill_id = skills[i]
		var icon_path = SKILL_ICONS.get(skill_id, "")
		if icon_path == "": continue
		
		var sprite = Sprite2D.new()
		sprite.texture = load(icon_path)
		
		# 加大版：目标大小约 64 像素
		var texture_size = sprite.texture.get_size()
		var target_scale = 64.0 / max(texture_size.x, texture_size.y)
		sprite.scale = Vector2(target_scale, target_scale)
		
		# 极坐标转换
		var angle = base_angle + i * angle_step
		sprite.position = Vector2(cos(angle), sin(angle)) * radius
		
		# 添加一些旋转效果，让它们看起来像嵌在木头里
		sprite.rotation = angle + PI/2
		
		# 视觉微调：半透明效果和淡入
		sprite.modulate.a = 0.8
		parent.add_child(sprite)

func _process(delta):
	time_elapsed += delta
	_update_positions()
	
	# 副标题呼吸动效
	if subtitle:
		var alpha = (sin(time_elapsed * 2.0) + 1.0) / 2.0 * 0.4 + 0.3 # 保持浅色基调
		subtitle.modulate.a = alpha
	
	# 鼠标判定逻辑
	var mouse_pos = get_global_mouse_position()
	var dist = mouse_pos.distance_to(center) / ring_container.scale.x
	
	var current_hover = -1
	# 修正：将开启门槛从 > 4 降至 >= 4，确保通关后能稳定触发
	var can_show_endless = GameData.is_endless_unlocked and GameData.current_max_stage >= 4
	
	if can_show_endless and dist < BASE_RADII["ENDLESS"]:
		current_hover = -2
	elif dist < BASE_RADII[1]:
		current_hover = 1
	elif dist < BASE_RADII[2]:
		current_hover = 2
	elif dist < BASE_RADII[3]:
		current_hover = 3
	elif dist < BASE_RADII[4]:
		current_hover = 4
	
	# 只能悬停已解锁关卡
	if current_hover != -2 and current_hover > GameData.current_max_stage:
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
		
		# 细微的呼吸/亮度提升
		var tween = create_tween().set_parallel(true)
		var target_mod = Color(1.2, 1.2, 1.15, 1.0) if active else Color.WHITE
		tween.tween_property(node, "modulate", target_mod, 0.15)

func _update_layer_visibility():
	if endless_crack:
		# 修改为 >= 4，保证通关当前最后关卡后开启
		endless_crack.visible = GameData.is_endless_unlocked and GameData.current_max_stage >= 4
		
	for stage_id in layers.keys():
		var layer = layers[stage_id]
		# 严格逻辑：未通过前置关卡，外部年轮直接不可见
		layer.visible = (stage_id <= GameData.current_max_stage)

func _input(event):
	if event is InputEventKey and event.pressed:
		# R 键：重置进度为第一关
		if event.keycode == KEY_R:
			print("[Debug] 重置进度为第一关！")
			GameData.current_max_stage = 1
			GameData.is_endless_unlocked = false
			GameData.skill_history_per_stage.clear()
			GameData.save_game()
			_update_layer_visibility()
			_render_skill_history()
			
		# U 键：一键解锁全图及无尽模式
		elif event.keycode == KEY_U:
			print("[Debug] 一键全图全解锁！")
			GameData.current_max_stage = 4
			GameData.is_endless_unlocked = true
			_update_layer_visibility()
		
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if hovered_stage >= 1:
			GameData.current_playing_stage = hovered_stage
			get_tree().change_scene_to_file("res://Main.tscn")
		elif hovered_stage == -2:
			GameData.is_endless_mode = true
			get_tree().change_scene_to_file("res://scenes/ui/EndlessSelectUI.tscn")
