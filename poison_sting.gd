extends Area2D

# ==========================================
# 战斗与飞行参数
# ==========================================
@export var default_speed: float = 800.0  # 飞行速度（极快）
@export var pierce_count: int = 1         # 穿透次数（1代表打中1个就消失）

var velocity: Vector2 = Vector2.ZERO
var damage: float = 10.0
var current_pierce: int = 0

@onready var sprite: Sprite2D = $Sprite2D

func _ready():
	# 确保一开始不在屏幕上乱触发
	monitoring = true

# ==========================================
# 发射接口：由技能管理器调用
# 注意：这里传的是 direction (方向向量)，而不是 target_pos (目标点)
# ==========================================
func launch(start_pos: Vector2, direction: Vector2, dmg: float, speed_mult: float = 1.0) -> void:
	global_position = start_pos
	damage = dmg
	
	# 核心：计算速度向量，并让毒刺的针尖永远对准飞行的方向！
	var actual_speed = default_speed * speed_mult
	velocity = direction.normalized() * actual_speed
	rotation = velocity.angle()
	
	# 🎨 Juice 表现：发射时伴随一个轻微的拉长残影效果
	sprite.scale = Vector2(0.3, 0.3)
	var tween = create_tween()
	# X轴拉长（体现速度感），Y轴恢复正常
	tween.tween_property(sprite, "scale", Vector2(1.5, 0.8), 0.1).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

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
	tween.tween_property(sprite, "scale", Vector2(2.0, 2.0), 0.1)
	tween.tween_property(sprite, "modulate:a", 0.0, 0.1)
	tween.chain().tween_callback(queue_free)
