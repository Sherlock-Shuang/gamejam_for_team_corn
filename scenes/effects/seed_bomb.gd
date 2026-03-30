extends Node2D

# ==========================================
# 战斗与表现参数
# ==========================================
@export var base_damage: float = 5.0      # 每次跳字的伤害
@export var damage_interval: float = 0.5  # 多久造成一次伤害？(0.5秒代表每秒打2次)
@export var lifetime: float = 10.0        # 持续 10 秒后枯萎
@export var fly_scale: float = 0.1
@export var grown_scale: float = 0.2

# ==========================================
# 节点获取 (如果你的名字不同，请修改这里)
# ==========================================
@onready var anim: AnimatedSprite2D = _resolve_anim_sprite()
@onready var hitbox_area: Area2D = _resolve_hitbox_area()
@onready var collision_shape: CollisionShape2D = _resolve_collision_shape()
# ==========================================
# 音乐参数
# ==========================================
@export var 种植_sfx: AudioStream

var damage_timer: Timer
var life_timer: Timer
var active_radius: float = 150.0
var launch_config: Dictionary = {}

func _ready():
	if anim == null or hitbox_area == null or collision_shape == null:
		push_warning("[SeedBomb] 节点路径不完整，无法启动种子炸弹。")
		return
	# 初始状态：收起刀刃，等待落地
	collision_shape.set_deferred("disabled", true)
	hitbox_area.monitoring = true
	hitbox_area.monitorable = true
	hitbox_area.collision_layer = 4
	hitbox_area.collision_mask = 2

# 发射接口：由大树的技能控制器调用
func launch(start_pos: Vector2, target_pos: Vector2, damage: float, radius: float, tick_interval: float, life_time: float, config: Dictionary = {}) -> void:
	collision_shape.set_deferred("disabled", true)
	if is_instance_valid(damage_timer):
		damage_timer.stop()
	if is_instance_valid(life_timer):
		life_timer.stop()
		
	global_position = start_pos
	base_damage = damage
	damage_interval = tick_interval
	lifetime = life_time
	launch_config = config.duplicate(true)
	if config.has("fly_scale"):
		fly_scale = float(config["fly_scale"])
	if config.has("grown_scale"):
		grown_scale = float(config["grown_scale"])
	active_radius = radius
	var new_shape = CircleShape2D.new()
	new_shape.radius = radius
	collision_shape.shape = new_shape
	
	anim.play("fly")
	# 🌟【表现细节】：在天上飞的时候，体积缩小到 0.4 倍
	anim.scale = Vector2(fly_scale, fly_scale) 
	
	var duration = 0.5 # 飞行时间
	var tween = create_tween().set_parallel(true)
	
	# 1. 根节点直线飞向目标点
	tween.tween_property(self, "global_position", target_pos, duration)
	
	# 2. 视觉抛物线：控制图片上下跳跃
	var jump_tween = create_tween()
	jump_tween.tween_property(anim, "position:y", -80.0, duration / 2.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	jump_tween.tween_property(anim, "position:y", 0.0, duration / 2.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	
	# 3. 飞行结束后，触发落地生根逻辑
	tween.chain().tween_callback(_on_land)

func _on_land() -> void:
	# 播放落地音效
	if 种植_sfx:
		AudioManager.play_sfx(种植_sfx, 15.0, false)  # max_instances 防止爆音
	# 播放破土成长的动画
	anim.play("grow")
	
	# 🌟【表现细节】：伴随成长动画，像弹簧一样“嘭”地膨胀回正常大小
	var grow_tween = create_tween()
	grow_tween.tween_property(anim, "scale", Vector2(grown_scale, grown_scale), maxf(0.08, float(launch_config.get("grow_duration", 0.3)))).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	
	# 死等动画播完
	await anim.animation_finished
	
	# 成长完毕，进入无情割草模式！
	_start_combat()

func _start_combat() -> void:
	# 播放美术画好的自带摇摆的战斗动画
	anim.play("swing")
	
	# 开启判定框
	collision_shape.set_deferred("disabled", false)
	await get_tree().physics_frame
	_deal_continuous_damage()
	
	if not is_instance_valid(damage_timer):
		damage_timer = Timer.new()
		damage_timer.timeout.connect(_deal_continuous_damage)
		add_child(damage_timer)
	damage_timer.wait_time = maxf(0.05, damage_interval)
	damage_timer.start()
	
	if not is_instance_valid(life_timer):
		life_timer = Timer.new()
		life_timer.timeout.connect(_wither)
		add_child(life_timer)
	life_timer.wait_time = maxf(0.1, lifetime)
	life_timer.start()

# 每次 Timer 滴答时触发
func _deal_continuous_damage() -> void:
	for enemy in get_tree().get_nodes_in_group("Enemy"):
		if not is_instance_valid(enemy):
			continue
		if enemy.process_mode == Node.PROCESS_MODE_DISABLED:
			continue
		if not enemy.has_method("take_damage"):
			continue
		if enemy.global_position.distance_to(global_position) <= active_radius:
			enemy.take_damage(base_damage, global_position)

func _resolve_anim_sprite() -> AnimatedSprite2D:
	if has_node("AnimatedSprite2D"):
		return $AnimatedSprite2D
	if has_node("pivot/Area2D/AnimatedSprite2D"):
		return $pivot/Area2D/AnimatedSprite2D
	return null

func _resolve_hitbox_area() -> Area2D:
	if has_node("HitBox"):
		return $HitBox
	if has_node("pivot/Area2D"):
		return $pivot/Area2D
	return null

func _resolve_collision_shape() -> CollisionShape2D:
	if has_node("HitBox/CollisionShape2D"):
		return $HitBox/CollisionShape2D
	if has_node("pivot/Area2D/CollisionShape2D"):
		return $pivot/Area2D/CollisionShape2D
	return null

func _wither() -> void:
	# 停止伤害计算，关掉判定框
	collision_shape.set_deferred("disabled", true)
	if is_instance_valid(damage_timer):
		damage_timer.stop()
	if is_instance_valid(life_timer):
		life_timer.stop()
	
	# 🥀【枯萎表现】：缩回到地下然后销毁
	var tween = create_tween()
	tween.tween_property(anim, "scale", Vector2.ZERO, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tween.tween_callback(PoolManager.return_effect.bind(self, "seed_bomb"))
