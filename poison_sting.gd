extends Area2D

# ==========================================
# 战斗与飞行参数
# ==========================================
@export var default_speed: float = 800.0  # 飞行速度（极快）
@export var pierce_count: int = 1         # 穿透次数（1代表打中1个就消失）
@export var launch_start_scale: Vector2 = Vector2(0.22, 0.26)
@export var launch_end_scale: Vector2 = Vector2(1.15, 0.62)
@export var destroy_scale: Vector2 = Vector2(1.5, 1.5)
@export var hitbox_radius_ratio: float = 0.82
@export var hitbox_length_ratio: float = 0.84

# 🎵 音效资源：在编辑器里把音频拖进这两个属性里
@export var launch_sound: AudioStream
@export var hit_sound: AudioStream

var velocity: Vector2 = Vector2.ZERO
var damage: float = 10.0
var current_pierce: int = 0

@onready var sprite: Sprite2D = $Sprite2D
@onready var collision_shape: CollisionShape2D = $CollisionShape2D

func _ready():
	monitoring = true
	collision_layer = 4
	collision_mask = 2
	
	# 不再需要初始化局部的 AudioStreamPlayer 节点！
	
	if collision_shape and collision_shape.shape is CapsuleShape2D:
		var capsule = (collision_shape.shape as CapsuleShape2D).duplicate() as CapsuleShape2D
		capsule.radius *= clampf(hitbox_radius_ratio, 0.2, 2.0)
		capsule.height *= clampf(hitbox_length_ratio, 0.2, 2.0)
		collision_shape.shape = capsule
	if not area_entered.is_connected(_on_area_entered):
		area_entered.connect(_on_area_entered)
	var notifier = get_node_or_null("VisibleOnScreenNotifier2D")
	if notifier and not notifier.screen_exited.is_connected(_on_visible_on_screen_notifier_2d_screen_exited):
		notifier.screen_exited.connect(_on_visible_on_screen_notifier_2d_screen_exited)

# ==========================================
# 发射接口
# ==========================================
func launch(start_pos: Vector2, direction: Vector2, dmg: float, speed_mult: float = 1.0, config: Dictionary = {}) -> void:
	set_deferred("monitoring", true)
	set_physics_process(true)
	global_position = start_pos
	damage = dmg
	current_pierce = 0
	sprite.modulate.a = 1.0
	
	# 🎵 调用全局管理器播放发射音效
	# 参数：音效资源 | 音量(0.0) | 开启随机音调(true) | 限制同屏最多播放数(比如3)
	if launch_sound:
		AudioManager.play_sfx(launch_sound, 25, true, 3)

	if config.has("launch_end_scale_x") or config.has("launch_end_scale_y"):
		launch_end_scale = Vector2(
			float(config.get("launch_end_scale_x", launch_end_scale.x)),
			float(config.get("launch_end_scale_y", launch_end_scale.y))
		)
	if config.has("launch_start_scale_x") or config.has("launch_start_scale_y"):
		launch_start_scale = Vector2(
			float(config.get("launch_start_scale_x", launch_start_scale.x)),
			float(config.get("launch_start_scale_y", launch_start_scale.y))
		)
	if config.has("pierce_count"):
		pierce_count = maxi(0, int(config.get("pierce_count", pierce_count)))
	var scale_duration = float(config.get("scale_transition_duration", 0.1))
	
	var actual_speed = default_speed * speed_mult
	velocity = direction.normalized() * actual_speed
	rotation = velocity.angle()
	
	sprite.scale = launch_start_scale
	var tween = create_tween()
	tween.tween_property(sprite, "scale", launch_end_scale, maxf(0.03, scale_duration)).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

func _physics_process(delta: float) -> void:
	global_position += velocity * delta

# ==========================================
# 信号连接 1：击中敌人
# ==========================================
func _on_area_entered(area: Area2D) -> void:
	if area.is_in_group("Enemy"):
		var enemy = area.get_parent()
		if enemy and enemy.has_method("take_damage"):
			# 局部慢放：匕首和敌人短暂定格
			_trigger_local_slowmo(enemy)
			
			enemy.take_damage(damage, global_position, 0.0, "thorn_shot")
			
			# 🎵 调用全局管理器播放击中音效
			if hit_sound:
				AudioManager.play_sfx(hit_sound, 20, true, 5)
			
			# 穿透计算逻辑
			current_pierce += 1
			if current_pierce >= pierce_count:
				_destroy_sting()

func _trigger_local_slowmo(enemy: Node) -> void:
	# 防止同一敌人被多发毒刺反复定格导致速度抖动
	if enemy.has_meta("_thorn_frozen") and enemy.get_meta("_thorn_frozen"):
		return
	
	set_physics_process(false)
	if enemy.has_method("set_physics_process"):
		enemy.set_physics_process(false)
	enemy.set_meta("_thorn_frozen", true)
	
	sprite.modulate = Color(5, 5, 5, 1)
	var enemy_anim = enemy.get("anim")
	var original_enemy_mod = Color.WHITE
	var true_original_scale = Vector2.ONE
	
	if is_instance_valid(enemy_anim):
		original_enemy_mod = enemy_anim.modulate
		enemy_anim.modulate = Color(4, 4, 4, 1)
		true_original_scale = enemy.get_meta("original_anim_scale", enemy_anim.scale)
		enemy_anim.scale = true_original_scale * 1.1
	
	var old_scale = sprite.scale
	sprite.scale = old_scale * Vector2(0.7, 1.3)
	
	var freeze_time = 0.10
	get_tree().create_timer(freeze_time, false).timeout.connect(func():
		set_physics_process(true)
		
		if is_instance_valid(enemy):
			if enemy.has_method("set_physics_process"):
				enemy.set_physics_process(true)
			enemy.set_meta("_thorn_frozen", false)
			if is_instance_valid(enemy_anim):
				enemy_anim.modulate = original_enemy_mod
				enemy_anim.scale = true_original_scale
		
		if is_instance_valid(sprite):
			var recover_tween = create_tween().set_parallel(true)
			recover_tween.tween_property(sprite, "modulate", Color(1, 1, 1, 1), 0.1)
			recover_tween.tween_property(sprite, "scale", old_scale, 0.1).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	)

# ==========================================
# 信号连接 2：飞出屏幕自动销毁
# ==========================================
func _on_visible_on_screen_notifier_2d_screen_exited() -> void:
	PoolManager.return_effect(self, "thorn_shot")

# 销毁表现
func _destroy_sting() -> void:
	set_deferred("monitoring", false)
	set_physics_process(false)
	
	# 🎨 这里的逻辑变得清爽了，只需专注于 Juice 动画即可
	var tween = create_tween().set_parallel(true)
	tween.tween_property(sprite, "scale", destroy_scale, 0.1)
	tween.tween_property(sprite, "modulate:a", 0.0, 0.1)
	tween.chain().tween_callback(PoolManager.return_effect.bind(self, "thorn_shot"))
