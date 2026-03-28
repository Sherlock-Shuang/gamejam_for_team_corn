extends Node
# ═══════════════════════════════════════════════════════════════
#  PoolManager.gd — 全局对象池 (Autoload)
#  专治反复 Instantiate() 造成的游戏掉帧。
# ═══════════════════════════════════════════════════════════════

# 数据结构：字典。Key 为路径(String)或 PackedScene，Value 为 Array[Node]
var _pools: Dictionary = {}

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
			# 恢复节点状态
			instance.process_mode = Node.PROCESS_MODE_INHERIT
			if instance is CanvasItem or instance is Node2D or instance is Node3D:
				instance.show()
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
		
	# 拔出场景树，或者直接禁用 (为了避免复杂的 add/remove 消耗，推荐保留在树里但是隐藏)
	if node.get_parent():
		node.get_parent().remove_child(node)
		
	node.process_mode = Node.PROCESS_MODE_DISABLED
	if node is CanvasItem or node is Node2D or node is Node3D:
		node.hide()
		
	pool_array.append(node)

# --- 兼容旧代码的方法 ---
var enemy_scene: PackedScene = preload("res://scenes/actors/Enemy.tscn")
func get_enemy(spawn_pos: Vector2) -> Node2D:
	var enemy = enemy_scene.instantiate()
	enemy.global_position = spawn_pos
	# 将生成的怪物直接挂载到当前主场景的根节点下
	get_tree().current_scene.add_child(enemy)
	return enemy
