extends Node2D
# ═══════════════════════════════════════════════════════════════
#  AnnualRingMenu.gd — 年轮选关界面 (大地图)
#  通过 _draw() 纯代码渲染同心圆年轮，作为美术贴图介入前的完整逻辑演示。
# ═══════════════════════════════════════════════════════════════

var center: Vector2 = Vector2(960, 540) # 屏幕中心（稍后在 _process 中动态获取视口大小以自适应）
var base_radius: float = 150.0          # 最内圈起始半径 (放大)
var ring_spacing: float = 160.0         # 每圈之间的距离 (放大)
var ring_thickness: float = 65.0        # 年轮线条的粗细 (放大)

var hovered_stage: int = -1             # 当前鼠标悬停在哪一关
var time_elapsed: float = 0.0

@onready var subtitle = $UI/Control/Subtitle
@onready var quit_button = $UI/Control/QuitButton

func _ready():
	print("[Menu] 欢迎来到树独年轮选单。当前最大关卡: ", GameData.current_max_stage)
	quit_button.pressed.connect(func(): get_tree().quit())
	GameData.is_endless_mode = false # 确保普通模式为主

func _process(delta):
	time_elapsed += delta
	
	# 动态获取视口中心，以适应全屏和不同分辨率拉伸
	var viewport_size = get_viewport_rect().size
	center = viewport_size / 2.0
	
	# 同步背景的尺寸（如果是通过代码控制的背景节点，也可通过 anchors 控制，这里加个保险）
	if has_node("Background"):
		$Background.size = viewport_size
		
	# 动态居中 Camera
	if has_node("Camera2D"):
		$Camera2D.position = center
	
	# 检测鼠标位置并推算指向哪一圈
	var mouse_pos = get_global_mouse_position()
	var dist = mouse_pos.distance_to(center)
	
	# 推算所在的 stage_id (1, 2, 3...)
	# 公式: index = (dist - base_radius + spacing/2) / spacing
	var est_stage = int(round((dist - base_radius) / ring_spacing)) + 1
	
	# 范围判定：只允许选中已解锁的关卡 (1 ~ current_max_stage)
	if est_stage >= 1 and est_stage <= GameData.current_max_stage:
		# 做个距离容差判定，避免点在条带外也算
		var target_r = base_radius + (est_stage - 1) * ring_spacing
		if abs(dist - target_r) <= ring_thickness / 2.0 * 1.5:
			if hovered_stage != est_stage:
				hovered_stage = est_stage
				subtitle.text = "点击进入 关卡 " + str(hovered_stage)
				queue_redraw()
		else:
			_clear_hover()
	elif GameData.is_endless_unlocked and dist < base_radius * 0.8:
		# 点击内心区域进入无尽模式
		if hovered_stage != -2:
			hovered_stage = -2
			subtitle.text = "【 深渊裂缝：无尽模式 】"
			queue_redraw()
	else:
		_clear_hover()
			
	# 由于外圈（当前最高进度）有呼吸动画，所以每帧都要求重绘
	queue_redraw()

func _clear_hover():
	if hovered_stage != -1:
		hovered_stage = -1
		subtitle.text = "悬停选择年轮节点，点击进入挑战"
		queue_redraw()

func _input(event):
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if hovered_stage >= 1:
			print("[Menu] 发车！进入关卡: Stage ", hovered_stage)
			GameData.current_playing_stage = hovered_stage
			get_tree().change_scene_to_file("res://Main.tscn")
		elif hovered_stage == -2:
			print("[Menu] 发车！进入无尽模式！")
			GameData.is_endless_mode = true
			get_tree().change_scene_to_file("res://scenes/ui/EndlessSelectUI.tscn")

func _draw():
	# 从最内圈画到最外圈
	for stage_id in range(1, GameData.current_max_stage + 1):
		var r = base_radius + (stage_id - 1) * ring_spacing
		
		# 基础颜色：老棕色（老树皮）
		var color = Color(0.35, 0.25, 0.15, 1.0) 
		
		# 特殊状态一：是最外圈的“当前可打关卡”，赋予生机勃勃的浅绿色/金黄色呼吸灯
		if stage_id == GameData.current_max_stage:
			var alpha_wave = (sin(time_elapsed * 3.0) + 1.0) / 2.0 * 0.4 + 0.6  # 0.6 ~ 1.0 呼吸
			color = Color(0.65, 0.75, 0.2, alpha_wave)
		
		# 特殊状态二：鼠标正在悬停它，给予高亮
		if stage_id == hovered_stage:
			color = color.lightened(0.3)
			
		# 画出这圈纯色的圆环
		draw_arc(center, r, 0, TAU, 64, color, ring_thickness, true)
		
		# ── 重点：绘制在这关拿到的“技能历史印记” ──
		if GameData.skill_history_per_stage.has(stage_id):
			var skills = GameData.skill_history_per_stage[stage_id]
			var count = skills.size()
			if count > 0:
				var angle_step = TAU / float(count)
				for i in range(count):
					# 为了美观，给每圈一个特定的起步旋转角度
					var angle_offset = stage_id * 0.5 
					var angle = angle_offset + i * angle_step
					var marker_pos = center + Vector2.RIGHT.rotated(angle) * r
					
					# 画一个镶嵌在年轮里的青蓝色小发光点表示获得了技能
					draw_circle(marker_pos, 10.0, Color(0.1, 0.9, 0.8))
					draw_circle(marker_pos, 5.0, Color(1.0, 1.0, 1.0))
					
					var skill_id = skills[i]
					if GameData.skill_pool.has(skill_id):
						var skill_name = GameData.skill_pool[skill_id]["name"]
						draw_string(ThemeDB.fallback_font, marker_pos + Vector2(15, 6), skill_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(0.9, 1.0, 0.5))
	
	# 绘制无尽模式的大刀裂痕
	if GameData.is_endless_unlocked:
		var max_r = base_radius + (GameData.current_max_stage - 1) * ring_spacing
		var crack_p1 = center - Vector2(max_r + 40, 0).rotated(0.3)
		var crack_p2 = center + Vector2(max_r + 40, 0).rotated(0.3)
		
		# 给裂缝一个发光脉冲
		var pulse = (sin(time_elapsed * 5.0) + 1.0) / 2.0 * 0.5 + 0.5
		var crack_color = Color(0.9, 0.1, 0.1, pulse)
		draw_line(crack_p1, crack_p2, crack_color, 8.0)
		draw_line(crack_p1, crack_p2, Color.WHITE, 2.0)
		
		# 核心高亮
		if hovered_stage == -2:
			draw_circle(center, base_radius * 0.8, Color(0.9, 0.2, 0.2, 0.4))
