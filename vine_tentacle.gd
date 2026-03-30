extends Node2D

@onready var sprite: Sprite2D = $Sprite2D

var target_enemy: Node2D
var damage: float = 0.0
var original_scale: Vector2 = Vector2.ONE
var original_modulate: Color = Color.WHITE
var original_collision_layer: int = 0
var original_collision_mask: int = 0
var had_physics_processing: bool = true

func _ready() -> void:
	# 初始隐藏，等待 launch 被调用
	hide()

# ==========================================
# 处决执行接口
# ==========================================
func launch(enemy: Node2D, dmg: float, config: Dictionary = {}) -> void:
	if not is_instance_valid(enemy):
		PoolManager.return_effect(self, "vine_tentacle")
		return
		
	target_enemy = enemy
	damage = dmg
	z_as_relative = false
	z_index = 80
	original_scale = target_enemy.scale
	original_modulate = target_enemy.modulate
	
	global_position = _get_spawn_position_under_enemy(target_enemy, config)
	show()
	
	if target_enemy.has_method("set_physics_process"):
		had_physics_processing = target_enemy.is_physics_processing()
		target_enemy.set_physics_process(false)
	if target_enemy is CollisionObject2D:
		var collision_object = target_enemy as CollisionObject2D
		original_collision_layer = collision_object.collision_layer
		original_collision_mask = collision_object.collision_mask
		collision_object.collision_layer = 0
		collision_object.collision_mask = 0
	if target_enemy.has_method("suspend_combat"):
		target_enemy.suspend_combat()
			
	_play_execution_animation(config)

func _play_execution_animation(config: Dictionary = {}) -> void:
	# 触手破土而出的动画
	var initial_scale_x = float(config.get("tentacle_initial_scale_x", 0.5))
	var peak_scale = float(config.get("tentacle_peak_scale", 1.2))
	var rise_duration = float(config.get("rise_duration", 0.2))
	var hold_duration = float(config.get("hold_duration", 0.2))
	var sink_duration = float(config.get("sink_duration", 0.4))
	sprite.scale = Vector2(initial_scale_x, 0.0)
	sprite.modulate = Color(0.5, 1.0, 0.45, 1.0)
	
	var tween = create_tween()
	
	# 阶段 1：触手极速钻出地面 (0.2秒)
	tween.tween_property(sprite, "scale", Vector2(peak_scale, peak_scale), maxf(0.06, rise_duration)).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	
	# 阶段 2：僵直停顿一下，让玩家看清怪物被捆住了 (0.2秒)
	tween.tween_interval(maxf(0.02, hold_duration))
	
	# 阶段 3：连怪带触手，一起拖入地下！
	# 注意：我们这里并行执行，触手缩回地里，同时把怪物的 Y 轴拉长/透明化，模拟“沉入地下”
	if is_instance_valid(target_enemy):
		tween.parallel().tween_property(sprite, "scale:y", 0.0, maxf(0.06, sink_duration)).set_trans(Tween.TRANS_SINE)
		
		# 让怪物像被碾碎一样拉低 Y 轴比例，同时变黑变透明
		tween.parallel().tween_property(target_enemy, "scale:y", 0.1, maxf(0.06, sink_duration))
		tween.parallel().tween_property(target_enemy, "modulate", Color(0.2, 0.0, 0.0, 0.0), maxf(0.06, sink_duration))
	
	# 阶段 4：动画播完，正式结算伤害，然后销毁触手
	tween.chain().tween_callback(_finish_execution)

func _finish_execution() -> void:
	var should_restore = false
	if is_instance_valid(target_enemy) and target_enemy.has_method("take_damage"):
		target_enemy.take_damage(damage, global_position)
		if target_enemy.get("current_health") != null:
			should_restore = float(target_enemy.get("current_health")) > 0.0
		else:
			should_restore = true
	elif is_instance_valid(target_enemy):
		should_restore = true
	if should_restore and is_instance_valid(target_enemy):
		if target_enemy.has_method("set_physics_process"):
			target_enemy.set_physics_process(had_physics_processing)
		if target_enemy is CollisionObject2D:
			var collision_object = target_enemy as CollisionObject2D
			collision_object.collision_layer = original_collision_layer
			collision_object.collision_mask = original_collision_mask
		if target_enemy.has_method("resume_combat"):
			target_enemy.resume_combat()
		target_enemy.scale = original_scale
		target_enemy.modulate = original_modulate
	PoolManager.return_effect(self, "vine_tentacle")

func _get_spawn_position_under_enemy(enemy: Node2D, config: Dictionary) -> Vector2:
	var fallback_offset = float(config.get("spawn_foot_offset", 24.0))
	var enemy_pos = enemy.global_position
	var max_bottom_delta = 0.0
	for node in enemy.get_children():
		if not (node is CollisionShape2D):
			continue
		var shape_node = node as CollisionShape2D
		if shape_node.disabled or shape_node.shape == null:
			continue
		var half_height = _get_shape_half_height(shape_node.shape)
		var world_half_height = half_height * absf(shape_node.global_scale.y)
		var bottom_y = shape_node.global_position.y + world_half_height
		max_bottom_delta = maxf(max_bottom_delta, bottom_y - enemy_pos.y)
	if max_bottom_delta <= 0.0:
		max_bottom_delta = fallback_offset
	return Vector2(enemy_pos.x, enemy_pos.y + max_bottom_delta)

func _get_shape_half_height(shape: Shape2D) -> float:
	if shape is CircleShape2D:
		return (shape as CircleShape2D).radius
	if shape is RectangleShape2D:
		return (shape as RectangleShape2D).size.y * 0.5
	if shape is CapsuleShape2D:
		var capsule = shape as CapsuleShape2D
		return capsule.radius + capsule.height * 0.5
	return 0.0
