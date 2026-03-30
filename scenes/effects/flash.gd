extends Node2D

# ==========================================
# 战斗与特效配置
# ==========================================
var explosion_radius: float = 50.0 
var state: int = 0
var current_damage: float = 0.0
var last_flight_duration: float = 0.0
var last_speed_value: float = 0.0
var last_linger_duration: float = 0.0
var last_final_scale: float = 1.0
var last_decay_scale: float = 1.0
var _flight_hit_enemy_ids: Dictionary = {}
var _linger_tick_left: float = 0.0

# 🔥 视觉调参区 (在右侧检查器可直接调整)
@export var base_flight_duration: float = 0.5
@export var speed_ratio: float = 0.4
@export var explosion_duration: float = 0.15  # 爆炸展开速度：瞬间炸到最大
@export var linger_duration: float = 2.5
@export var fade_duration: float = 0.3        # 【新增】消散时间：悬留结束后变透明消失的时间
@export var texture_base_radius: float = 50.0 # 贴图原半径：如果美术画的爆炸图是 100x100，这里填 50
@export var linger_scale_ratio: float = 1.0
@export var burst_overshoot_ratio: float = 1.2
@export var scale_settle_duration: float = 0.1
@export var flight_hit_radius: float = 42.0
@export var flight_hit_damage_ratio: float = 0.35
@export var linger_tick_interval: float = 0.2
@export var linger_tick_damage_ratio: float = 0.5

# 获取节点（已根据你的新截图匹配了节点名称！）
@onready var anim_sprite: AnimatedSprite2D = $AnimatedSprite2D 
@onready var explosion_sprite: Sprite2D = $Sprite2D            
@onready var explosion_area: Area2D = $Area2D
@onready var collision_shape: CollisionShape2D = $Area2D/CollisionShape2D

# 音乐参数
@export var 飞行_sfx: AudioStream
@export var 爆炸_sfx: AudioStream


func _ready():
	_ensure_node_refs()
	# 初始状态配置
	collision_shape.set_deferred("disabled", true)
	anim_sprite.show() # 显示预警果实/闪电球
	explosion_sprite.hide() # 隐藏爆炸特效
	explosion_area.monitoring = true
	explosion_area.monitorable = true
	explosion_area.collision_layer = 4
	explosion_area.collision_mask = 2

func _ensure_node_refs() -> void:
	if anim_sprite == null:
		anim_sprite = get_node_or_null("AnimatedSprite2D")
	if explosion_sprite == null:
		explosion_sprite = get_node_or_null("Sprite2D")
	if explosion_area == null:
		explosion_area = get_node_or_null("Area2D")
	if collision_shape == null:
		collision_shape = get_node_or_null("Area2D/CollisionShape2D")

func get_effective_speed_ratio() -> float:
	return clampf(speed_ratio, 0.3, 0.5)

func get_effective_linger_duration() -> float:
	return clampf(linger_duration, 0.1, 3.0)

func compute_flight_duration(base_duration: float = base_flight_duration) -> float:
	return maxf(0.01, base_duration / get_effective_speed_ratio())

func compute_speed(distance: float, base_duration: float = base_flight_duration) -> float:
	return distance / compute_flight_duration(base_duration)

func compute_final_scale(radius: float) -> float:
	return radius / maxf(1.0, texture_base_radius)

func compute_decay_scale(final_scale: float) -> float:
	return final_scale * clampf(linger_scale_ratio, 0.0, 1.0)

