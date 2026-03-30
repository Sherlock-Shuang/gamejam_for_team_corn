# EnemyAI.gd (基础敌人脚本)
extends CharacterBody2D
class_name EnemyBase

# ==========================================
# 核心设计参数
# ==========================================
@export var attraction_weight: float = 1.0 
@export var repulsion_weight: float = 2.0 
@export var is_flying_unit: bool = false # 勾选后开启 360 度旋转，否则只左右翻转
# 音乐参数
@export var 死亡惨叫_sfx: AudioStream

# 下列数值现由 PoolManager 从 GameData 统一注入，取消 @export 以免产生混淆
var speed: float = 0.0
var max_health: float = 0.0
var exp_drop: float = 0.0
var damage: float = 0.0

@onready var separation_area: Area2D = $SeparationArea
@onready var anim: AnimatedSprite2D = $AnimatedSprite2D # 统一获取动画节点
@onready var hit_box: Area2D = $HitBox # 抓取你刚刚配置好的攻击判定区域
@onready var burn_particles: GPUParticles2D = get_node_or_null("BurnParticles")
@onready var ice_particles: GPUParticles2D = get_node_or_null("IceEnchantParticles")

var target_tree: Node2D = null
var current_health: float
var tween: Tween
var can_move: bool = true # 控制状态开关（比如河狸咬人时需要停下）

var frame_count: int = 0
var cached_repulsion: Vector2 = Vector2.ZERO
var speed_multiplier: float = 1.0
@export var river_avoid_margin: float = 48.0

# --- 攻击状态参数 ---
var is_attacking: bool = false
var attack_timer: float = 0.0
@export var attack_cooldown: float = 1.0 # 每隔 1 秒咬一口
var burn_tick_damage: float = 0.0
var burn_interval: float = 0.4
var burn_time_left: float = 0.0
var burn_tick_left: float = 0.0
var slow_ratio_applied: float = 0.0
var slow_time_left: float = 0.0

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
		
	# 【核心】：动态连接你配置好的 HitBox 的信号！
	if is_instance_valid(hit_box):
		if not hit_box.area_entered.is_connected(_on_hitbox_area_entered):
			hit_box.area_entered.connect(_on_hitbox_area_entered)
		if not hit_box.area_exited.is_connected(_on_hitbox_area_exited):
			hit_box.area_exited.connect(_on_hitbox_area_exited)
		if not hit_box.body_entered.is_connected(_on_hitbox_body_entered):
			hit_box.body_entered.connect(_on_hitbox_body_entered)
	if ice_particles == null:
		var node = find_child("IceEnchantParticles", true, false)
		if node and node is GPUParticles2D:
			ice_particles = node as GPUParticles2D

func reset() -> void:
	# 【关键修复】：每次从对象池醒来，重新睁开眼睛找大树！
	var trees = get_tree().get_nodes_in_group("Tree")
	if trees.size() > 0:
		target_tree = trees[0]
		
	current_health = max_health
	speed_multiplier = 1.0
	cached_repulsion = Vector2.ZERO
	can_move = true 
	is_attacking = false
	attack_timer = 0.0
	burn_tick_damage = 0.0
	burn_time_left = 0.0
	burn_tick_left = 0.0
	slow_ratio_applied = 0.0
	slow_time_left = 0.0
	speed_multiplier = 1.0
	resume_combat() # 唤醒时恢复所有碰撞检测框
	set_physics_process(true)
	anim.modulate = Color(1.0, 1.0, 1.0, 1.0) 
	if burn_particles:
		burn_particles.emitting = false
		burn_particles.hide()
	if ice_particles:
		ice_particles.emitting = false
		ice_particles.hide()
	
	if tween:
		tween.kill()
		tween = null

	# 【手感优化】：重置时起步速度直接拉满，跳过缓慢加速期，压迫感剧增！
	if is_instance_valid(target_tree):
		if speed <= 0.0:
			speed = 40.0
		var dir = (target_tree.global_position - global_position).normalized()
		velocity = dir * speed 
	else:
		velocity = Vector2.ZERO

