extends Node2D

# ==========================================
# 战斗与特效配置
# ==========================================
var explosion_radius: float = 50.0 

# 🔥 视觉调参区 (在右侧检查器可直接调整)
@export var flight_duration: float = 2.0      # 【新增】飞行时间：数值越大，飞得越慢（闪电球的压迫感）
@export var explosion_duration: float = 0.15  # 爆炸展开速度：瞬间炸到最大
@export var linger_duration: float = 1.0      # 【新增】悬留时间：达到最大半径后在场上停留多久
@export var fade_duration: float = 0.3        # 【新增】消散时间：悬留结束后变透明消失的时间
@export var texture_base_radius: float = 50.0 # 贴图原半径：如果美术画的爆炸图是 100x100，这里填 50

# 获取节点（已根据你的新截图匹配了节点名称！）
@onready var anim_sprite: AnimatedSprite2D = $AnimatedSprite2D 
@onready var explosion_sprite: Sprite2D = $Sprite2D            
@onready var explosion_area: Area2D = $Area2D
@onready var collision_shape: CollisionShape2D = $Area2D/CollisionShape2D

func _ready():
	# 初始状态配置
	collision_shape.set_deferred("disabled", true)
	anim_sprite.show() # 显示预警果实/闪电球
	explosion_sprite.hide() # 隐藏爆炸特效
	explosion_area.monitoring = true
	explosion_area.monitorable = true
	explosion_area.collision_layer = 4
	explosion_area.collision_mask = 2

# 发射接口：由大树的技能控制器调用
func launch(start_pos: Vector2, target_pos: Vector2, radius: float, damage: float) -> void:
	global_position = start_pos
	explosion_radius = radius
	collision_shape.scale = Vector2.ONE
	
	# 彻底隔离碰撞形状，防止影响其他同类实例
	var new_shape = CircleShape2D.new()
	new_shape.radius = radius
	collision_shape.shape = new_shape 
	
	# ==========================================
	# 🐌 飞行逻辑修改：使用新的 flight_duration
	# ==========================================
	var tween = create_tween().set_parallel(true)
	
	# 1. 缓慢直线飞向目标点
	tween.tween_property(self, "global_position", target_pos, flight_duration)
	
	# 2. 视觉欺骗：往上弹再落下 (依然适配缓慢的飞行时间)
	var jump_tween = create_tween()
	jump_tween.tween_property(anim_sprite, "position:y", -60.0, flight_duration / 2.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	jump_tween.tween_property(anim_sprite, "position:y", 0.0, flight_duration / 2.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	
	# 3. 飞行结束后，进入“引爆预警”阶段！
	tween.chain().tween_callback(func(): _trigger_fuse(damage))

func _trigger_fuse(damage: float) -> void:
	# 播放那 2 帧闪烁动画
	anim_sprite.play("warning")
	
	# 死等动画播放完毕！
	await anim_sprite.animation_finished
	
	# 动画播完，正式引爆！
	_explode(damage)

func _explode(damage: float) -> void:
	# ==========================================
	# 💥 状态切换：隐藏实体，亮出特效图
	# ==========================================
	anim_sprite.hide()
	explosion_sprite.show()
	
	# ==========================================
	# ⚔️ 伤害判定：瞬间爆发伤害
	# ==========================================
	collision_shape.set_deferred("disabled", false)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var hit_enemy_ids: Dictionary = {}
	for enemy in get_tree().get_nodes_in_group("Enemy"):
		if not is_instance_valid(enemy):
			continue
		if enemy.process_mode == Node.PROCESS_MODE_DISABLED:
			continue
		if not enemy.has_method("take_damage"):
			continue
		if enemy.global_position.distance_to(global_position) <= explosion_radius:
			var enemy_id = enemy.get_instance_id()
			if not hit_enemy_ids.has(enemy_id):
				hit_enemy_ids[enemy_id] = true
				enemy.take_damage(damage, global_position)
			
	# ==========================================
	# 🎨 特效表现 (Juice)：放大 -> 悬留 -> 消散
	# ==========================================
	var final_scale_size = explosion_radius / texture_base_radius
	
	explosion_sprite.scale = Vector2(0.08, 0.08)
	explosion_sprite.modulate.a = 1.0 
	
	# ⚠️ 注意：这里去掉了 set_parallel(true)，变成了按顺序执行的串行 Tween！
	var tween = create_tween()
	
	# 阶段 1：瞬间炸开到动态计算出的大小
	tween.tween_property(explosion_sprite, "scale", Vector2(final_scale_size, final_scale_size), explosion_duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	
	# 阶段 2：维持大小和透明度，静静地悬留一段时间 (神级延迟语法)
	tween.tween_interval(linger_duration)
	
	# 阶段 3：悬留结束后，缓慢变透明消散
	tween.tween_property(explosion_sprite, "modulate:a", 0.0, fade_duration)
	
	# 尘归尘土归土，彻底清空
	tween.tween_callback(queue_free)
