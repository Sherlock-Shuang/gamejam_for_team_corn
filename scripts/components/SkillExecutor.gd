extends Node
class_name SkillExecutor
# ═══════════════════════════════════════════════════════════════
#  SkillExecutor.gd — 玩家技能引擎核心（作为 tree 的子节点运行）
#  负责解析 GameData 里的词条数据，应用各种 BUFF / 生成衍生弹幕
# ═══════════════════════════════════════════════════════════════

var active_skills: Dictionary = {}
var active_skill_levels: Dictionary = {}
@onready var tree_owner = get_parent()
const VINE_TENTACLE_SCENE = preload("res://scenes/effects/vine_tentacle.tscn")

func _ready():
	print("[SkillExecutor] 技能引擎已加载，开始监听天命总线...")
	SignalBus.on_upgrade_selected.connect(_on_skill_unlocked)
	SignalBus.on_enemy_hit.connect(_on_enemy_hit)
	_set_tree_fire_enchant_fx(false, 0)
	_set_tree_ice_enchant_fx(false, 0)

func _on_skill_unlocked(skill_id: String):
	var payload = GameData.decode_upgrade_payload(skill_id)
	var real_skill_id = str(payload.get("skill_id", ""))
	var route_id = str(payload.get("route_id", ""))
	if not GameData.skill_pool.has(real_skill_id):
		return

	var data = GameData.skill_pool[real_skill_id]
	print("[SkillExecutor] 实装能力: ", data["name"])

	var upgrade_result = GameData.apply_skill_upgrade(real_skill_id, route_id)
	var new_level = int(upgrade_result.get("skill_level", 1))
	var prev_effects = upgrade_result.get("prev_effects", {})
	var new_effects = upgrade_result.get("effects", {})
	active_skill_levels[real_skill_id] = new_level
	active_skills[real_skill_id] = data
	SignalBus.on_skill_actived.emit(real_skill_id)
	if real_skill_id == "fire_enchant":
		_set_tree_fire_enchant_fx(true, new_level)
	if real_skill_id == "ice_enchant":
		_set_tree_ice_enchant_fx(true, new_level)

	var category = data["category"]
	if category == "衍生攻击":
		_setup_derived_attack(real_skill_id)
	elif category == "基础数值":
		_apply_base_stats(real_skill_id, prev_effects, new_effects)

# ── 类别 A：衍生攻击 (定时开火型) ──────────────────────────────
func _setup_derived_attack(skill_id: String):
	var effects = _get_skill_effects(skill_id)
	if skill_id == "thorn_shot":
		var cd = effects.get("interval", 2.0)
		_create_skill_timer("thorn_shot_timer", cd, _fire_thorn)
	elif skill_id == "exploding_fruit":
		var cd = effects.get("interval", 4.0)
		_create_skill_timer("bomb_fruit_timer", cd, _fire_bomb)
	elif skill_id == "lightning_field":
		var cd = effects.get("interval", 5.0)
		_create_skill_timer("lightning_field_timer", cd, _fire_lightning_field)
	elif skill_id == "vine_spread":
		var cd = effects.get("interval", 4.0)
		_create_skill_timer("vine_spread_timer", cd, _cast_vine_spread)
	elif skill_id == "seed_bomb":
		var cd = effects.get("interval", effects.get("delay", 1.5) + 1.0)
		_create_skill_timer("seed_bomb_timer", cd, _cast_seed_bomb)

func _create_skill_timer(timer_name: String, wait_time: float, callable_func: Callable):
	var old_timer = get_node_or_null(timer_name)
	if old_timer and old_timer is Timer:
		old_timer.stop()
		old_timer.queue_free()
	var timer = Timer.new()
	timer.name = timer_name
	timer.wait_time = wait_time
	timer.autostart = true
	add_child(timer)
	timer.timeout.connect(callable_func)

func _get_skill_level(skill_id: String) -> int:
	return int(active_skill_levels.get(skill_id, 1))

func _get_skill_effects(skill_id: String) -> Dictionary:
	return GameData.get_skill_effects(skill_id, _get_skill_level(skill_id))

func _fire_thorn():
	var nearest = _get_nearest_target()
	if not nearest:
		return
	var thorn = PoolManager.get_effect("thorn_shot")
	var direction = (nearest.global_position - tree_owner.global_position).normalized()
	var effects = _get_skill_effects("thorn_shot")
	var final_damage = GameData.player_base_stats.get("attack_power", 10.0) * 0.8
	final_damage = effects.get("poison_damage", final_damage)
	var projectile_count = maxi(1, int(effects.get("projectile_count", 1)))
	var spread_step = deg_to_rad(10.0)
	var half = float(projectile_count - 1) * 0.5
	for i in range(projectile_count):
		var shot = thorn
		if i > 0:
			shot = PoolManager.get_effect("thorn_shot")
		var offset_angle = (float(i) - half) * spread_step
		var shot_dir = direction.rotated(offset_angle)
		if shot.has_method("launch"):
			shot.launch(tree_owner.global_position, shot_dir, final_damage, effects.get("speed_mult", 1.0), effects)

