extends SceneTree

var _failed: Array[String] = []
var _game_data_ref: Node = null

func _initialize() -> void:
	seed(20260329)
	_test_game_data_river_helpers()
	_test_wave_manager_spawn_rule()
	_test_wave_manager_uniformity()
	_test_enemy_ai_river_logic()
	_test_enemy_collision_masks()
	_test_skill_random_points_out_of_river()
	_test_lightning_skill_registration()
	_test_lightning_numeric_params()
	_test_lightning_scene_launch()
	_test_main_scene_river_nodes()
	if _failed.is_empty():
		print("RIVER_TESTS: PASS")
		quit(0)
		return
	for msg in _failed:
		push_error(msg)
	print("RIVER_TESTS: FAIL (%d)" % _failed.size())
	quit(1)

func _assert_true(condition: bool, message: String) -> void:
	if not condition:
		_failed.append(message)

func _assert_almost_eq(a: float, b: float, epsilon: float, message: String) -> void:
	if absf(a - b) > epsilon:
		_failed.append("%s | actual=%s expected=%s" % [message, str(a), str(b)])

func _game_data() -> Node:
	if is_instance_valid(_game_data_ref):
		return _game_data_ref
	_game_data_ref = get_root().get_node_or_null("GameData")
	if _game_data_ref == null:
		_game_data_ref = load("res://scripts/autoloads/GameData.gd").new()
	return _game_data_ref

func _test_game_data_river_helpers() -> void:
	var gd = _game_data()
	_assert_true(gd.is_in_river(Vector2(10.0, 201.0)), "GameData.is_in_river 未识别 Y>200")
	_assert_true(not gd.is_in_river(Vector2(10.0, 200.0)), "GameData.is_in_river 误判 Y=200")
	var clamped = gd.clamp_to_river_bank(Vector2(10.0, 300.0), 12.0)
	_assert_almost_eq(clamped.y, 188.0, 0.001, "GameData.clamp_to_river_bank 结果错误")

func _test_wave_manager_spawn_rule() -> void:
	var gd = _game_data()
	var script = load("res://scripts/components/WaveManager.gd")
	var wave_manager = script.new()
	wave_manager.spawn_radius = 1100.0
	wave_manager.min_spawn_distance = 1000.0
	var spawn_pos = wave_manager.get_spawn_position_with_river_rule(Vector2(943.0, 150.0), PI / 2.0)
	_assert_true(spawn_pos.y <= gd.RIVER_Y_THRESHOLD, "WaveManager 生成点仍落在河流区")
	_assert_true(spawn_pos.distance_to(Vector2(943.0, 150.0)) >= wave_manager.min_spawn_distance, "WaveManager 生成点落在树周围禁区内")
	_assert_true(spawn_pos.distance_to(Vector2(943.0, 150.0)) <= wave_manager.spawn_radius, "WaveManager 生成点超过最大半径")

func _test_wave_manager_uniformity() -> void:
	var script = load("res://scripts/components/WaveManager.gd")
	var wave_manager = script.new()
	wave_manager.spawn_radius = 1100.0
	wave_manager.min_spawn_distance = 1000.0
	wave_manager.spawn_uniform_jitter = 0.25
	var center = Vector2(943.0, 150.0)
	var points = wave_manager.get_uniform_spawn_positions(center, 24)
	_assert_true(points.size() == 24, "WaveManager 未生成完整数量位置")
	var bins: Array[int] = [0, 0, 0, 0]
	for p in points:
		var dist = p.distance_to(center)
		_assert_true(dist >= wave_manager.min_spawn_distance, "WaveManager 均匀生成功能进入树周围禁区")
		_assert_true(dist <= wave_manager.spawn_radius, "WaveManager 均匀生成功能超过最大半径")
		_assert_true(p.y <= _game_data().RIVER_Y_THRESHOLD, "WaveManager 均匀生成点进入河流区域")
		var angle = fposmod((p - center).angle(), TAU)
		var folded_angle = angle if angle >= PI else angle + TAU
		_assert_true(folded_angle >= PI and folded_angle <= TAU + PI, "WaveManager 生成点未落在陆地侧角域")
		var idx = int(floor((folded_angle - PI) / (PI / 4.0)))
		bins[clampi(idx, 0, 3)] += 1
	var min_bin = bins[0]
	var max_bin = bins[0]
	for c in bins:
		min_bin = mini(min_bin, c)
		max_bin = maxi(max_bin, c)
	_assert_true(max_bin - min_bin <= 3, "WaveManager 角度分布不均匀")

func _test_enemy_ai_river_logic() -> void:
	var gd = _game_data()
	var script = load("res://scripts/actors/EnemyAI.gd")
	var enemy = script.new()
	enemy.speed = 120.0
	enemy.river_avoid_margin = 48.0
	enemy.global_position = Vector2(0.0, 225.0)
	enemy.velocity = Vector2(10.0, 60.0)
	var boundary_force: Vector2 = enemy._calculate_river_avoidance_force()
	_assert_true(boundary_force.y < 0.0, "EnemyAI 未产生向上避让力")
	enemy._enforce_river_boundary()
	_assert_true(enemy.global_position.y <= gd.RIVER_Y_THRESHOLD, "EnemyAI 边界纠正失败")

