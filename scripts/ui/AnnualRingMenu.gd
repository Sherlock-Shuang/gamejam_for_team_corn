extends Node2D
# ═══════════════════════════════════════════════════════════════
#  AnnualRingMenu.gd — 年轮选关界面 (大地图)
#  通过 4 层树木年轮的 _small / _big 贴图切换实现关卡选择。
# ═══════════════════════════════════════════════════════════════

@export var UI交互_sfx :AudioStream
@export var click_sfx :AudioStream
@export var reversal_sfx :AudioStream

var center: Vector2 = Vector2(960, 540)
var hovered_stage: int = -1
var time_elapsed: float = 0.0

# --- 时空倒转演出变量 ---
var is_cinematic_playing: bool = false
var ring_speeds: Array[float] = [0.0, 0.0, 0.0, 0.0] # 4层年轮的实时转速
var crack_speed: float = 0.0                        # 中央裂痕的实时转速
var cinematic_timer: float = 0.0                    # 剧情计时器
var input_blocker: Control = null
var reversal_player: AudioStreamPlayer


@onready var ring_container: Node2D = $RingContainer
@onready var endless_crack: Sprite2D = $RingContainer/EndlessCrack
@onready var camera = $Camera2D
@onready var background = $Background # 对应之前修改后的名字，如果是 Node2D 下的 ColorRect
@onready var layers = {
	1: $RingContainer/Layer1,
	2: $RingContainer/Layer2,
	3: $RingContainer/Layer3,
	4: $RingContainer/Layer4
}

# 纹理池
var textures_small = {}
var textures_big = {}

# 判定半径：基于圆形的精准判定区间
const BASE_RADII = {
	"ENDLESS": 60.0,
	1: 130.0,
	2: 200.0,
	3: 270.0,
	4: 330.0
}

@onready var subtitle = $UI/Control/Subtitle
@onready var quit_button = $UI/Control/QuitButton

func _ready():
	reversal_player = AudioStreamPlayer.new()
	add_child(reversal_player)
	reversal_player.stream = reversal_sfx
	reversal_player.volume_db = 0  # 正常音量，可根据需要调整，可根据需要修改
	
	quit_button.pressed.connect(func(): get_tree().quit())
	GameData.is_endless_mode = false
	
	# 初始化纹理缓存 (对应 assets 目录下的资源)
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
	ring_container.scale = Vector2(1.3, 1.3)
	_update_positions()
	
	# 【核心逻辑】：判断是否刚从最终战归来，触发史诗级过场
	if GameData.just_finished_final_stage:
		_start_reversal_cinematic()
		GameData.just_finished_final_stage = false # 重置状态，防止反复触发
	elif GameData.is_endless_unlocked:
		# 如果已经通关过，保持常态慢速旋转
		for i in range(4):
			ring_speeds[i] = 0.15 + (i * 0.05)


func _process(delta):
	time_elapsed += delta
	_update_positions()
	
	# 刷新年轮与裂痕的旋转
	_apply_rotations(delta)
	
	# 如果正在进行结局剧场
	if is_cinematic_playing:
		# 裂痕开始逆时针疯狂加速 (速度不断累加)
		crack_speed -= delta * 15.0 
		cinematic_timer += delta
		
		# 音效逐渐加快
		if reversal_player.playing:
			reversal_player.pitch_scale += delta * 0.5  # 每秒增加0.5，可调整这个值来控制加快速度
		
		# 5秒后进入最终转场
		if cinematic_timer >= 5.0:
			_play_ending_video()
			is_cinematic_playing = false # 停止后续判定
	
	# 副标题呼吸动效
	if subtitle:
		var alpha = (sin(time_elapsed * 2.0) + 1.0) / 2.0 * 0.4 + 0.3
		subtitle.modulate.a = alpha

	
	# 鼠标悬停判定
	var mouse_pos = get_global_mouse_position()
	var dist = mouse_pos.distance_to(center) / ring_container.scale.x
	
	var current_hover = -1
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

func _on_hover_changed(new_stage: int):
	_set_node_state(hovered_stage, false)
	hovered_stage = new_stage
	_set_node_state(hovered_stage, true)
	
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
		# 悬停时的亮度反馈
		var tween = create_tween().set_parallel(true)
		var target_mod = Color(1.2, 1.2, 1.15, 1.0) if active else Color.WHITE
		tween.tween_property(node, "modulate", target_mod, 0.15)