func _fire_bomb():
	if not active_skills.has("exploding_fruit"):
		return
	var effects = _get_skill_effects("exploding_fruit")
	var blast_radius = effects.get("radius", 150.0)
	var final_damage = effects.get("explosion_damage", 20.0)
	var cast_count = maxi(1, int(effects.get("cast_count", 1)))
	
	for _i in range(cast_count):
		var target_pos = _pick_random_land_point_around(tree_owner.global_position, 80.0, 600.0)
		var fruit = PoolManager.get_effect("exploding_fruit")
		fruit.launch(tree_owner.global_position, target_pos, blast_radius, final_damage)

func _fire_lightning_field():
	if not active_skills.has("lightning_field"):
		return
	var effects = _get_skill_effects("lightning_field")
	var blast_radius = effects.get("radius", 320.0)
	var final_damage = effects.get("explosion_damage", 24.0)
	var min_range = effects.get("cast_range_min", 120.0)
	var max_range = effects.get("cast_range_max", 650.0)
	var speed_ratio = effects.get("speed_ratio", 0.4)
	var linger_duration = effects.get("linger_duration", 2.5)
	var linger_scale_ratio = effects.get("linger_scale_ratio", 0.85)
	var cast_count = maxi(1, int(effects.get("cast_count", 1)))
	var target_pos = tree_owner.global_position
	var nearest = _get_nearest_target()
	if is_instance_valid(nearest):
		target_pos = nearest.global_position
	else:
		target_pos = _pick_random_land_point_around(tree_owner.global_position, min_range, max_range)
	target_pos = _clamp_skill_target_to_land(target_pos, tree_owner.global_position, min_range, max_range)
	for _i in range(cast_count):
		var aim_pos = target_pos
		if cast_count > 1:
			aim_pos = _pick_random_land_point_around(target_pos, 20.0, 120.0)
		var lightning_field = PoolManager.get_effect("lightning_field")
		lightning_field.launch(
			tree_owner.global_position,
			aim_pos,
			blast_radius,
			final_damage,
			{
				"speed_ratio": speed_ratio,
				"linger_duration": linger_duration,
				"linger_scale_ratio": linger_scale_ratio,
				"burst_overshoot_ratio": effects.get("burst_overshoot_ratio", 1.2),
				"scale_settle_duration": effects.get("scale_settle_duration", 0.1)
			}
		)

func _cast_vine_spread():
	var skill = active_skills.get("vine_spread", null)
	if skill == null:
		return
	var vine_level = _get_skill_level("vine_spread")
	var effects = _get_skill_effects("vine_spread")
	var target_count = int(effects.get("target_count", 3))
	var search_radius = maxf(float(effects.get("search_radius", effects.get("radius", 350.0))), 520.0)
	var base_damage = float(effects.get("damage", 100.0))
	var atk = float(GameData.player_base_stats.get("attack_power", 10.0))
	var final_damage = base_damage + atk * 0.5
	var enemies_in_range = _get_active_enemies_in_radius(search_radius)
	if enemies_in_range.is_empty():
		var nearest = _get_nearest_target()
		if is_instance_valid(nearest):
			enemies_in_range = [nearest]
		else:
			return
	if enemies_in_range.is_empty():
		return
	enemies_in_range.shuffle()
	var grab_count = mini(enemies_in_range.size(), target_count)
	print("[SkillExecutor] VineTentacle cast targets=", grab_count, " radius=", search_radius)
	var scale_bonus = 1.0 + maxf(0.0, float(vine_level - 1)) * 0.22
	var cast_config = effects.duplicate(true)
	cast_config["tentacle_peak_scale"] = float(cast_config.get("tentacle_peak_scale", 1.2)) * scale_bonus
	cast_config["tentacle_initial_scale_x"] = float(cast_config.get("tentacle_initial_scale_x", 0.5)) * (1.0 + maxf(0.0, float(vine_level - 1)) * 0.15)
	for i in range(grab_count):
		var target_enemy = enemies_in_range[i]
		var tentacle = PoolManager.get_effect("vine_tentacle")
		if tentacle.has_method("launch"):
			tentacle.launch(target_enemy, final_damage, cast_config)

