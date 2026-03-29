extends Node2D

# --- 核心配置 ---
@export var base_wave_interval: float = 3.0   # 基础每波间隔时间
@export var spawn_radius: float = 1000.0      # 生成半径

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
	for i in range(enemies_to_spawn):
		var random_angle = randf_range(0.0, TAU)
		var random_delay = randf_range(0.0, timer.wait_time)
		
		# 🎲 随机池抽取机制：决定这只怪是什么类型
		var enemy_type_to_spawn = "fly" 
		var roll = randf() # 掷骰子：得到一个 0.0 到 1.0 的随机数
		
		if roll > fly_ratio: 
			enemy_type_to_spawn = "beaver"
			
		# 异步延迟生成：通过 bind 传递局部变量，防止闭包捕获到循环最终值导致怪物重叠
		var spawn_func = func(angle: float, type: String):
			if not is_instance_valid(target_tree): return
			var center_pos = target_tree.global_position
			var spawn_pos = center_pos + Vector2(cos(angle), sin(angle)) * spawn_radius
			PoolManager.get_enemy(type, spawn_pos)
			
		get_tree().create_timer(random_delay, false).timeout.connect(spawn_func.bind(random_angle, enemy_type_to_spawn))
		
