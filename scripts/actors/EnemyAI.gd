extends CharacterBody2D

# ==========================================
# 核心设计参数
# ==========================================
@export var speed: float = 120.0
@export var attraction_weight: float = 1.0  # 向心引力权重
@export var repulsion_weight: float = 2.0   # 互斥力权重（调大可以让虫群散得更开）

# 引用我们在第一步建好的传感器 (用于推开同类)
@onready var separation_area: Area2D = $SeparationArea

# 缓存树的引用，避免每帧去查找
var target_tree: Node2D = null

func _ready() -> void:
	# 利用分组，全局安全地获取树的引用
	# (确保你的主角树根节点或者整体加了 "Tree" 这个分组)
	var trees = get_tree().get_nodes_in_group("Tree")
	if trees.size() > 0:
		target_tree = trees[0]

func _physics_process(delta: float) -> void:
	# 如果树死了（或者还没生成），原地待命
	if not is_instance_valid(target_tree):
		return

	# ==========================================
	# 1. 计算引力：趋向树干
	# ==========================================
	var dir_to_tree = (target_tree.global_position - global_position).normalized()
	var seek_force = dir_to_tree * speed * attraction_weight

	# ==========================================
	# 2. 计算斥力：避免同类重叠
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
	# ==========================================
	var desired_velocity = seek_force + (repulsion_force * repulsion_weight)
	
	# 加入元素减速影响
	var final_speed = desired_velocity.limit_length(speed) * speed_multiplier
	
	# 使用 lerp(线性插值) 模拟物理惯性和阻尼感，而不是瞬间转向
	velocity = velocity.lerp(final_speed, 0.1)

	# 执行 Godot 内部移动逻辑
	move_and_slide()

# ==========================================
# 元素与状态控制
# ==========================================
var speed_multiplier: float = 1.0

func apply_slow(ratio: float, duration: float) -> void:
	speed_multiplier = clampf(1.0 - ratio, 0.1, 1.0)
	$ColorRect.color = Color(0.3, 0.6, 1.0, 1.0) # 变成蓝色
	# 创建一个一次性定时器恢复速度
	var timer = get_tree().create_timer(duration)
	timer.timeout.connect(func():
		$ColorRect.color = Color(1.0, 0.0, 0.0, 1.0) # 恢复红色
		speed_multiplier = 1.0
	)

# ==========================================
# 4. 战斗接口：专门暴露给树干调用的“受死”方法
# ==========================================
func die() -> void:
	print("💥 虫群被碾碎了！掉落经验。")
	
	# 抛出死亡事件 (让 Dev B 的逻辑知道)
	SignalBus.on_enemy_died.emit(1.0, global_position)
	
	# 无情销毁自己，后续改成 PoolManager
	queue_free()
