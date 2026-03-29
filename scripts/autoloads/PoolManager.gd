extends Node
# ═══════════════════════════════════════════════════════════════
#  PoolManager.gd — 全局对象池 (Autoload)
#  Game Jam 终极优化版：多怪物类型支持 + 纯状态冻结回收
# ═══════════════════════════════════════════════════════════════

# 1. 预加载所有敌人场景
var enemy_scenes: Dictionary = {
	"fly": preload("res://scenes/actors/EnemyFly.tscn"),     # 确认路径正确
	"beaver": preload("res://scenes/actors/EnemyBeaver.tscn") # 确认路径正确
}

# 2. 对象池存储字典
var _pools: Dictionary = {
	"fly": [],
	"beaver": []
}

func _ready() -> void:
	# 游戏启动时偷偷把怪建好，藏在后台，防止第一波刷怪时卡顿
	prewarm("fly", 50)
	prewarm("beaver", 20)

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
	enemy.global_position = spawn_pos
	enemy.process_mode = Node.PROCESS_MODE_INHERIT # 解除冰封
	enemy.show()
	
	# 初始化血量和状态
	if enemy.has_method("reset"):
		enemy.reset()
		
	return enemy

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
