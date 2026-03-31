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
	
	if not GameData.is_endless_mode:
		match GameData.current_playing_stage:
			1: base_wave_interval = 12.0 # 给予玩家更多喘息时间
			2: base_wave_interval = 7.5
			3: base_wave_interval = 6.0 # 频率大幅增加
			4: base_wave_interval = 4.5 # 极高频率
			_: base_wave_interval = 6.0
	else:
		base_wave_interval = 8.0 # 无尽模式起始节奏就拉满

		
	timer.wait_time = base_wave_interval
	timer.timeout.connect(_on_wave_timeout)
	timer.start()
	
	# 第一波在开局不久后立即出现 (无尽模式更快出现)
	var first_wave_delay = 0.5 if GameData.is_endless_mode else 1.5
	get_tree().create_timer(first_wave_delay).timeout.connect(_on_wave_timeout)

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
			return
	
	if not GameData.is_endless_mode and current_wave >= MAX_WAVES_PER_STAGE:
		return 
		
	if GameData.is_endless_mode:
		var elapsed = 0.0
		var main_node = get_tree().root.get_node_or_null("Main")
		if main_node and "level_timer" in main_node:
			elapsed = float(main_node.level_timer)
			
		if elapsed < 60.0:
			base_wave_interval = 20.0
		elif elapsed < 100.0:
			base_wave_interval = 15.0
		else:
			base_wave_interval = 8.0
		timer.wait_time = base_wave_interval
		
	current_wave += 1
	GameData.current_wave = current_wave
	
	SignalBus.on_wave_started.emit(current_wave)
	
	# 🔥【性能优化】：先检查场上数量，到达上限直接跳过本波
	var alive_count = _count_alive_enemies()
	if alive_count >= MAX_ALIVE_ENEMIES:
		print("[WaveManager] 场上敌人已满 (%d/%d)，暂缓出怪" % [alive_count, MAX_ALIVE_ENEMIES])
		return
	
	# 出怪数量：改用亚线性增长（对数曲线），防止后期帧率崩塌
	var base_count = 25
	if GameData.current_playing_stage == 1: base_count = 15
	
	var difficulty_mult = GameData.current_playing_stage
	if GameData.is_endless_mode: difficulty_mult = 6 
	
	# 🔥 核心公式重构：对数增长 + 硬上限 (玩家调整版)
	var wave_bonus = int(3.0 * log(maxf(current_wave, 1.0)) * 15.0) 
	var enemies_to_spawn = mini(base_count + wave_bonus + (difficulty_mult * 10), MAX_PER_WAVE)
	
	# 再次检查：不要超过全局上限的剩余空间
	enemies_to_spawn = mini(enemies_to_spawn, MAX_ALIVE_ENEMIES - alive_count)
	if enemies_to_spawn <= 0:
		return

	var center_pos = target_tree.global_position
	var spawn_positions = get_uniform_spawn_positions(center_pos, enemies_to_spawn)
	
	for i in range(enemies_to_spawn):
		var random_delay = randf_range(0.0, base_wave_interval * 0.8)
		var spawn_pos = spawn_positions[i]
		var enemy_type_to_spawn = get_enemy_type_for_wave(current_wave, randf())
		
		# 精英判定：第 3, 4 关或无尽模式有 1% 概率产生精英。
		var roll_elite = false
		if GameData.is_endless_mode or GameData.current_playing_stage >= 3:
			if randf() < 0.01:
				roll_elite = true
		
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
			# 第二关：河狸初现
			if wave == 1: 
				return "beetle" if roll < 0.8 else "beaver"
			if wave == 2: 
				return "beetle" if roll < 0.4 else "beaver"
			else: # 第三波决战
				if roll < 0.6: return "beaver"
				return "lumberjack" # 第三波如约加入少量人类
				
		3:
			# 第三关：伐木工的主场
			if wave == 1:
				return "beaver" if roll < 0.7 else "beetle"
			if wave == 2:
				return "beaver" if roll < 0.4 else "lumberjack"
			else: # 第三波决战
				if roll < 0.8: return "lumberjack"
				return "beaver"
				
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
