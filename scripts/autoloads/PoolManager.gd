extends Node
# ═══════════════════════════════════════════════════════════════
#  PoolManager.gd — 全局对象池 (Autoload)
#  专治反复 Instantiate() 造成的游戏掉帧。
# ═══════════════════════════════════════════════════════════════

# 数据结构：字典。Key 为路径(String)或 PackedScene，Value 为 Array[Node]
var _pools: Dictionary = {}

## 【性能终极优化】：预热池子（开局调用一次，把几百个怪瞬间藏好）
func prewarm(scene: PackedScene, count: int, parent_node: Node) -> void:
	var path_key = scene.resource_path
	if not _pools.has(path_key):
		_pools[path_key] = []
		
	var arr = _pools[path_key]
	for i in range(count):
		var enemy = scene.instantiate()
		enemy.set_meta("pool_key", path_key)
		enemy.process_mode = Node.PROCESS_MODE_DISABLED
		if enemy.has_method("hide"):
			enemy.hide()
		parent_node.add_child(enemy)
		arr.append(enemy)
	print("[PoolManager] 已成功预热 (Pre-warm) 了 %d 个实体进入对象池。" % count)

## 获取一个对象池实例
func get_instance(res_path_or_scene) -> Node:
	var path_key = ""
	var scene: PackedScene = null
	
	if typeof(res_path_or_scene) == TYPE_STRING:
		path_key = res_path_or_scene
		scene = load(path_key)
	elif typeof(res_path_or_scene) == TYPE_OBJECT and res_path_or_scene is PackedScene:
		path_key = res_path_or_scene.resource_path
		scene = res_path_or_scene
	else:
		push_error("[PoolManager] 无效的资源池请求！")
		return null
		
	# 确保池子存在
	if not _pools.has(path_key):
		_pools[path_key] = []
		
	var pool_array = _pools[path_key]
	var instance: Node = null
	
	# 从池里取
	while pool_array.size() > 0:
		instance = pool_array.pop_back()
		if is_instance_valid(instance):
			# 恢复节点状态 (解除冻结冰封状态)
			instance.process_mode = Node.PROCESS_MODE_INHERIT
			if instance.has_method("show"):
				instance.show()
			
			# 如果节点带有 reset 自定义函数，则在这里初始化它
			if instance.has_method("reset"):
				instance.reset()
			break
		else:
			instance = null
			
	# 如果池里没东西，或者全坏了，就新造一个
	if not instance:
		instance = scene.instantiate()
		instance.set_meta("pool_key", path_key) # 印上归属印记
		
	return instance

## 用完之后回收，请用此方法代替 queue_free()
func return_instance(node: Node):
	if not is_instance_valid(node):
		return
		
	var path_key = node.get_meta("pool_key", "")
	if path_key == "":
		push_warning("[PoolManager] 试图回收不属于池管理的对象！将直接 queue_free()。")
		node.queue_free()
		return
		
	if not _pools.has(path_key):
		_pools[path_key] = []
		
	var pool_array = _pools[path_key]
	
	# 避免重复回收
	if pool_array.has(node):
		return
		
	# 【性能优化核心】：坚决不用 remove_child 拔出场景树了！
	# 只将它冻结逻辑计算，并隐藏显示，直接塞回待机队列。
	node.process_mode = Node.PROCESS_MODE_DISABLED
	if node.has_method("hide"):
		node.hide()
		
	pool_array.append(node)

# --- 兼容旧代码的方法 ---
var enemy_scene: PackedScene = preload("res://scenes/actors/Enemy.tscn")
var enemy_pool: Array = []  # 对象池

func get_enemy(spawn_pos: Vector2) -> Node2D:
	var enemy: Node2D
	if enemy_pool.size() > 0:
		enemy = enemy_pool.pop_back()
		enemy.global_position = spawn_pos
		enemy.show()  # 确保可见
		get_tree().current_scene.add_child(enemy)
	else:
		enemy = enemy_scene.instantiate()
		enemy.global_position = spawn_pos
		get_tree().current_scene.add_child(enemy)
	
	# 重置敌人状态
	if enemy.has_method("reset"):
		enemy.reset()
	
	return enemy

func return_enemy(enemy: Node2D) -> void:
	enemy.hide()  # 隐藏
	enemy.get_parent().remove_child(enemy)
	enemy_pool.append(enemy)