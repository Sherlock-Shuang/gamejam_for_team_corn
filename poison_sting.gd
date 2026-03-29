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

var velocity: Vector2 = Vector2.ZERO
var damage: float = 10.0
var current_pierce: int = 0

@onready var sprite: Sprite2D = $Sprite2D
@onready var collision_shape: CollisionShape2D = $CollisionShape2D

func _ready():
	monitoring = true
	collision_layer = 4
	collision_mask = 2
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
# 发射接口：由技能管理器调用
# 注意：这里传的是 direction (方向向量)，而不是 target_pos (目标点)
# ==========================================
func launch(start_pos: Vector2, direction: Vector2, dmg: float, speed_mult: float = 1.0, config: Dictionary = {}) -> void:
	global_position = start_pos
	damage = dmg
	current_pierce = 0
	sprite.modulate.a = 1.0
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
	# 直线飞行的核心逻辑：每帧移动
	global_position += velocity * delta

# ==========================================
# 信号连接 1：击中敌人
# (请在编辑器里把 Area2D 的 area_entered 信号连到这个函数)
# ==========================================
func _on_area_entered(area: Area2D) -> void:
	if area.is_in_group("Enemy"):
		var enemy = area.get_parent()
		if enemy and enemy.has_method("take_damage"):
			enemy.take_damage(damage, global_position)
			
			# 穿透计算逻辑
			current_pierce += 1
			if current_pierce >= pierce_count:
				# 🎵 这里可以加个“噗嗤”的刺入音效
				_destroy_sting()

# ==========================================
# 信号连接 2：飞出屏幕自动销毁
# (请把 VisibleOnScreenNotifier2D 的 screen_exited 信号连到这里)
# ==========================================
func _on_visible_on_screen_notifier_2d_screen_exited() -> void:
	queue_free()

# 销毁表现
func _destroy_sting() -> void:
	# 停止伤害检测和移动
	set_deferred("monitoring", false)
	set_physics_process(false)
	
	# 🎨 Juice：击中后稍微变大变透明，产生扎进去的质感
	var tween = create_tween().set_parallel(true)
	tween.tween_property(sprite, "scale", destroy_scale, 0.1)
	tween.tween_property(sprite, "modulate:a", 0.0, 0.1)
	tween.chain().tween_callback(queue_free)
