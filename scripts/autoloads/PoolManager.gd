extends Node
# 【Dev B 的临时替身】
# 等 Dev A 把真正的对象池写好后，直接替换这个文件里的逻辑
# 现在的目的只是保证 WaveManager 不报错

var enemy_scene: PackedScene = preload("res://scenes/actors/Enemy.tscn")

func get_enemy(spawn_pos: Vector2) -> Node2D:
    var enemy = enemy_scene.instantiate()
    enemy.global_position = spawn_pos
    # 将生成的怪物直接挂载到当前主场景的根节点下
    get_tree().current_scene.add_child(enemy)
    return enemy