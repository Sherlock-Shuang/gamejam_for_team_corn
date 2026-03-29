extends Node2D

@export var base_wave_interval: float = 3.0
@export var spawn_radius: float = 1100.0
@export var min_spawn_distance: float = 1000.0
@export var spawn_uniform_jitter: float = 0.35
@export var spawn_retry_limit: int = 8

@onready var timer: Timer = $WaveTimer
var target_tree: Node2D = null
var current_wave: int = 0

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
	GameData.current_wave = current_wave
	var enemies_to_spawn = 10 + (current_wave * 3)
	if current_wave >= 5:
		pass
	if current_wave >= 10:
		enemies_to_spawn += 10
	var center_pos = target_tree.global_position
	var spawn_positions = get_uniform_spawn_positions(center_pos, enemies_to_spawn)
	for i in range(enemies_to_spawn):
		var random_delay = randf_range(0.0, timer.wait_time)
		var spawn_pos = spawn_positions[i]
		var enemy_type_to_spawn = get_enemy_type_for_wave(current_wave, randf())
		var spawn_func = func(target_spawn_pos: Vector2, type: String):
			if not is_instance_valid(target_tree):
				return
			PoolManager.get_enemy(type, target_spawn_pos)
		get_tree().create_timer(random_delay, false).timeout.connect(spawn_func.bind(spawn_pos, enemy_type_to_spawn))

func get_enemy_type_for_wave(wave: int, roll: float) -> String:
	var r = clampf(roll, 0.0, 1.0)
	if wave < 5:
		return "fly"
	if wave < 10:
		if r < 0.7:
			return "fly"
		return "beaver"
	if wave < 15:
		if r < 0.45:
			return "fly"
		if r < 0.85:
			return "beaver"
		return "human"
	if r < 0.25:
		return "fly"
	if r < 0.6:
		return "beaver"
	return "human"

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