# 发射接口：由大树的技能控制器调用
func launch(start_pos: Vector2, target_pos: Vector2, radius: float, damage: float, config: Dictionary = {}) -> void:
	_ensure_node_refs()
	if collision_shape == null or anim_sprite == null or explosion_sprite == null:
		return
	if config.has("speed_ratio"):
		speed_ratio = float(config["speed_ratio"])
	if config.has("linger_duration"):
		linger_duration = float(config["linger_duration"])
	if config.has("linger_scale_ratio"):
		linger_scale_ratio = float(config["linger_scale_ratio"])
	if config.has("burst_overshoot_ratio"):
		burst_overshoot_ratio = float(config["burst_overshoot_ratio"])
	if config.has("scale_settle_duration"):
		scale_settle_duration = float(config["scale_settle_duration"])
	_flight_hit_enemy_ids.clear()
	_linger_tick_left = 0.0
	global_position = start_pos
	explosion_radius = radius
	current_damage = damage
	collision_shape.scale = Vector2.ONE
	
	collision_shape.set_deferred("disabled", true)
	anim_sprite.show()
	explosion_sprite.hide()
	anim_sprite.position.y = 0.0
	anim_sprite.modulate = Color.WHITE
	explosion_sprite.modulate.a = 1.0
	
	# 彻底隔离碰撞形状，防止影响其他同类实例
	var new_shape = CircleShape2D.new()
	new_shape.radius = radius
	collision_shape.shape = new_shape 
	
	# ==========================================
	# 🐌 飞行逻辑修改：使用新的 flight_duration
	# ==========================================
	last_flight_duration = compute_flight_duration()
	last_speed_value = compute_speed(start_pos.distance_to(target_pos))
	state = 1
	var tween = create_tween().set_parallel(true)
	
	# 1. 缓慢直线飞向目标点
	tween.tween_property(self, "global_position", target_pos, last_flight_duration)
	
	# 2. 视觉欺骗：往上弹再落下 (依然适配缓慢的飞行时间)
	var jump_tween = create_tween()
	jump_tween.tween_property(anim_sprite, "position:y", -60.0, last_flight_duration / 2.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	jump_tween.tween_property(anim_sprite, "position:y", 0.0, last_flight_duration / 2.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	
	# 👇 【新增】起飞瞬间，播放带电飞行的声音
	AudioManager.play_sfx(飞行_sfx, 10, 1.0, 2, 2.75)  # 音量可以根据需要调整
	
	# 3. 飞行结束后，进入“引爆预警”阶段！
	tween.chain().tween_callback(func(): _trigger_fuse(damage))

func _physics_process(delta: float) -> void:
	if state == 1:
		_apply_flight_contact_damage(damage_from_ratio(flight_hit_damage_ratio))
	elif state == 4 or state == 5:
		_linger_tick_left -= delta
		if _linger_tick_left <= 0.0:
			_linger_tick_left = maxf(0.05, linger_tick_interval)
			_apply_linger_damage_tick(damage_from_ratio(linger_tick_damage_ratio))

func _trigger_fuse(damage: float) -> void:
	state = 2
	if anim_sprite.sprite_frames and anim_sprite.sprite_frames.has_animation("warning"):
		anim_sprite.play("warning")
		await anim_sprite.animation_finished
	else:
		if anim_sprite.sprite_frames and anim_sprite.sprite_frames.has_animation("move"):
			anim_sprite.play("move")
		await get_tree().create_timer(0.12).timeout
	
	# 动画播完，正式引爆！
	_explode(damage)

func _explode(damage: float) -> void:
	state = 3
	# ==========================================
	# 💥 状态切换：隐藏实体，亮出特效图
	# ==========================================
	anim_sprite.hide()
	explosion_sprite.show()

	# 👇 【新增】爆炸瞬间，强行切断飞行声音，播放轰鸣声
	AudioManager.play_sfx(爆炸_sfx, 10, 1.0, 1)  # 音量可以根据需要调整

	# ==========================================
	# ⚔️ 伤害判定：瞬间爆发伤害
	# ==========================================
	collision_shape.set_deferred("disabled", false)
	await get_tree().physics_frame
	await get_tree().physics_frame
	_apply_explosion_snapshot_damage(damage)
			
	# ==========================================
	# 🎨 特效表现 (Juice)：放大 -> 悬留 -> 消散
	# ==========================================
	var final_scale_size = compute_final_scale(explosion_radius)
	last_final_scale = final_scale_size
	last_decay_scale = compute_decay_scale(final_scale_size)
	last_linger_duration = get_effective_linger_duration()
	var peak_scale = last_decay_scale * clampf(burst_overshoot_ratio, 0.0, 1.6)
	
	explosion_sprite.scale = Vector2(0.08, 0.08)
	explosion_sprite.modulate.a = 1.0 
	
	# ⚠️ 注意：这里去掉了 set_parallel(true)，变成了按顺序执行的串行 Tween！
	var tween = create_tween()
	
	# 阶段 1：瞬间炸开到动态计算出的大小
	tween.tween_property(explosion_sprite, "scale", Vector2(peak_scale, peak_scale), explosion_duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(explosion_sprite, "scale", Vector2(last_decay_scale, last_decay_scale), maxf(0.04, scale_settle_duration)).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_callback(func():
		state = 4
		_linger_tick_left = 0.0
	)
	
	# 阶段 2：维持大小和透明度，静静地悬留一段时间 (神级延迟语法)
	tween.tween_interval(last_linger_duration)
	tween.tween_callback(func(): state = 5)
	
	# 阶段 3：悬留结束后，缓慢变透明消散
	tween.tween_property(explosion_sprite, "modulate:a", 0.0, fade_duration)
	
	# 尘归尘土归土，彻底清空
	tween.tween_callback(func():
		state = 6
		PoolManager.return_effect(self, "lightning_field")
	)

func damage_from_ratio(ratio: float) -> float:
	var clamped = clampf(ratio, 0.0, 3.0)
	return maxf(0.0, current_damage * float(clamped))

func _get_active_enemies() -> Array:
	var result: Array = []
	for enemy in get_tree().get_nodes_in_group("Enemy"):
		if not is_instance_valid(enemy):
			continue
		if enemy.process_mode == Node.PROCESS_MODE_DISABLED:
			continue
		if not enemy.has_method("take_damage"):
			continue
		result.append(enemy)
	return result

func _apply_flight_contact_damage(ratio_damage: float) -> void:
	for enemy in _get_active_enemies():
		if enemy.global_position.distance_to(global_position) > flight_hit_radius:
			continue
		var enemy_id = enemy.get_instance_id()
		if _flight_hit_enemy_ids.has(enemy_id):
			continue
		_flight_hit_enemy_ids[enemy_id] = true
		enemy.take_damage(ratio_damage, global_position)

func _apply_explosion_snapshot_damage(damage: float) -> void:
	var hit_enemy_ids: Dictionary = {}
	for enemy in _get_active_enemies():
		if enemy.global_position.distance_to(global_position) > explosion_radius:
			continue
		var enemy_id = enemy.get_instance_id()
		if hit_enemy_ids.has(enemy_id):
			continue
		hit_enemy_ids[enemy_id] = true
		enemy.take_damage(damage, global_position)

func _apply_linger_damage_tick(ratio_damage: float) -> void:
	for enemy in _get_active_enemies():
		if enemy.global_position.distance_to(global_position) > explosion_radius:
			continue
		enemy.take_damage(ratio_damage, global_position)
