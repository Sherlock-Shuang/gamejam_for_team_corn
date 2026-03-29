extends Node
class_name SkillExecutor
# ═══════════════════════════════════════════════════════════════
#  SkillExecutor.gd — 玩家技能引擎核心（作为 tree 的子节点运行）
#  负责解析 GameData 里的词条数据，应用各种 BUFF / 生成衍生弹幕
# ═══════════════════════════════════════════════════════════════

var active_skills: Dictionary = {}
@onready var tree_owner = get_parent()

func _ready():
	print("[SkillExecutor] 技能引擎已加载，开始监听天命总线...")
	SignalBus.on_upgrade_selected.connect(_on_skill_unlocked)
	SignalBus.on_enemy_hit.connect(_on_enemy_hit)
	
	# 无尽模式下，出门自带所有神装技能！
	if GameData.is_endless_mode:
		print("[SkillExecutor] 无尽模式启动，加载全库技能！")
		for skill_id in GameData.skill_pool.keys():
			_on_skill_unlocked(skill_id)

func _on_skill_unlocked(skill_id: String):
	if not GameData.skill_pool.has(skill_id):
		return
	
	var data = GameData.skill_pool[skill_id]
	print("[SkillExecutor] 实装能力: ", data["name"])
	
	# 免得重复初始化
	if active_skills.has(skill_id):
		# 如果允许叠加，可以在这写叠加逻辑
		return
	
	active_skills[skill_id] = data
	SignalBus.on_skill_actived.emit(skill_id)
	
	var category = data["category"]
	if category == "衍生攻击":
		_setup_derived_attack(data)
	elif category == "基础数值":
		_apply_base_stats(data)

# ── 类别 A：衍生攻击 (定时开火型) ──────────────────────────────
func _setup_derived_attack(skill_data: Dictionary):
	var effects = skill_data["effects"]
	
	if skill_data["id"] == "thorn_shot":
		var cd = effects.get("interval", 2.0)
		_create_skill_timer("thorn_shot_timer", cd, _fire_thorn)
	elif skill_data["id"] == "exploding_fruit":
		var cd = effects.get("interval", 4.0)
		_create_skill_timer("bomb_fruit_timer", cd, _fire_bomb)

func _create_skill_timer(timer_name: String, wait_time: float, callable_func: Callable):
	var timer = Timer.new()
	timer.name = timer_name
	timer.wait_time = wait_time
	timer.autostart = true
	add_child(timer)
	timer.timeout.connect(callable_func)

func _fire_thorn():
	var nearest = _get_nearest_target()
	if not nearest: return
	
	# 这里后续用真正的 Thorn.tscn，目前先拿纯色块代替
	var thorn = Polygon2D.new()
	thorn.polygon = PackedVector2Array([Vector2(-2, -10), Vector2(2, -10), Vector2(0, 5)])
	thorn.color = Color(0.1, 0.8, 0.2)
	thorn.global_position = tree_owner.global_position
	# 因为需要物理运动，通常会挂在 current_scene。暂时先用简单的 Tween 模拟
	get_tree().current_scene.add_child(thorn)
	
	var dir = (nearest.global_position - thorn.global_position).normalized()
	thorn.rotation = dir.angle() + PI/2.0
	
	var tween = create_tween()
	var final_pos = thorn.global_position + dir * 600.0
	tween.tween_property(thorn, "global_position", final_pos, 0.5)
	
	# 简单范围判定
	tween.parallel().tween_method(func(_progress):
		if not is_instance_valid(nearest): return
		if not is_instance_valid(thorn): return
		if thorn.global_position.distance_to(nearest.global_position) < 30.0:
			if nearest.has_method("die"):
				nearest.die(thorn.global_position) # 传入攻击源坐标
			thorn.queue_free()
	, 0.0, 1.0, 0.5)
	
	tween.tween_callback(thorn.queue_free)

func _fire_bomb():
	# 类似发射果实逻辑
	pass

# ── 类别 B：元素附魔 (基于每次普攻) ─────────────────────────────
# 监听 treehead 发来的击中信号，判定有没有元素状态，直接附加给你
func _on_enemy_hit(damage: float, enemy_pos: Vector2, enemy_node: Node2D):
	if active_skills.has("ice_enchant"):
		var fx = active_skills["ice_enchant"]["effects"]
		if enemy_node and enemy_node.has_method("apply_slow"):
			enemy_node.apply_slow(fx["slow_percent"], fx["slow_duration"])
			
	if active_skills.has("fire_enchant"):
		# 点燃逻辑... 同理
		pass

# ── 类别 C：基础属性被动提升 ────────────────────────────────────
func _apply_base_stats(skill_data: Dictionary):
	var eff = skill_data["effects"]
	if eff.has("max_hp_bonus"):
		GameData.current_hp += eff["max_hp_bonus"]
		SignalBus.on_player_hp_changed.emit(GameData.current_hp, GameData.player_base_stats["max_hp"])
	if eff.has("range_mult"):
		# 通知树根变大
		var tween = create_tween().set_trans(Tween.TRANS_ELASTIC)
		tween.tween_property(tree_owner, "scale", tree_owner.scale * eff["range_mult"], 0.5)

# ── 工具函数 ──
func _get_nearest_target() -> Node2D:
	var enemies = get_tree().get_nodes_in_group("Enemy")
	var closest_dist = 999999.0
	var nearest_enemy = null
	
	for e in enemies:
		# 极其关键的三个过滤条件：
		# 1. 它必须是活着的有效节点
		# 2. 它不能是被对象池回收后处于 DISABLED 冰封状态的怪物
		# 3. 它必须拥有 die() 方法（排除误加了分组的 Area2D / Hurtbox 等子节点）
		if is_instance_valid(e) and e.process_mode != Node.PROCESS_MODE_DISABLED and e.has_method("die"):
			var dist = e.global_position.distance_to(tree_owner.global_position)
			if dist < closest_dist:
				closest_dist = dist
				nearest_enemy = e
				
	return nearest_enemy