func _physics_process(delta: float) -> void:
	if not is_instance_valid(target_tree): return
	if burn_time_left > 0.0:
		burn_time_left -= delta
		burn_tick_left -= delta
		if burn_tick_left <= 0.0:
			burn_tick_left = maxf(0.05, burn_interval)
			if burn_tick_damage > 0.0:
				take_damage(burn_tick_damage, global_position)
		if burn_time_left <= 0.0:
			_clear_burn()
	if slow_time_left > 0.0:
		slow_time_left -= delta
		if slow_time_left <= 0.0:
			_clear_slow()
	
	# 给子类预留的自定义逻辑接口
	_custom_behavior(delta)
	
	# 如果正在攻击，每秒造成伤害，但保持继续向树推进
	if is_attacking:
		attack_timer -= delta
		if attack_timer <= 0.0:
			if is_instance_valid(target_tree) and target_tree.has_method("take_damage"):
				target_tree.take_damage(damage)
			attack_timer = attack_cooldown

	# 如果状态不允许移动（比如被冰冻定住），直接停止计算寻路
	if not can_move:
		return

	# ==========================================
	# 1. Boids 寻路与排斥逻辑计算
	# ==========================================
	var nav_target = target_tree.global_position
	
	# 👇【修改点 1】：使用全局统一的防河流目标点修正
	if GameData.is_in_river(nav_target):
		nav_target = GameData.clamp_to_river_bank(nav_target, river_avoid_margin)
		
	var dir_to_tree = (nav_target - global_position).normalized()
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

	var boundary_force = _calculate_river_avoidance_force()
	var desired_velocity = seek_force + (cached_repulsion * repulsion_weight) + boundary_force
	var final_speed = desired_velocity.limit_length(speed) * speed_multiplier
	velocity = velocity.lerp(final_speed, 0.1)

	# ==========================================
	# 2. 视线与朝向控制 (完美分离飞行与地面单位)
	# ==========================================
	if is_flying_unit:
		# 飞虫逻辑：优先看向飞行方向；速度很小时，直接看向树避免朝向卡死
		if velocity.length() > 0.01:
			rotation = velocity.angle() + (PI / 2)
		else:
			look_at(target_tree.global_position)
			rotation += PI / 2.0
	else:
		# 地面单位逻辑：如果不是飞行单位（如甲虫、河狸），保持水平，只做左右翻转
		if velocity.x < 0:
			anim.flip_h = true
		elif velocity.x > 0:
			anim.flip_h = false

	# 执行 Godot 内部移动逻辑
	move_and_slide()
	_enforce_river_boundary()

# 这个空函数是留给河狸等特殊怪物的
func _custom_behavior(delta: float) -> void:
	pass

# ==========================================
# 👇【修改点 2】：彻底替换避障预测，所有单位均不能下水！
# ==========================================
func _calculate_river_avoidance_force() -> Vector2:
	# 预测怪物 0.3 秒后会走到哪里
	var projected_pos = global_position + velocity * 0.3
	
	# 如果预测点掉进水里了，产生一个强大的推力把它往岸边推
	if GameData.is_in_river(projected_pos):
		# 算出岸边的安全落脚点
		var safe_pos = GameData.clamp_to_river_bank(projected_pos, river_avoid_margin)
		# 计算逃离河流的方向
		var avoid_dir = (safe_pos - projected_pos).normalized()
		# 返回一个 2.5 倍速度的强力排斥力，让它丝滑转向
		return avoid_dir * speed * 2.5 
		
	return Vector2.ZERO

# ==========================================
# 👇【修改点 3】：彻底替换物理兜底，强制拉回所有落水单位
# ==========================================
func _enforce_river_boundary() -> void:
	if GameData.is_in_river(global_position):
		# 强制拽回岸边，加上 2.0 像素的缓冲，防止在多边形边缘反复横跳（抽搐）
		global_position = GameData.clamp_to_river_bank(global_position, 2.0)

# ==========================================
# 3. 攻击范围判定与触发
# ==========================================
func _on_hitbox_area_entered(area: Area2D) -> void:
	# 检查碰到的是不是树的 HurtBox
	if area.get_parent() == target_tree:
		is_attacking = true
		attack_timer = 0.0 # 刚碰到时立刻咬一口
		
		# 如果怪物有特殊的攻击动画，播放它
		if anim.sprite_frames.has_animation("attack"):
			anim.play("attack")

func _on_hitbox_area_exited(area: Area2D) -> void:
	if area.get_parent() == target_tree:
		is_attacking = false
		
		# 恢复走路或飞行状态
		if is_flying_unit and anim.sprite_frames.has_animation("fly"):
			anim.play("fly")
		elif anim.sprite_frames.has_animation("walk"):
			anim.play("walk")

func _on_hitbox_body_entered(body: Node2D) -> void:
	if body == target_tree:
		is_attacking = true
		attack_timer = 0.0

func apply_slow(ratio: float, duration: float) -> void:
	var target_ratio = clampf(ratio, 0.0, 0.9)
	slow_ratio_applied = maxf(slow_ratio_applied, target_ratio)
	speed_multiplier = clampf(1.0 - slow_ratio_applied, 0.1, 1.0)
	slow_time_left = maxf(slow_time_left, duration)
	anim.modulate = Color(0.3, 0.6, 1.0, 1.0) # 变成蓝色
	if ice_particles:
		ice_particles.show()
		ice_particles.emitting = true

func _clear_slow() -> void:
	slow_time_left = 0.0
	slow_ratio_applied = 0.0
	speed_multiplier = 1.0
	anim.modulate = Color(1.0, 1.0, 1.0, 1.0)
	if ice_particles:
		ice_particles.emitting = false
		ice_particles.hide()

func apply_burn(tick_damage: float, interval: float, duration: float) -> void:
	burn_tick_damage = maxf(burn_tick_damage, tick_damage)
	burn_interval = maxf(0.05, interval)
	burn_time_left = maxf(burn_time_left, duration)
	burn_tick_left = 0.0
	if burn_particles:
		burn_particles.show()
		burn_particles.emitting = true

