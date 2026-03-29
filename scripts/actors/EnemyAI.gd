extends CharacterBody2D

# ==========================================
# 核心设计参数
# ==========================================
@export var speed: float = 120.0
@export var attraction_weight: float = 1.0  # 向心引力权重
@export var repulsion_weight: float = 2.0   # 互斥力权重（调大可以让虫群散得更开）
@export var max_health: float = 10.0        # 最大生命值
@export var exp_drop: float = 1.0           # 死亡时掉落的经验值

# 引用我们在第一步建好的传感器 (用于推开同类)
@onready var separation_area: Area2D = $SeparationArea

# 缓存树的引用，避免每帧去查找
var target_tree: Node2D = null
var current_health: float
var tween: Tween

# ==========================================
# 对象池重置接口：每次从对象池取出时必须调用
# ==========================================
func reset() -> void:
	# 1. 恢复生命与战斗数值
	current_health = max_health
	speed_multiplier = 1.0
	velocity = Vector2.ZERO
	cached_repulsion = Vector2.ZERO
	
	# 2. 恢复物理与视觉状态
	set_physics_process(true)
	if has_node("ColorRect"):
		$ColorRect.color = Color(1.0, 0.0, 0.0, 1.0) # 还原初始红色
		
	# 3. 彻底清理上一轮残留的 Tween 动画，防止“灵异位移”
	if tween:
		tween.kill()
		tween = null
var frame_count: int = 0
var cached_repulsion: Vector2 = Vector2.ZERO

func _ready() -> void:
	current_health = max_health
	# 利用分组，全局安全地获取树的引用
	_find_target_tree()


func _find_target_tree():
	var trees = get_tree().get_nodes_in_group("Tree")
	if trees.size() > 0:
		target_tree = trees[0]
	else:
		target_tree = null



func _physics_process(delta: float) -> void:
	# 如果树死了（或者还没生成），尝试重新查找
	if not is_instance_valid(target_tree):
		_find_target_tree()
		if not is_instance_valid(target_tree):
			return


	# ==========================================
	# 1. 计算引力：趋向树干
	# ==========================================
	var dir_to_tree = (target_tree.global_position - global_position).normalized()
	var seek_force = dir_to_tree * speed * attraction_weight

	# ==========================================
	# 2. 计算斥力：避免同类重叠 (交错优化大法)
	# ==========================================
	# 让几百个怪物不要挤在同一帧计算 O(N^2) 的重叠！分散到不同的帧去算
	frame_count += 1
	if frame_count % 5 == 0:
		cached_repulsion = Vector2.ZERO
		var neighbors = separation_area.get_overlapping_bodies() # 获取传感器内的所有物体
		
		for neighbor in neighbors:
			# 排除自己，且只对其他同类（CharacterBody2D）产生斥力
			if neighbor != self and neighbor is CharacterBody2D:
				var dist_vector = global_position - neighbor.global_position
				var dist = dist_vector.length()
				
				# 距离越近，斥力越巨大 (反比例函数)
				if dist > 0.1: 
					cached_repulsion += (dist_vector.normalized() / dist) * speed * 5.0

		# 限制斥力的最大阈值，防止虫群像爆炸一样飞出屏幕
		if cached_repulsion.length() > speed * 3:
			cached_repulsion = cached_repulsion.normalized() * speed * 3

	# ==========================================
	# 3. 向量合成与平滑运动
	# ==========================================
	var desired_velocity = seek_force + (cached_repulsion * repulsion_weight)
	
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
# 【新增参数】强制要求伤害来源传入它的位置 (attack_source_position)
func take_damage(damage: float, attack_source_position: Vector2) -> void:
	current_health -= damage
	if current_health <= 0:
		die(attack_source_position) # 把坐标传给 die

func die(attack_source_position: Vector2) -> void:
	print("💥 虫群被碾碎了！")

	# 发送敌人死亡信号
	SignalBus.on_enemy_died.emit(exp_drop, global_position)

	# 触发击飞动画，继续传递攻击源坐标
	play_death_animation(attack_source_position)

# 【核心修改】利用传入的坐标计算真实的物理击飞方向
func play_death_animation(attack_source_position: Vector2) -> void:
	set_physics_process(false)
	
	# 替换掉原来的随机方向！
	# 向量相减：用敌人的位置(global_position) 减去 攻击源的位置(attack_source_position)
	var knockback_direction = (global_position - attack_source_position).normalized()
	
	# 防错：如果两者坐标完全重叠（极小概率），给一个默认向上的力
	if knockback_direction == Vector2.ZERO:
		knockback_direction = Vector2.UP
		
	var knockback_distance = 400.0
	var knockback_duration = 0.4
	
	tween = create_tween()
	# 加上缓动曲线（TRANS_EXPO + EASE_OUT），让击飞呈现出“起步爆弹、后续摩擦减速”的真实感
	tween.tween_property(self, "global_position", global_position + knockback_direction * knockback_distance, knockback_duration)\
		.set_trans(Tween.TRANS_EXPO)\
		.set_ease(Tween.EASE_OUT)
	tween.tween_callback(func(): PoolManager.return_enemy(self))
	
