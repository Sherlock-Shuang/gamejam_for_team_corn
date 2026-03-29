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
	GameData.register_current_run_skill(skill_id)
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
	elif skill_data["id"] == "vine_spread":
		_create_skill_timer("vine_spread_timer", 0.5, _cast_vine_spread)
	elif skill_data["id"] == "seed_bomb":
		var cd = effects.get("interval", effects.get("delay", 1.5) + 1.0)
		_create_skill_timer("seed_bomb_timer", cd, _cast_seed_bomb)

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
			if nearest.has_method("take_damage"):
				var base_atk = GameData.player_base_stats["attack_power"]
				nearest.take_damage(base_atk * 0.8, thorn.global_position)
			thorn.queue_free()
	, 0.0, 1.0, 0.5)
	
	tween.tween_callback(thorn.queue_free)

func _fire_bomb():
	# 从 GameData 获取特效数值
	var skill_data = active_skills.get("exploding_fruit", null)
	if skill_data == null: return
	var effects = skill_data["effects"]
	var blast_radius = effects.get("radius", 150.0)
	var final_damage = effects.get("explosion_damage", 20.0)
	
	var target_pos = _pick_random_land_point_around(tree_owner.global_position, 80.0, 600.0)
	
	# 加载并实例化 fruit_root 场景
	var fruit_scene_path = "res://scenes/effects/FruitRoot.tscn"
	if not ResourceLoader.exists(fruit_scene_path):
		push_warning("[SkillExecutor] 缺少场景: " + fruit_scene_path + "，请先在编辑器保存 fruit_root.tscn")
		return
	var fruit_scene = load(fruit_scene_path)
	if fruit_scene == null:
		push_warning("[SkillExecutor] fruit_root 场景加载失败: " + fruit_scene_path)
		return
	var fruit = fruit_scene.instantiate()
	
	# 将其添加到场景树中
	get_tree().current_scene.add_child(fruit)
	
	# 调用果实的发射接口，直接传入最终伤害
	fruit.launch(tree_owner.global_position, target_pos, blast_radius, final_damage)

func _cast_vine_spread():
	var skill = active_skills.get("vine_spread", null)
	if skill == null:
		return
	var effects = skill["effects"]
	var radius = effects.get("radius", 220.0)
	var slow_percent = effects.get("slow_percent", 0.4)
	var dps = effects.get("dps", 2.0)
	var duration = effects.get("duration", 1.2)
	var tick_damage = dps * 0.5
	var hit_enemies = _get_active_enemies_in_radius(radius)
	for enemy in hit_enemies:
		if enemy.has_method("apply_slow"):
			enemy.apply_slow(slow_percent, duration)
		if enemy.has_method("take_damage"):
			var base_atk = GameData.player_base_stats["attack_power"]
			enemy.take_damage(base_atk * 0.35 + tick_damage, tree_owner.global_position)

