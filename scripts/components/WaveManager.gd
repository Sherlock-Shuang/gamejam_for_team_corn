extends Node

# --- 波次配置参数 ---
@export var wave_interval: float = 3.0   # 这波怪物在几秒内刷完
@export var enemies_per_wave: int = 10   # 这波总共刷多少只
@export var spawn_radius: float = 1000.0  # 生成半径

@onready var timer: Timer = $WaveTimer
var target_tree: Node2D = null

func _ready() -> void:
	# 寻找靶子树
	_find_target_tree()
		
	# 初始化波次循环计时器
	timer.wait_time = wave_interval
	timer.timeout.connect(_on_wave_timeout)
	timer.start()
	
	# 游戏开始立刻触发第一波
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

		
	# 遍历这波需要生成的所有怪物
	for i in range(enemies_per_wave):
		
		# 1. 核心算法：各方向概率相等的随机角度
		# Godot 里的 TAU 就等于 2 * PI (即 360 度)。randf_range 保证了概率的绝对均匀。
		var random_angle = randf_range(0.0, TAU)
		
		# 2. 核心算法：生成时间随机，且在 wave_interval 内概率相等
		var random_delay = randf_range(0.0, wave_interval)
		
		# 3. 异步延迟生成 (利用 Godot 4 的 Lambda 闭包)
		# 意思是：创建一个一次性的后台计时器，等 random_delay 秒后，执行内部的代码
		get_tree().create_timer(random_delay, false).timeout.connect(func():
			# 闭包内再次检查树是否存活，防止树死了还在刷怪报错
			if not is_instance_valid(target_tree): 
				return
			
			# 实时获取树的最新坐标（防止树如果有微小位移时刷错地方）
			var center_pos = target_tree.global_position
			var spawn_pos = center_pos + Vector2(cos(random_angle), sin(random_angle)) * spawn_radius
			
			# 调用全局对象池生成
			PoolManager.get_enemy(spawn_pos)
		)
		
	# 增加下一波的压力
	enemies_per_wave += 5
