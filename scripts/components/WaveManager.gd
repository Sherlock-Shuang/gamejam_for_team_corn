extends Node2D

# --- 核心配置 ---
@export var base_wave_interval: float = 3.0   # 基础每波间隔时间
@export var spawn_radius: float = 1000.0      # 生成半径
@export var min_spawn_distance: float = 380.0
@export var spawn_uniform_jitter: float = 0.35
@export var spawn_retry_limit: int = 8

@onready var timer: Timer = $WaveTimer
var target_tree: Node2D = null
var current_wave: int = 0                     # 当前波次记录

func _ready() -> void:
	_find_target_tree()
		
	timer.wait_time = base_wave_interval
	timer.timeout.connect(_on_wave_timeout)
	timer.start()
	
	_on_wave_timeout()

func _find_target_tree():
	var trees = get_tree().get_nodes_in_group("Tree")
	if trees.size() > 0:
		target_tree = trees[0]
	else:
		target_tree = null

func _on_wave_timeout() -> void:
	if not is_instance_valid(target_tree):
		_find_target_tree()
		if not is_instance_valid(target_tree):
			return
	
	current_wave += 1
	# 可以顺手把当前波次同步给全局，方便 UI 显示或控制难度
	GameData.current_wave = current_wave 
	
	# ==========================================
	# 🎯 难度曲线与刷怪字典 (Game Jam 极速配置法)
	# ==========================================
	var enemies_to_spawn = 10 + (current_wave * 3) # 怪物总数随波次递增
	var fly_ratio = 1.0    # 飞虫生成概率
	var beaver_ratio = 0.0 # 河狸生成概率
	
	# 阶段一 (1~4波)：纯自然虫害，100% 飞虫，让玩家爽快割草升级
	
	# 阶段二 (第5波开始)：河狸入场，打乱阵型
	if current_wave >= 5:
		fly_ratio = 0.7
		beaver_ratio = 0.3
		
	# 阶段三 (第10波开始)：河狸成为主力，压迫感剧增！
	if current_wave >= 10:
		fly_ratio = 0.3
		beaver_ratio = 0.7
		enemies_to_spawn += 10 # 额外加压
		
	# ==========================================
	# ⚙️ 核心生成逻辑
	# ==========================================
	var center_pos = target_tree.global_position
	var spawn_positions = get_uniform_spawn_positions(center_pos, enemies_to_spawn)
	for i in range(enemies_to_spawn):
		var random_delay = randf_range(0.0, timer.wait_time)
		var spawn_pos = spawn_positions[i]
		
		# 🎲 随机池抽取机制：决定这只怪是什么类型
		var enemy_type_to_spawn = "fly" 
		var roll = randf() # 掷骰子：得到一个 0.0 到 1.0 的随机数
		
		if roll > fly_ratio: 
			enemy_type_to_spawn = "beaver"
			
		# 异步延迟生成：通过 bind 传递局部变量，防止闭包捕获到循环最终值导致怪物重叠
		var spawn_func = func(target_spawn_pos: Vector2, type: String):
			if not is_instance_valid(target_tree):
				return
			PoolManager.get_enemy(type, target_spawn_pos)
			
		get_tree().create_timer(random_delay, false).timeout.connect(spawn_func.bind(spawn_pos, enemy_type_to_spawn))

func get_uniform_spawn_positions(center_pos: Vector2, count: int) -> Array[Vector2]:
	var points: Array[Vector2] = []
	if count <= 0:
		return points
	var start_angle = PI + randf_range(0.0, PI / float(count))
	var segment = PI / float(count)
	var jitter = segment * clampf(spawn_uniform_jitter, 0.0, 0.49)
	for i in range(count):
		var angle = start_angle + segment * float(i) + randf_range(-jitter, jitter)
		angle = clampf(angle, PI, TAU)
		points.append(get_spawn_position_with_river_rule(center_pos, angle))
	return points

func get_spawn_position_with_river_rule(center_pos: Vector2, angle: float) -> Vector2:
	var min_r = maxf(0.0, minf(min_spawn_distance, spawn_radius - 1.0))
	var max_r = maxf(min_r + 1.0, spawn_radius)
	for _attempt in range(max(1, spawn_retry_limit)):
		var dist = sqrt(lerpf(min_r * min_r, max_r * max_r, randf()))
		var spawn_pos = center_pos + Vector2.from_angle(angle) * dist
		if spawn_pos.distance_to(center_pos) < min_spawn_distance:
			continue
		if GameData.is_in_river(spawn_pos):
			continue
		return spawn_pos
	var fallback = center_pos + Vector2.from_angle(angle) * max_r
	if fallback.distance_to(center_pos) < min_spawn_distance:
		fallback = center_pos + Vector2.UP * min_spawn_distance
	if GameData.is_in_river(fallback):
		fallback = center_pos + Vector2.UP * max_r
	return GameData.clamp_to_river_bank(fallback, 24.0)
		
