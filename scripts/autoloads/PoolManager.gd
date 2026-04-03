extends Node
# ═══════════════════════════════════════════════════════════════
#  PoolManager.gd — 全局对象池 (Autoload)
#  Game Jam 终极优化版：多怪物类型支持 + 纯状态冻结回收
# ═══════════════════════════════════════════════════════════════

# 1. 预加载所有敌人场景 (直接使用规范化的名称作为 Key)
var enemy_scenes: Dictionary = {
	"beetle": preload("res://scenes/actors/EnemyFly.tscn"),     
	"beaver": preload("res://scenes/actors/EnemyBeaver.tscn"), 
	"lumberjack": preload("res://scenes/actors/EnemyHuman.tscn"),
	"mech_boss": preload("res://scenes/actors/EnemyMachine.tscn")
}

# 2. 对象池存储字典
var _pools: Dictionary = {
	"beetle": [],
	"beaver": [],
	"lumberjack": [],
	"mech_boss": []
}

# --- 🔥【性能优化】：主动管理活跃敌人列表，彻底干掉 get_tree().get_nodes_in_group() ---
var active_enemies: Array[Node2D] = []

# 3. 预加载所有特效/抛射物场景
var effect_scenes: Dictionary = {
	"thorn_shot": preload("res://scenes/effects/PoisonSting.tscn"),
	"exploding_fruit": preload("res://scenes/effects/FruitRoot.tscn"),
	"lightning_field": preload("res://scenes/effects/Flash.tscn"),
	"lightning_enchant": preload("res://scenes/effects/ChainLightning.tscn"),
	"seed_bomb": preload("res://scenes/effects/SeedBomb.tscn"),
	"vine_tentacle": preload("res://scenes/effects/vine_tentacle.tscn")
}

# 4. 特效对象池存储字典
var _effect_pools: Dictionary = {
	"thorn_shot": [],
	"exploding_fruit": [],
	"lightning_field": [],
	"lightning_enchant": [],
	"seed_bomb": [],
	"vine_tentacle": []
}

func _ready() -> void:
	# 游戏启动时预热
	prewarm("beetle", 50)
	prewarm("beaver", 30)
	prewarm("lumberjack", 20)
	prewarm("mech_boss", 5)

	# 特效子弹预热
	prewarm_effect("thorn_shot", 50)
	prewarm_effect("exploding_fruit", 15)
	prewarm_effect("lightning_field", 10)
	prewarm_effect("lightning_enchant", 15)
	prewarm_effect("seed_bomb", 15)
	prewarm_effect("vine_tentacle", 15)
	
	active_enemies.clear()



## 【性能终极优化】：预热池子
func prewarm(enemy_type: String, count: int) -> void:
	if not enemy_scenes.has(enemy_type): return
	
	var scene = enemy_scenes[enemy_type]
	for i in range(count):
		var enemy = scene.instantiate()
		
		# 【神之一手】用 meta 打上基因标签，回收时一眼认出它是谁
		enemy.set_meta("pool_key", enemy_type) 
		
		# 冻结计算，隐藏显示
		enemy.process_mode = Node.PROCESS_MODE_DISABLED
		enemy.hide()
		
		# 【重要】：记录关卡原始缩放率，防止在不同精英怪转换中体型无限膨胀/缩水
		enemy.set_meta("base_scale", enemy.scale)
		
		# 直接作为 PoolManager 的子节点，永远不 Remove！
		add_child(enemy)
		_pools[enemy_type].append(enemy)
		
	print("[PoolManager] 成功预热 %d 个 %s" % [count, enemy_type])

var _has_shown_elite_hint: bool = false