func _cast_seed_bomb():
	var skill = active_skills.get("seed_bomb", null)
	if skill == null:
		return
	var effects = _get_skill_effects("seed_bomb")
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
	var seed_bomb = PoolManager.get_effect("seed_bomb")
	seed_bomb.launch(tree_owner.global_position, target_pos, final_damage, radius, tick_interval, life_time, effects)

# ── 类别 B：元素附魔 (基于每次普攻) ─────────────────────────────
# 监听 treehead 发来的击中信号，判定有没有元素状态，直接附加给你
func _on_enemy_hit(damage: float, enemy_pos: Vector2, enemy_node: Node2D):
	if active_skills.has("ice_enchant"):
		var fx = _get_skill_effects("ice_enchant")
		if enemy_node and enemy_node.has_method("apply_slow"):
			var slow_ratio = 0.3
			if fx.has("slow_percent"):
				slow_ratio = maxf(0.3, float(fx["slow_percent"]))
			enemy_node.apply_slow(slow_ratio, float(fx.get("slow_duration", 2.0)))
			
	if active_skills.has("fire_enchant"):
		var fx_fire = _get_skill_effects("fire_enchant")
		var burn_interval = float(fx_fire.get("burn_interval", 0.4))
		var burn_tick_damage = float(fx_fire.get("burn_tick_damage", 5.0))
		if not fx_fire.has("burn_tick_damage"):
			burn_tick_damage = float(fx_fire.get("burn_dps", 4.0)) * burn_interval
		var burn_duration = float(fx_fire.get("burn_duration", 3.0))
		if enemy_node and enemy_node.has_method("apply_burn"):
			enemy_node.apply_burn(burn_tick_damage, burn_interval, burn_duration)
			
	if active_skills.has("lightning_enchant") and is_instance_valid(enemy_node):
		var fx_lighting = _get_skill_effects("lightning_enchant")
		var chain_dmg = float(fx_lighting.get("chain_damage", 5.0))
		var chain_count = int(fx_lighting.get("chain_count", 3))
		_cast_chain_lightning(enemy_node, enemy_node.global_position, chain_dmg, chain_count)