func _cast_seed_bomb():
	var skill = active_skills.get("seed_bomb", null)
	if skill == null:
		return
	var effects = skill["effects"]
	var radius = effects.get("radius", 150.0)
	var tick_interval = effects.get("damage_interval", 0.5)
	var life_time = effects.get("lifetime", 10.0)
	var base_damage = effects.get("sapling_damage", 12.0)
	var base_atk = GameData.player_base_stats.get("attack_power", 0.0)
	var final_damage = base_damage + base_atk * 0.5
	var spawn_range = effects.get("cast_range", 600.0)
	var min_seed_distance = 120.0
	var target_pos = tree_owner.global_position
	var nearest = _get_nearest_target()
	if is_instance_valid(nearest):
		target_pos = nearest.global_position
	else:
		target_pos = _pick_random_land_point_around(tree_owner.global_position, min_seed_distance, spawn_range)
	target_pos = _clamp_skill_target_to_land(target_pos, tree_owner.global_position, min_seed_distance, spawn_range)
	var seed_scene_path = "res://scenes/effects/SeedBomb.tscn"
	if not ResourceLoader.exists(seed_scene_path):
		push_warning("[SkillExecutor] 缺少场景: " + seed_scene_path + "，请先保存 SeedBomb.tscn")
		return
	var seed_scene = load(seed_scene_path)
	if seed_scene == null:
		push_warning("[SkillExecutor] SeedBomb 场景加载失败: " + seed_scene_path)
		return
	var seed_bomb = seed_scene.instantiate()
	get_tree().current_scene.add_child(seed_bomb)
	seed_bomb.launch(tree_owner.global_position, target_pos, final_damage, radius, tick_interval, life_time)

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
	var skill_id = skill_data.get("id", "")
	if eff.has("max_hp_bonus"):
		GameData.player_base_stats["max_hp"] += eff["max_hp_bonus"]
		GameData.current_hp += eff["max_hp_bonus"]
		GameData.current_hp = minf(GameData.current_hp, GameData.player_base_stats["max_hp"])
		SignalBus.on_player_hp_changed.emit(GameData.current_hp, GameData.player_base_stats["max_hp"])
		if skill_id == "thick_bark" and tree_owner.has_method("apply_trunk_width_multiplier"):
			tree_owner.apply_trunk_width_multiplier(eff.get("trunk_width_mult", 1.3))
	if eff.has("hp_regen"):
		GameData.player_base_stats["hp_regen"] += eff["hp_regen"]
		if skill_id == "deep_roots" and tree_owner.has_method("apply_root_scale_multiplier"):
			tree_owner.apply_root_scale_multiplier(eff.get("root_scale_mult", 1.3))
	if eff.has("attack_mult"):
		GameData.player_base_stats["attack_power"] *= eff["attack_mult"]
	if eff.has("range_mult"):
		GameData.player_base_stats["attack_range"] *= eff["range_mult"]
		if skill_id == "wide_canopy":
			if tree_owner.has_method("apply_canopy_scale_multiplier"):
				tree_owner.apply_canopy_scale_multiplier(eff.get("canopy_sprite_mult", 1.4))
			var treehead = tree_owner.get_node_or_null("treehead")
			if treehead and treehead.has_method("apply_hit_shape_scale_multiplier"):
				treehead.apply_hit_shape_scale_multiplier(eff.get("hitbox_shape_mult", 1.4))
	if eff.has("stretch_scale_bonus"):
		# 弹性树干技能：去树干上修改 max_stretch_scale
		var treehead = tree_owner.get_node_or_null("treehead")
		if treehead and treehead.get("max_stretch_scale") != null:
			treehead.max_stretch_scale += eff["stretch_scale_bonus"]
			print("[SkillExecutor] 弹性树干生效！当前 max_stretch_scale: ", treehead.max_stretch_scale)

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
		if is_instance_valid(e) and e.process_mode != Node.PROCESS_MODE_DISABLED and e.has_method("take_damage"):
			var dist = e.global_position.distance_to(tree_owner.global_position)
			if dist < closest_dist:
				closest_dist = dist
				nearest_enemy = e
				
	return nearest_enemy

func _get_active_enemies_in_radius(radius: float) -> Array:
	var result: Array = []
	for enemy in get_tree().get_nodes_in_group("Enemy"):
		if not is_instance_valid(enemy):
			continue
		if enemy.process_mode == Node.PROCESS_MODE_DISABLED:
			continue
		if not enemy.has_method("take_damage"):
			continue
		if enemy.global_position.distance_to(tree_owner.global_position) <= radius:
			result.append(enemy)
	return result

func _pick_random_land_point_around(center_pos: Vector2, min_distance: float, max_distance: float) -> Vector2:
	var inner = maxf(0.0, min_distance)
	var outer = maxf(inner + 1.0, max_distance)
	for _try in range(12):
		var angle = randf_range(0.0, TAU)
		var dist = sqrt(lerpf(inner * inner, outer * outer, randf()))
		var candidate = center_pos + Vector2.from_angle(angle) * dist
		if not GameData.is_in_river(candidate):
			return candidate
	return GameData.clamp_to_river_bank(center_pos + Vector2.UP * outer, 24.0)

func _clamp_skill_target_to_land(target_pos: Vector2, center_pos: Vector2, min_distance: float, max_distance: float) -> Vector2:
	var inner = maxf(0.0, min_distance)
	var outer = maxf(inner + 1.0, max_distance)
	var adjusted = target_pos
	var dist = center_pos.distance_to(adjusted)
	if dist < 0.001:
		adjusted = center_pos + Vector2.RIGHT * inner
		dist = inner
	if dist < inner:
		adjusted = center_pos + (adjusted - center_pos).normalized() * inner
	elif dist > outer:
		adjusted = center_pos + (adjusted - center_pos).normalized() * outer
	if GameData.is_in_river(adjusted):
		return _pick_random_land_point_around(center_pos, inner, outer)
	return adjusted