func _update_layer_visibility():
	if endless_crack:
		endless_crack.visible = GameData.is_endless_unlocked
	for stage_id in layers.keys():
		var layer = layers[stage_id]
		if layer:
			# 严格逻辑：未通过前置关卡，外部年轮不可见
			layer.visible = (stage_id <= GameData.current_max_stage)


# ── 结局过场演出逻辑 ───────────────────────────────────────────

func _start_reversal_cinematic():
	print("[AnnualRingMenu] 警告：检测到时空不稳定性，启动倒转剧场...")
	is_cinematic_playing = true
	cinematic_timer = 0.0
	
	# 开始播放时钟逆转音效
	if reversal_player and reversal_sfx:
		reversal_player.pitch_scale = 1.0  # 重置pitch
		reversal_player.play()
	
	# 1. 屏蔽所有输入 (添加到 UI 层)
	input_blocker = Control.new()
	input_blocker.set_anchors_preset(Control.PRESET_FULL_RECT)
	input_blocker.mouse_filter = Control.MOUSE_FILTER_STOP
	# 显式覆盖整个画布
	input_blocker.size = get_viewport_rect().size
	if $UI:
		$UI.add_child(input_blocker)
	else:
		add_child(input_blocker)
	
	if subtitle:
		subtitle.text = "时 光 倒 流 . . ."
	
	# 2. 年轮顺次爆发自转 (Tween 接力)
	var tween = create_tween().set_parallel(true)
	for i in range(4):
		# 【关键修复】：索引闭包锁定
		var idx = i 
		var delay = idx * 0.5
		var target_speed = 5.0 + (idx * 2.5) # 外圈转得更快更疯狂
		
		# 使用 tween_method 直接动态修改数组内的值
		tween.tween_method(
			func(v: float): ring_speeds[idx] = v, 
			ring_speeds[idx], 
			target_speed, 
			1.5
		).set_delay(delay).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_IN)



func _apply_rotations(delta):
	# 更新 4 层年轮
	for i in range(4):
		var layer = layers.get(i + 1)
		if layer:
			layer.rotation += ring_speeds[i] * delta
	
	# 更新中央裂痕 (倒转)
	if endless_crack:
		endless_crack.rotation += crack_speed * delta

func _play_ending_video():
	print("[AnnualRingMenu] 时空已锁定。启动最终视频播放逻辑...")
	
	# 停止所有当前正在播放的声音 (由 AudioManager 处理或直接停止播放器)
	if reversal_player.playing:
		reversal_player.stop()
	
	# 🎵 可选：让大管家也清静一下
	AudioManager.stop_all()
	
	# 真正进入结尾视频场景
	get_tree().change_scene_to_file("res://scenes/ui/EndingVideo.tscn")


func _input(event):
	# 调试快捷键
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_R:
			GameData.reset_all_progress()
			_update_layer_visibility()
			if subtitle: subtitle.text = "进度已重置，从第一关开始吧"
		elif event.keycode == KEY_U:
			GameData.unlock_all()
			_update_layer_visibility()
			if subtitle: subtitle.text = "力量已觉醒，所有年轮已开启"

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if hovered_stage >= 1:
			if click_sfx: AudioManager.play_sfx(click_sfx, 0.0, false, 1)
			GameData.current_playing_stage = hovered_stage
			get_tree().change_scene_to_file("res://Main.tscn")
		elif hovered_stage == -2:
			if click_sfx: AudioManager.play_sfx(click_sfx, 0.0, false, 1)
			GameData.is_endless_mode = true
			get_tree().change_scene_to_file("res://scenes/ui/EndlessSelectUI.tscn")

func _update_positions():

	var viewport_size = get_viewport_rect().size
	center = viewport_size / 2.0
	
	# 让年轮容器始终位于屏幕正中央
	if ring_container:
		ring_container.position = center
		
	# 让摄像机也跟着动，确保 0,0 坐标误差不会导致偏移
	if camera:
		camera.position = center
		
	# 强行拉伸背景色块，覆盖整个屏幕
	if background:
		background.size = viewport_size
		background.position = Vector2.ZERO
