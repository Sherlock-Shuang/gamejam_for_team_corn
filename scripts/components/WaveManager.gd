extends Node2D

@export var base_wave_interval: float = 4.0 
@export var spawn_radius: float = 1400.0
@export var min_spawn_distance: float = 1250.0

@export var spawn_uniform_jitter: float = 0.35
@export var spawn_retry_limit: int = 8

@onready var timer: Timer = $WaveTimer
var target_tree: Node2D = null
var current_wave: int = 0
const MAX_WAVES_PER_STAGE = 20 # 大幅增加上限，由 Main 的倒计时决定关卡结束

# ==========================================
# 🔥【性能核心】：全局出怪上限，防止无尽模式雪崩
# ==========================================
const MAX_ALIVE_ENEMIES: int = 250  # 同屏活跃敌人硬上限（已解除部分限制）
const MAX_PER_WAVE: int = 120       # 单波最大生成数（配合上限放宽）

func _ready() -> void:
	_find_target_tree()
	print("[WaveManager] _ready: is_endless=%s, stage=%d, target_tree=%s" % [GameData.is_endless_mode, GameData.current_playing_stage, target_tree])
	
	if not GameData.is_endless_mode:
		match GameData.current_playing_stage:
			1: base_wave_interval = 9.0
			2: base_wave_interval = 8.0
			3: base_wave_interval = 7.0
			4: base_wave_interval = 6.0
			_: base_wave_interval = 6.0
	else:
		base_wave_interval = 8.0

		
	timer.wait_time = base_wave_interval
	timer.timeout.connect(_on_wave_timeout)
	timer.start()
	
	var first_wave_delay = 0.5 if GameData.is_endless_mode else 1.5
	get_tree().create_timer(first_wave_delay).timeout.connect(_on_wave_timeout)
	print("[WaveManager] 定时器启动: interval=%.1f, first_delay=%.1f" % [base_wave_interval, first_wave_delay])

func _find_target_tree():
	var trees = get_tree().get_nodes_in_group("Tree")
	if trees.size() > 0:
		target_tree = trees[0]
	else:
		target_tree = null

## 🔥【性能优化】：统计当前场上活跃敌人数量
func _count_alive_enemies() -> int:
	var count = 0
	for child in PoolManager.get_children():
		if child.has_meta("pool_key") and child.process_mode != Node.PROCESS_MODE_DISABLED and child.visible:
			count += 1
	return count

func _on_wave_timeout() -> void:
	if not is_instance_valid(target_tree):
		_find_target_tree()
		if not is_instance_valid(target_tree):
			print("[WaveManager] 警告: 找不到目标树，跳过本波！")
			return
	
	if not GameData.is_endless_mode and current_wave >= MAX_WAVES_PER_STAGE:
		return 
		
	if GameData.is_endless_mode:
		var elapsed = 0.0
		var main_node = get_tree().root.get_node_or_null("Main")
		if main_node and "level_timer" in main_node:
			elapsed = float(main_node.level_timer)
			
		if elapsed < 30.0:
			base_wave_interval = 8.0
		elif elapsed < 60.0:
			base_wave_interval = 6.0
		elif elapsed < 120.0:
			base_wave_interval = 5.0
		else:
			base_wave_interval = 4.0
		timer.wait_time = base_wave_interval
		
	current_wave += 1
	GameData.current_wave = current_wave
	
	SignalBus.on_wave_started.emit(current_wave)
	
	var alive_count = _count_alive_enemies()
	if alive_count >= MAX_ALIVE_ENEMIES:
		print("[WaveManager] 场上敌人已满 (%d/%d)，暂缓出怪" % [alive_count, MAX_ALIVE_ENEMIES])
		return
	
	var base_count = 25
	match GameData.current_playing_stage:
		1: base_count = 16
		2: base_count = 20
		3: base_count = 23
		4: base_count = 22
	
	var difficulty_mult = GameData.current_playing_stage
	if GameData.is_endless_mode:
		difficulty_mult = 6
		base_count = 25
	
	var wave_bonus = int(4.0 * log(maxf(current_wave, 1.0)) + current_wave * 1.5)
	var enemies_to_spawn = mini(base_count + wave_bonus + (difficulty_mult * 3), MAX_PER_WAVE)
	
	enemies_to_spawn = mini(enemies_to_spawn, MAX_ALIVE_ENEMIES - alive_count)
	if enemies_to_spawn <= 0:
		return

	var center_pos = target_tree.global_position
	print("[WaveManager] 波次 %d: 生成 %d 个敌人, alive=%d, endless=%s, tree_pos=%s" % [current_wave, enemies_to_spawn, alive_count, GameData.is_endless_mode, center_pos])
	# 预先计算分布参数，但不立即分配位置，因为 beetle 需要不同的半径
	var start_angle = PI + randf_range(0.0, PI / float(enemies_to_spawn))
	var segment = PI / float(enemies_to_spawn)
	var jitter = segment * clampf(spawn_uniform_jitter, 0.0, 0.49)
	
	for i in range(enemies_to_spawn):
		var random_delay = randf_range(0.0, base_wave_interval * 0.8)
		var enemy_type_to_spawn = get_enemy_type_for_wave(current_wave, randf())
		
		# 为不同敌人设置不同的生成半径
		var custom_min = min_spawn_distance
		var custom_max = spawn_radius
		if enemy_type_to_spawn == "beetle":
			custom_min = 700.0
			custom_max = 1100.0
			
		var angle = start_angle + segment * float(i) + randf_range(-jitter, jitter)
		angle = clampf(angle, PI, TAU)
		var spawn_pos = get_spawn_position_with_river_rule(center_pos, angle, custom_min, custom_max)
		
		# 【难度提升计划 B】：阶梯式精英率提升
		var elite_chance = 0.01
		if GameData.current_playing_stage == 3:
			elite_chance = 0.02
		elif GameData.current_playing_stage == 4:
			elite_chance = 0.03
		
		# 无尽模式：随着波数（Wave）每增加 10 波，精英率额外提升 1%
		if GameData.is_endless_mode:
			elite_chance = 0.01 + floor(current_wave / 10.0) * 0.01
			
		var roll_elite = (randf() < elite_chance)
		
		var spawn_func = func(target_spawn_pos: Vector2, type: String, elite: bool):
			if not is_instance_valid(target_tree):
				return
			# 延迟生成时再次检查上限
			if _count_alive_enemies() >= MAX_ALIVE_ENEMIES:
				return
			PoolManager.get_enemy(type, target_spawn_pos, elite)
		
		get_tree().create_timer(random_delay, false).timeout.connect(spawn_func.bind(spawn_pos, enemy_type_to_spawn, roll_elite))