func _cast_chain_lightning(start_node: Node2D, start_pos: Vector2, chain_damage: float, max_bounces: int) -> void:
	var chain_targets = [start_node]
	var current_node = start_node
	var current_pos = start_pos
	
	for _i in range(max_bounces):
		var nearest = _get_nearest_target_from(current_pos, chain_targets, 300.0)
		if is_instance_valid(nearest):
			chain_targets.append(nearest)
			current_node = nearest
			current_pos = nearest.global_position
		else:
			break
			
	if chain_targets.size() <= 1:
		return
		
	var lightning_line = PoolManager.get_effect("lightning_enchant")
	if not (lightning_line is Line2D):
		return
		
	lightning_line.top_level = true
	lightning_line.global_position = Vector2.ZERO
	lightning_line.clear_points()
	
	for target in chain_targets:
		if is_instance_valid(target):
			lightning_line.add_point(target.global_position)
			# Do not damage the first target again
			if target != start_node and target.has_method("take_damage"):
				target.take_damage(chain_damage, current_pos)
				
	lightning_line.modulate = Color(1.5, 1.5, 2.0, 1.0)
	var tween = create_tween()
	tween.tween_property(lightning_line, "modulate:a", 0.0, 0.2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_callback(PoolManager.return_effect.bind(lightning_line, "lightning_enchant"))

func _get_nearest_target_from(pos: Vector2, exclude_list: Array, max_dist: float) -> Node2D:
	var enemies = get_tree().get_nodes_in_group("Enemy")
	var closest_dist = max_dist
	var nearest_enemy = null
	for e in enemies:
		if is_instance_valid(e) and e.process_mode != Node.PROCESS_MODE_DISABLED and e.has_method("take_damage"):
			if not exclude_list.has(e):
				var dist = e.global_position.distance_to(pos)
				if dist < closest_dist:
					closest_dist = dist
					nearest_enemy = e
	return nearest_enemy

func _set_tree_fire_enchant_fx(enabled: bool, level: int = 0) -> void:
	var particles = tree_owner.get_node_or_null("treehead/FireEnchantParticles")
	if particles == null:
		particles = tree_owner.find_child("FireEnchantParticles", true, false)
	if particles and particles is GPUParticles2D:
		var p = particles as GPUParticles2D
		p.z_as_relative = false
		p.z_index = -2
		p.visible = enabled
		p.emitting = enabled
		if enabled:
			p.amount_ratio = minf(1.0, 0.3 + float(level) * 0.2)

func _set_tree_ice_enchant_fx(enabled: bool, level: int = 0) -> void:
	var ice_nodes: Array = []
	var root_node = tree_owner.get_node_or_null("treehead")
	if root_node:
		ice_nodes.append_array(root_node.find_children("IceEnchantParticles*", "GPUParticles2D", true, false))
	ice_nodes.append_array(tree_owner.find_children("IceEnchantParticles*", "GPUParticles2D", true, false))
	for node in ice_nodes:
		if not (node is GPUParticles2D):
			continue
		var p = node as GPUParticles2D
		p.visible = enabled
		p.emitting = enabled
		if enabled:
			p.amount_ratio = minf(1.0, 0.25 + float(level) * 0.15)

# ── 类别 C：基础属性被动提升 ────────────────────────────────────
func _apply_base_stats(skill_id: String, prev_eff: Dictionary, new_eff: Dictionary):
	if new_eff.has("max_hp_bonus"):
		var prev_bonus = float(prev_eff.get("max_hp_bonus", 0.0))
		var new_bonus = float(new_eff.get("max_hp_bonus", 0.0))
		var add_bonus = maxf(0.0, new_bonus - prev_bonus)
		GameData.player_base_stats["max_hp"] += add_bonus
		GameData.current_hp += add_bonus
		GameData.current_hp = minf(GameData.current_hp, GameData.player_base_stats["max_hp"])
		SignalBus.on_player_hp_changed.emit(GameData.current_hp, GameData.player_base_stats["max_hp"])
		if skill_id == "thick_bark" and tree_owner.has_method("apply_trunk_width_multiplier"):
			var prev_mult = float(prev_eff.get("trunk_width_mult", 1.0))
			var new_mult = float(new_eff.get("trunk_width_mult", 1.0))
			var step_mult = 1.0
			if prev_mult > 0.0:
				step_mult = new_mult / prev_mult
			tree_owner.apply_trunk_width_multiplier(step_mult)
	if new_eff.has("hp_regen"):
		var prev_regen = float(prev_eff.get("hp_regen", 0.0))
		var next_regen = float(new_eff.get("hp_regen", 0.0))
		GameData.player_base_stats["hp_regen"] += maxf(0.0, next_regen - prev_regen)
		if skill_id == "deep_roots" and tree_owner.has_method("apply_root_scale_multiplier"):
			var prev_root = float(prev_eff.get("root_scale_mult", 1.0))
			var next_root = float(new_eff.get("root_scale_mult", 1.0))
			var step_root = 1.0
			if prev_root > 0.0:
				step_root = next_root / prev_root
			tree_owner.apply_root_scale_multiplier(step_root)
	if new_eff.has("attack_mult"):
		var prev_atk = float(prev_eff.get("attack_mult", 1.0))
		var next_atk = float(new_eff.get("attack_mult", 1.0))
		var step_atk = 1.0
		if prev_atk > 0.0:
			step_atk = next_atk / prev_atk
		GameData.player_base_stats["attack_power"] *= step_atk
	if new_eff.has("range_mult"):
		var prev_range = float(prev_eff.get("range_mult", 1.0))
		var next_range = float(new_eff.get("range_mult", 1.0))
		var step_range = 1.0
		if prev_range > 0.0:
			step_range = next_range / prev_range
		GameData.player_base_stats["attack_range"] *= step_range
		if skill_id == "wide_canopy":
			if tree_owner.has_method("apply_canopy_scale_multiplier"):
				var prev_canopy = float(prev_eff.get("canopy_sprite_mult", 1.0))
				var next_canopy = float(new_eff.get("canopy_sprite_mult", 1.0))
				var step_canopy = 1.0
				if prev_canopy > 0.0:
					step_canopy = next_canopy / prev_canopy
				tree_owner.apply_canopy_scale_multiplier(step_canopy)
			var treehead = tree_owner.get_node_or_null("treehead")
			if treehead and treehead.has_method("apply_hit_shape_scale_multiplier"):
				var prev_hit = float(prev_eff.get("hitbox_shape_mult", 1.0))
				var next_hit = float(new_eff.get("hitbox_shape_mult", 1.0))
				var step_hit = 1.0
				if prev_hit > 0.0:
					step_hit = next_hit / prev_hit
				treehead.apply_hit_shape_scale_multiplier(step_hit)
	if new_eff.has("stretch_scale_bonus"):
		var treehead = tree_owner.get_node_or_null("treehead")
		if treehead and treehead.get("max_stretch_scale") != null:
			var prev_stretch = float(prev_eff.get("stretch_scale_bonus", 0.0))
			var next_stretch = float(new_eff.get("stretch_scale_bonus", 0.0))
			treehead.max_stretch_scale += maxf(0.0, next_stretch - prev_stretch)
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