## 获取怪物（供 WaveManager 调用）
func get_enemy(enemy_type: String, spawn_pos: Vector2, is_elite: bool = false) -> Node2D:
	if not _pools.has(enemy_type):
		push_error("[PoolManager] 找不到该怪物类型：" + enemy_type)
		return null
		
	var pool_array = _pools[enemy_type]
	var enemy: Node2D = null
	
	# 从池里取
	while pool_array.size() > 0:
		enemy = pool_array.pop_back()
		if is_instance_valid(enemy):
			break
		else:
			enemy = null
			
	# 如果池子干了，临时加班造一个
	if not enemy:
		enemy = enemy_scenes[enemy_type].instantiate()
		enemy.set_meta("pool_key", enemy_type)
		enemy.set_meta("base_scale", enemy.scale)
		add_child(enemy)
		
	# 唤醒怪物！
	var safe_spawn_pos = spawn_pos
	if GameData.is_in_river(safe_spawn_pos):
		safe_spawn_pos = GameData.clamp_to_river_bank(safe_spawn_pos, 8.0)
	enemy.global_position = safe_spawn_pos
	_apply_enemy_stats(enemy, enemy_type, is_elite)
	
	# ==========================================
	# 关键修复：直接重置节点的暂停模式和可见性
	# PROCESS_MODE_INHERIT 有时在跨场景时会失效，特别是父节点暂停状态混乱时。
	# 改为 PROCESS_MODE_ALWAYS 或 PROCESS_MODE_PAUSABLE
	# ==========================================
	enemy.process_mode = Node.PROCESS_MODE_PAUSABLE 
	enemy.show()
	
	# 初始化血量和状态
	if enemy.has_method("reset"):
		enemy.reset()
	
	if is_elite and not _has_shown_elite_hint:
		_has_shown_elite_hint = true
		SignalBus.on_first_elite_spawned.emit()
		
	active_enemies.append(enemy)
	return enemy

func _apply_enemy_stats(enemy: Node, enemy_type: String, is_elite: bool = false) -> void:
	var stats = GameData.get_enemy_stats(enemy_type)
	if stats.is_empty():
		# 数据表缺失时的兜底
		stats = {"hp": 10.0, "speed": 40.0, "damage": 2.0, "exp_drop": 1.0}
	
	# 【动态难度】：根据无尽模式的时长提升敌人属性
	var mult = GameData.get_endless_multiplier()
	var hp_mult = GameData.get_endless_hp_multiplier()
	
	# === 基础属性应用 ===
	var final_hp = float(stats["hp"]) * hp_mult
	var final_speed = float(stats["speed"]) * mult
	var final_damage = float(stats["damage"]) * mult
	
	# 【难度提升计划 D】：基于剧情模式关卡的全局速度倍率
	var stage_speed_mult = 1.0
	if not GameData.is_endless_mode:
		if GameData.current_playing_stage == 3:
			stage_speed_mult = 1.1
		elif GameData.current_playing_stage >= 4:
			stage_speed_mult = 1.2
	final_speed *= stage_speed_mult
	
	var final_scale = 1.0
	var final_exp = float(stats.get("exp_drop", 1.0))
	
	if is_elite:
		final_hp *= 5.0      # 【难度提升 C】：精英血量 5 倍
		final_speed *= 1.3   
		final_scale = 1.2    # 保持精英怪比普通怪稍微大一点点（1.2倍），且已通过元数据重置彻底防膨胀
		final_exp *= 6.0     # 经验也对应给多一点平衡
		enemy.modulate = Color(2.5, 0.4, 0.4, 1.0) # 极高浓度的狂暴深红 (警告色)
	else:
		# 普通怪：完全重置属性到标准倍率
		enemy.modulate = Color.WHITE
		final_scale = 1.0
	
	# === 实装到 Node ===
	# 关键：这些属性直接覆盖，不要使用 *=，否则池化循环后会无限倍增！
	if enemy.get("max_health") != null:
		enemy.max_health = final_hp
		if enemy.get("current_health") != null:
			enemy.current_health = final_hp
			
	if enemy.get("speed") != null:
		enemy.speed = final_speed
		
	if enemy.get("damage") != null:
		enemy.damage = final_damage
		
	if enemy.get("exp_drop") != null:
		enemy.exp_drop = final_exp

	# 攻击范围修正（必须要有一个基础值，如果没有就从 GameData 取，或者假设为 1.0）
	if enemy.get("attack_range") != null:
		# 如果是精英，基于默认值修正，而不是基于当前值（防止累加）
		enemy.attack_range = 1.0 * (2.0 if is_elite else 1.0)
		
	if enemy is Node2D:
		var base_s = enemy.get_meta("base_scale", Vector2.ONE)
		enemy.scale = base_s * final_scale


