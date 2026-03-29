# EnemyAI.gd (基础敌人脚本)
class_name EnemyBase extends CharacterBody2D

# ==========================================
# 核心设计参数
# ==========================================
@export var speed: float = 120.0
@export var attraction_weight: float = 1.0 
@export var repulsion_weight: float = 2.0 
@export var max_health: float = 10.0 
@export var exp_drop: float = 1.0 
@export var damage: float = 5.0 # 怪物对树造成的伤害（飞虫1，河狸可以设为5）
@export var is_flying_unit: bool = false # 勾选后开启 360 度旋转，否则只左右翻转

@onready var separation_area: Area2D = $SeparationArea
@onready var anim: AnimatedSprite2D = $AnimatedSprite2D # 统一获取动画节点

var target_tree: Node2D = null
var current_health: float
var tween: Tween
var can_move: bool = true # 控制状态开关（比如河狸咬人时需要停下）

var frame_count: int = 0
var cached_repulsion: Vector2 = Vector2.ZERO
var speed_multiplier: float = 1.0

func _ready() -> void:
	current_health = max_health
	var trees = get_tree().get_nodes_in_group("Tree")
	if trees.size() > 0:
		target_tree = trees[0]
	
	# 如果有飞行或走路的默认动画，确保它播放
	if anim.sprite_frames.has_animation("walk"):
		anim.play("walk")
	elif anim.sprite_frames.has_animation("fly"):
		anim.play("fly")

func reset() -> void:
	# 【关键修复】：每次从对象池醒来，重新睁开眼睛找大树！
	var trees = get_tree().get_nodes_in_group("Tree")
	if trees.size() > 0:
		target_tree = trees[0]
		
	current_health = max_health
	speed_multiplier = 1.0
	cached_repulsion = Vector2.ZERO
	can_move = true 
	set_physics_process(true)
	anim.modulate = Color(1.0, 1.0, 1.0, 1.0) 
	
	if tween:
		tween.kill()
		tween = null

	# 【手感优化】：重置时起步速度直接拉满，跳过缓慢加速期，压迫感剧增！
	if is_instance_valid(target_tree):
		var dir = (target_tree.global_position - global_position).normalized()
		velocity = dir * speed 
	else:
		velocity = Vector2.ZERO

func _physics_process(delta: float) -> void:
	if not is_instance_valid(target_tree): return
	
	# 给子类预留的自定义逻辑接口
	_custom_behavior(delta)
	
	# 如果状态不允许移动（比如正在攻击），直接停止计算寻路
	if not can_move:
		return

	# ==========================================
	# 1. Boids 寻路与排斥逻辑计算
	# ==========================================
	var dir_to_tree = (target_tree.global_position - global_position).normalized()
	var seek_force = dir_to_tree * speed * attraction_weight
	
	frame_count += 1
	if frame_count % 5 == 0:
		cached_repulsion = Vector2.ZERO
		var neighbors = separation_area.get_overlapping_bodies()
		for neighbor in neighbors:
			if neighbor != self and neighbor is CharacterBody2D:
				var dist_vector = global_position - neighbor.global_position
				var dist = dist_vector.length()
				if dist > 0.1: 
					cached_repulsion += (dist_vector.normalized() / dist) * speed * 5.0
		if cached_repulsion.length() > speed * 3:
			cached_repulsion = cached_repulsion.normalized() * speed * 3

	var desired_velocity = seek_force + (cached_repulsion * repulsion_weight)
	var final_speed = desired_velocity.limit_length(speed) * speed_multiplier
	velocity = velocity.lerp(final_speed, 0.1)

	# ==========================================
	# 2. 视线与朝向控制 (完美分离飞行与地面单位)
	# ==========================================
	if is_flying_unit:
		# 飞虫逻辑：360 度看向实际飞行的方向，+PI/2 修正素材角度
		rotation = velocity.angle() + (PI / 2)
	else:
		# 河狸逻辑：保持水平，只做左右翻转
		if velocity.x < 0:
			anim.flip_h = true
		elif velocity.x > 0:
			anim.flip_h = false

	# 执行 Godot 内部移动逻辑
	move_and_slide()

# 这个空函数是留给河狸等特殊怪物的
func _custom_behavior(delta: float) -> void:
	pass

func apply_slow(ratio: float, duration: float) -> void:
	speed_multiplier = clampf(1.0 - ratio, 0.1, 1.0)
	anim.modulate = Color(0.3, 0.6, 1.0, 1.0) # 变成蓝色
	var timer = get_tree().create_timer(duration)
	timer.timeout.connect(func():
		anim.modulate = Color(1.0, 1.0, 1.0, 1.0)
		speed_multiplier = 1.0
	)

func take_damage(dmg: float, attack_source_position: Vector2) -> void:
	current_health -= dmg
	# 简单的受击闪白光 Juice
	anim.modulate = Color(10, 10, 10, 1) # 瞬间高亮
	get_tree().create_timer(0.1).timeout.connect(func(): if is_instance_valid(self): anim.modulate = Color(1,1,1,1))
	
	if current_health <= 0:
		die(attack_source_position)

func die(attack_source_position: Vector2) -> void:
	SignalBus.on_enemy_died.emit(exp_drop, global_position)
	play_death_animation(attack_source_position)

func play_death_animation(attack_source_position: Vector2) -> void:
	set_physics_process(false)
	var knockback_direction = (global_position - attack_source_position).normalized()
	if knockback_direction == Vector2.ZERO: knockback_direction = Vector2.UP
	var knockback_distance = 400.0
	var knockback_duration = 0.4
	tween = create_tween()
	tween.tween_property(self, "global_position", global_position + knockback_direction * knockback_distance, knockback_duration)\
		.set_trans(Tween.TRANS_EXPO)\
		.set_ease(Tween.EASE_OUT)
	
	# 使用 bind 完美替代 lambda，语法极简，绝不报错！
	tween.tween_callback(PoolManager.return_enemy.bind(self))