func _clear_burn() -> void:
	burn_tick_damage = 0.0
	burn_time_left = 0.0
	burn_tick_left = 0.0
	if burn_particles:
		burn_particles.emitting = false
		burn_particles.hide()

func take_damage(dmg: float, attack_source_position: Vector2, knockback_force: float = 0.0) -> void:
	if current_health <= 0:
		return # 防止同一帧被多个判定框打中多次触发死亡
		
	current_health -= dmg
	
	# 简单的受击闪白光 Juice
	anim.modulate = Color(10, 10, 10, 1) # 瞬间高亮
	get_tree().create_timer(0.1).timeout.connect(func(): if is_instance_valid(self): anim.modulate = Color(1,1,1,1))
	
	if current_health <= 0:
		die(attack_source_position)
	else:
		if knockback_force > 0.0:
			var kb_dir = (global_position - attack_source_position).normalized()
			if kb_dir == Vector2.ZERO: kb_dir = Vector2.UP
			velocity += kb_dir * knockback_force

func die(attack_source_position: Vector2) -> void:
	_clear_burn()
	_clear_slow()
	SignalBus.on_enemy_died.emit(exp_drop, global_position)
	# 呼叫全局管家播放死亡惨叫！
	if 死亡惨叫_sfx:
		AudioManager.play_sfx(死亡惨叫_sfx, 0, true, 4)
	play_death_animation(attack_source_position)

func play_death_animation(attack_source_position: Vector2) -> void:
	set_physics_process(false)
	suspend_combat() # 死亡击飞时彻底关闭所有受击/攻击逻辑，防止尸体吸伤
	var knockback_direction = (global_position - attack_source_position).normalized()
	if knockback_direction == Vector2.ZERO: knockback_direction = Vector2.UP
	var knockback_distance = 400.0
	var knockback_duration = 0.4
	tween = create_tween().set_parallel(true)
	
	# 让击飞方向永远是从大树往外弹！绝对不会往回飞！
	var out_dir = Vector2.UP
	if is_instance_valid(target_tree):
		out_dir = (global_position - target_tree.global_position).normalized()
	if out_dir == Vector2.ZERO: out_dir = Vector2.UP
	
	# 1. 强力击飞离场
	tween.tween_property(self, "global_position", global_position + out_dir * 150.0, knockback_duration)\
		.set_trans(Tween.TRANS_EXPO)\
		.set_ease(Tween.EASE_OUT)
		
	# 2. 死亡翻滚
	var random_spin = randf_range(-PI * 4.0, PI * 4.0)
	tween.tween_property(anim, "rotation", random_spin, knockback_duration)\
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		
	# 3. 瞬间爆亮（不要太大，防止刺眼）
	anim.modulate = Color(8.0, 8.0, 8.0, 1.0)
	tween.tween_property(anim, "modulate:a", 0.0, knockback_duration)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		
	# 4. 根据原本自身的比例稍微放大后缩小，坚决不写死固定数值！
	var base_scale = anim.scale
	tween.tween_property(anim, "scale", base_scale * 1.3, knockback_duration * 0.3)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(anim, "scale", Vector2.ZERO, knockback_duration * 0.7)\
		.set_delay(knockback_duration * 0.3)\
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	
	# 重置属性的回调
	var reset_func = func():
		anim.rotation = 0.0
		anim.scale = base_scale # 恢复他们各自原本的缩放率
		PoolManager.return_enemy(self)
		
	tween.chain().tween_callback(reset_func)

func suspend_combat() -> void:
	if is_instance_valid(hit_box):
		hit_box.set_deferred("monitoring", false)
		hit_box.set_deferred("monitorable", false)
	var h_box = get_node_or_null("hurtbox")
	if not is_instance_valid(h_box):
		h_box = get_node_or_null("Hurtbox")
	if is_instance_valid(h_box):
		h_box.set_deferred("monitoring", false)
		h_box.set_deferred("monitorable", false)
	if is_instance_valid(separation_area):
		separation_area.set_deferred("monitoring", false)
		separation_area.set_deferred("monitorable", false)

func resume_combat() -> void:
	if is_instance_valid(hit_box):
		hit_box.set_deferred("monitoring", true)
		hit_box.set_deferred("monitorable", true)
	var h_box = get_node_or_null("hurtbox")
	if not is_instance_valid(h_box):
		h_box = get_node_or_null("Hurtbox")
	if is_instance_valid(h_box):
		h_box.set_deferred("monitoring", true)
		h_box.set_deferred("monitorable", true)
	if is_instance_valid(separation_area):
		separation_area.set_deferred("monitoring", true)
		separation_area.set_deferred("monitorable", true)

func _on_hit_box_area_entered(area: Area2D) -> void:
	_on_hitbox_area_entered(area)

func _on_hit_box_body_entered(body: Node2D) -> void:
	_on_hitbox_body_entered(body)