## 回收怪物（供 EnemyAI 死亡击飞结束后调用）
func return_enemy(node: Node) -> void:
	if not is_instance_valid(node):
		return
		
	# 读取基因标签，看看它该回哪个池子
	var path_key = node.get_meta("pool_key", "")
	if path_key == "" or not _pools.has(path_key):
		push_warning("[PoolManager] 试图回收非法对象，已直接销毁。")
		node.queue_free()
		return
		
	var pool_array = _pools[path_key]
	
	# 还原精英状态的影响 (Scale) — 使用 base_scale 精确恢复，防止体型漂移
	if node is Node2D:
		node.scale = node.get_meta("base_scale", Vector2.ONE)
	node.modulate = Color.WHITE
	
	# 避免重复回收报错

	if pool_array.has(node):
		return
		
	# 【性能优化核心】：坚决不用 remove_child！
	node.process_mode = Node.PROCESS_MODE_DISABLED
	node.hide()
	
	# 如果有动画发光残留，在这里重置（确保下次拿出来是干净的）
	if node.has_node("AnimatedSprite2D"):
		node.get_node("AnimatedSprite2D").modulate = Color(1, 1, 1, 1)
		
	active_enemies.erase(node)
	pool_array.append(node)

## 新关卡重置：强制回收所有正在活动的敌人与特效
## 🔥【性能优化】：统计当前场上活跃敌人数量 (变成 O(1) 操作)
func _count_alive_enemies() -> int:
	return active_enemies.size()

## 🔥【性能优化】：单次遍历 O(n) 替代原 O(n²) 双层循环
func reset_pools() -> void:
	var enemies_to_return = active_enemies.duplicate()
	for enemy in enemies_to_return:
		return_enemy(enemy)
		
	for child in get_children():
		if not is_instance_valid(child):
			continue
		if child.has_meta("effect_key"):
			var key = child.get_meta("effect_key")
			if _effect_pools.has(key) and not _effect_pools[key].has(child):
				return_effect(child, key)

## -------------------------------------------------------------
## 特效对象池相关接口
## -------------------------------------------------------------
func prewarm_effect(effect_type: String, count: int) -> void:
	if not effect_scenes.has(effect_type): return
	var scene = effect_scenes[effect_type]
	for i in range(count):
		var effect = scene.instantiate()
		effect.set_meta("effect_key", effect_type) 
		effect.process_mode = Node.PROCESS_MODE_DISABLED
		effect.hide()
		add_child(effect)
		_effect_pools[effect_type].append(effect)
	print("[PoolManager] 成功预热 %d 个特效 %s" % [count, effect_type])

func get_effect(effect_type: String) -> Node2D:
	if not _effect_pools.has(effect_type):
		push_error("[PoolManager] 找不到该特效类型：" + effect_type)
		return null
		
	var pool_array = _effect_pools[effect_type]
	var effect: Node2D = null
	
	while pool_array.size() > 0:
		effect = pool_array.pop_back()
		if is_instance_valid(effect):
			break
		else:
			effect = null
			
	if not effect:
		effect = effect_scenes[effect_type].instantiate()
		effect.set_meta("effect_key", effect_type)
		add_child(effect)
		
	effect.process_mode = Node.PROCESS_MODE_INHERIT
	effect.show()
	return effect

func return_effect(node: Node, hint_type: String = "") -> void:
	if not is_instance_valid(node):
		return
		
	var path_key = node.get_meta("effect_key", hint_type)
	if path_key == "" or not _effect_pools.has(path_key):
		node.queue_free()
		return
		
	var pool_array = _effect_pools[path_key]
	if pool_array.has(node):
		return
		
	node.process_mode = Node.PROCESS_MODE_DISABLED
	node.hide()
	pool_array.append(node)