func _test_enemy_collision_masks() -> void:
	var fly = load("res://scenes/actors/EnemyFly.tscn").instantiate()
	var beaver = load("res://scenes/actors/EnemyBeaver.tscn").instantiate()
	_assert_true((fly.collision_mask & 32) == 32, "EnemyFly 未包含 world 层碰撞掩码")
	_assert_true((beaver.collision_mask & 32) == 32, "EnemyBeaver 未包含 world 层碰撞掩码")
	fly.free()
	beaver.free()

func _test_skill_random_points_out_of_river() -> void:
	var script = load("res://scripts/components/SkillExecutor.gd")
	var skill_executor = script.new()
	var center = Vector2(943.0, 150.0)
	for _i in range(40):
		var bomb_target = skill_executor._pick_random_land_point_around(center, 80.0, 600.0)
		_assert_true(not _game_data().is_in_river(bomb_target), "爆炸果实随机点进入河流")
		var bomb_dist = bomb_target.distance_to(center)
		_assert_true(bomb_dist >= 80.0 and bomb_dist <= 600.0, "爆炸果实随机点超出允许距离")
		var seed_target = skill_executor._pick_random_land_point_around(center, 120.0, 600.0)
		_assert_true(not _game_data().is_in_river(seed_target), "种子随机点进入河流")
		var seed_dist = seed_target.distance_to(center)
		_assert_true(seed_dist >= 120.0 and seed_dist <= 600.0, "种子随机点超出允许距离")

func _test_lightning_skill_registration() -> void:
	var gd = _game_data()
	_assert_true(gd.skill_pool.has("lightning_field"), "技能池缺少闪电场技能")
	var lightning = gd.skill_pool["lightning_field"]
	_assert_true(lightning.get("category", "") == "衍生攻击", "闪电场未进入可选衍生攻击池")

func _test_lightning_numeric_params() -> void:
	var script = load("res://scenes/effects/flash.gd")
	var lightning = script.new()
	lightning.base_flight_duration = 0.5
	lightning.speed_ratio = 0.4
	lightning.linger_duration = 0.5
	lightning.texture_base_radius = 100.0
	lightning.linger_scale_ratio = 0.1
	var flight_duration = lightning.compute_flight_duration()
	_assert_almost_eq(flight_duration, 1.25, 0.001, "闪电飞行时长计算错误")
	var speed_value = lightning.compute_speed(500.0)
	_assert_almost_eq(speed_value, 400.0, 0.001, "闪电速度曲线计算错误")
	var final_scale = lightning.compute_final_scale(320.0)
	_assert_almost_eq(final_scale, 3.2, 0.001, "闪电爆炸半径缩放计算错误")
	var decay_scale = lightning.compute_decay_scale(final_scale)
	_assert_almost_eq(decay_scale, 0.32, 0.001, "闪电爆炸半径衰减计算错误")
	var linger = lightning.get_effective_linger_duration()
	_assert_almost_eq(linger, 0.5, 0.001, "闪电悬停计时器时长错误")

func _test_lightning_scene_launch() -> void:
	var scene = load("res://scenes/effects/Flash.tscn").instantiate()
	get_root().add_child(scene)
	scene.launch(Vector2.ZERO, Vector2(400.0, 0.0), 320.0, 24.0, {"speed_ratio": 0.4, "linger_duration": 0.5, "linger_scale_ratio": 0.1})
	_assert_almost_eq(scene.last_flight_duration, 1.25, 0.001, "闪电场景飞行时长注入失败")
	_assert_true(scene.state == 1, "闪电场景启动状态错误")
	scene.queue_free()

func _test_main_scene_river_nodes() -> void:
	var gd = _game_data()
	var main_scene = load("res://Main.tscn").instantiate()
	_assert_true(main_scene.has_node("RiverBarrier"), "Main 场景缺少 RiverBarrier")
	_assert_true(main_scene.has_node("RiverVisual/RiverAreaFill"), "Main 场景缺少河流视觉填充")
	var tree_node = main_scene.get_node("tree")
	_assert_true(tree_node.position.y <= gd.RIVER_Y_THRESHOLD, "主树位置仍在河流禁区内，可能导致无法被进攻")
	var river_barrier = main_scene.get_node("RiverBarrier")
	var shape: RectangleShape2D = river_barrier.get_node("CollisionShape2D").shape
	var top_edge = river_barrier.position.y - (shape.size.y / 2.0)
	_assert_almost_eq(top_edge, gd.RIVER_Y_THRESHOLD, 0.001, "RiverBarrier 上边界不是 Y=200")
	main_scene.free()
