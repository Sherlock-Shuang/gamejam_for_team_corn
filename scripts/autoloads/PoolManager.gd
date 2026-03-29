extends Node
# ═══════════════════════════════════════════════════════════════
#  PoolManager.gd — 全局对象池 (Autoload)
#  Game Jam 终极优化版：多怪物类型支持 + 纯状态冻结回收
# ═══════════════════════════════════════════════════════════════

# 1. 预加载所有敌人场景
var enemy_scenes: Dictionary = {
	"fly": preload("res://scenes/actors/EnemyFly.tscn"),     # 确认路径正确
	"beaver": preload("res://scenes/actors/EnemyBeaver.tscn"), # 确认路径正确
	"human": preload("res://scenes/actors/EnemyHuman.tscn")
}

# 2. 对象池存储字典
var _pools: Dictionary = {
	"fly": [],
	"beaver": [],
	"human": []
}

var enemy_type_to_data_id: Dictionary = {
	"fly": "beetle",
	"beaver": "beaver",
	"human": "lumberjack"
}

func _ready() -> void:
	# 游戏启动时偷偷把怪建好，藏在后台，防止第一波刷怪时卡顿
	prewarm("fly", 50)
	prewarm("beaver", 20)
	prewarm("human", 15)

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
		
		# 直接作为 PoolManager 的子节点，永远不 Remove！
		add_child(enemy)
		_pools[enemy_type].append(enemy)
		
	print("[PoolManager] 成功预热 %d 个 %s" % [count, enemy_type])

## 获取怪物（供 WaveManager 调用）
func get_enemy(enemy_type: String, spawn_pos: Vector2) -> Node2D:
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
		add_child(enemy)
		
	# 唤醒怪物！
	var safe_spawn_pos = spawn_pos
	if GameData.is_in_river(safe_spawn_pos):
		safe_spawn_pos = GameData.clamp_to_river_bank(safe_spawn_pos, 8.0)
	enemy.global_position = safe_spawn_pos
	_apply_enemy_stats(enemy, enemy_type)
	
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
		
	return enemy

func _apply_enemy_stats(enemy: Node, enemy_type: String) -> void:
	var data_id = enemy_type_to_data_id.get(enemy_type, enemy_type)
	var stats = GameData.get_enemy_stats(data_id)
	if stats.is_empty():
		# 数据表缺失时的兜底，避免 speed=0 导致敌人卡在出生圈
		stats = {
			"hp": 10.0,
			"speed": 40.0,
			"damage": 2.0,
			"exp_drop": 1.0
		}
		push_warning("[PoolManager] 缺少敌人数据映射，已使用默认兜底: " + enemy_type)
	if enemy.get("max_health") != null and stats.has("hp"):
		enemy.max_health = float(stats["hp"])
	if enemy.get("speed") != null and stats.has("speed"):
		enemy.speed = float(stats["speed"])
	if enemy.get("damage") != null and stats.has("damage"):
		enemy.damage = float(stats["damage"])
	if enemy.get("exp_drop") != null and stats.has("exp_drop"):
		enemy.exp_drop = float(stats["exp_drop"])

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
	
	# 避免重复回收报错
	if pool_array.has(node):
		return
		
	# 【性能优化核心】：坚决不用 remove_child！
	node.process_mode = Node.PROCESS_MODE_DISABLED
	node.hide()
	
	# 如果有动画发光残留，在这里重置（确保下次拿出来是干净的）
	if node.has_node("AnimatedSprite2D"):
		node.get_node("AnimatedSprite2D").modulate = Color(1, 1, 1, 1)
		
	pool_array.append(node)

## 新关卡重置：强制回收所有正在活动的敌人
func reset_pools() -> void:
	for pool_key in _pools.keys():
		var pool_array = _pools[pool_key]
		# 遍历所有的子节点，如果是这个类型的活着的敌人，就强制回收
		for child in get_children():
			if child.has_meta("pool_key") and child.get_meta("pool_key") == pool_key:
				if not pool_array.has(child):
					return_enemy(child)
