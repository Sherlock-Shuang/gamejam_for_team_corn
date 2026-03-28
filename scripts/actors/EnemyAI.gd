extends CharacterBody2D

# --- 核心设计参数 ---
@export var speed: float = 120.0
@export var attraction_weight: float = 1.0  # 向心引力权重
@export var repulsion_weight: float = 2.0   # 互斥力权重（调大可以让虫群散得更开）

# 引用我们在第一步建好的传感器
@onready var separation_area: Area2D = $SeparationArea

# 缓存树的引用，避免每帧去查找
var target_tree: Node2D = null

func _ready():
    # 利用之前的分组，全局安全地获取树的引用
    var trees = get_tree().get_nodes_in_group("Tree")
    if trees.size() > 0:
        target_tree = trees[0]

func _physics_process(delta: float):
    # 如果树死了（或者还没生成），原地待命
    if not is_instance_valid(target_tree):
        return

    # ==========================================
    # 1. 计算引力：趋向树干
    # 公式: D_seek = Normalize(P_tree - P_enemy)
    # ==========================================
    var dir_to_tree = (target_tree.global_position - global_position).normalized()
    var seek_force = dir_to_tree * speed * attraction_weight

    # ==========================================
    # 2. 计算斥力：避免同类重叠
    # 公式: D_repel = Sum(Normalize(P_enemy - P_neighbor))
    # ==========================================
    var repulsion_force = Vector2.ZERO
    var neighbors = separation_area.get_overlapping_bodies() # 获取传感器内的所有物体
    
    for neighbor in neighbors:
        # 排除自己，且只对其他同类（CharacterBody2D）产生斥力
        if neighbor != self and neighbor is CharacterBody2D:
            var dist_vector = global_position - neighbor.global_position
            var dist = dist_vector.length()
            
            # 距离越近，斥力越巨大 (反比例函数)
            if dist > 0.1: 
                repulsion_force += (dist_vector.normalized() / dist) * speed * 5.0

    # 限制斥力的最大阈值，防止虫群像爆炸一样飞出屏幕
    if repulsion_force.length() > speed * 3:
        repulsion_force = repulsion_force.normalized() * speed * 3

    # ==========================================
    # 3. 向量合成与平滑运动
    # 公式: V = (Seek + Repel) * Speed
    # ==========================================
    var desired_velocity = seek_force + (repulsion_force * repulsion_weight)
    
    # 使用 lerp(线性插值) 模拟物理惯性和阻尼感，而不是瞬间转向
    velocity = velocity.lerp(desired_velocity.limit_length(speed), 0.1)

    # 执行 Godot 内部移动逻辑
    move_and_slide()