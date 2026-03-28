extends Node
# 【Dev B 的临时替身】
# 等 Dev A 把真正的对象池写好后，直接替换这个文件里的逻辑
# 现在的目的只是保证 WaveManager 不报错

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