func get_enemy_type_for_wave(wave: int, roll: float) -> String:
	var stage = GameData.current_playing_stage
	
	# 无尽模式：全员混战，随着波数提升精英概率
	if GameData.is_endless_mode:
		if wave < 3: 
			return "beetle" if roll < 0.7 else "beaver"
		if roll < 0.2: return "beetle"
		if roll < 0.5: return "beaver"
		if roll < 0.85: return "lumberjack"
		return "mech_boss"

	# 剧情模式 (1-4关)：每一关、每一波都有特定的敌人权重
	match stage:
		1:
			# 第一关：纯甲虫关卡
			return "beetle"
			
		2:
			# 第二关：河狸初现（纯甲虫+河狸，无伐木工）
			if wave == 1: 
				return "beetle"
			if wave == 2: 
				return "beetle" if roll < 0.7 else "beaver"
			else:
				return "beetle" if roll < 0.5 else "beaver"
				
		3:
			# 第三关：伐木工登场（温和过渡）
			if wave == 1:
				return "beetle" if roll < 0.6 else "beaver"
			if wave == 2:
				if roll < 0.3: return "beetle"
				if roll < 0.6: return "beaver"
				return "lumberjack"
			else:
				if roll < 0.5: return "lumberjack"
				if roll < 0.8: return "beaver"
				return "beetle"
				
		4:
			# 第四关：机甲末日
			if wave == 1:
				return "lumberjack" if roll < 0.7 else "beaver"
			if wave == 2:
				return "lumberjack" if roll < 0.6 else "mech_boss"
			else: # 第三波最终决战
				if roll < 0.7: return "mech_boss"
				return "lumberjack"
				
	return "beetle"
		

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

func get_spawn_position_with_river_rule(center_pos: Vector2, angle: float, min_r_override: float = -1.0, max_r_override: float = -1.0) -> Vector2:
	var min_r = min_spawn_distance if min_r_override < 0 else min_r_override
	var max_r = spawn_radius if max_r_override < 0 else max_r_override
	
	min_r = maxf(0.0, min_r)
	max_r = maxf(min_r + 1.0, max_r)
	
	for _attempt in range(max(1, spawn_retry_limit)):
		var dist = sqrt(lerpf(min_r * min_r, max_r * max_r, randf()))
		var spawn_pos = center_pos + Vector2.from_angle(angle) * dist
		
		# 【修复】：此处应使用局部 min_r 检查，而不是全局 min_spawn_distance
		if spawn_pos.distance_to(center_pos) < min_r:
			continue
			
		if GameData.is_in_river(spawn_pos):
			continue
			
		return spawn_pos
		
	# 最终兜底：沿原始角度在最大半径处生成，避免全部挤在 Vector2.UP
	var fallback = center_pos + Vector2.from_angle(angle) * max_r
	if GameData.is_in_river(fallback):
		# 如果最大半径处在水里，尝试往回缩一点，或者强制挪到岸边
		fallback = GameData.clamp_to_river_bank(fallback, 24.0)
		
	return fallback
