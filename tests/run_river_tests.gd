extends SceneTree

var _failed: Array[String] = []
var _game_data_ref: Node = null

func _initialize() -> void:
	randomize()
	_test_game_data_river_helpers()
	_test_wave_manager_spawn_rule()
	_test_enemy_ai_river_logic()
	_test_enemy_collision_masks()
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
	wave_manager.spawn_radius = 1000.0
	var spawn_pos = wave_manager.get_spawn_position_with_river_rule(Vector2(943.0, 556.0), PI / 2.0)
	_assert_true(spawn_pos.y <= gd.RIVER_Y_THRESHOLD, "WaveManager 生成点仍落在河流区")

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
