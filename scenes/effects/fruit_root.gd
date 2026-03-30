extends Node2D

# ==========================================
# 战斗与特效配置
# ==========================================
var explosion_radius: float = 50.0 

# 🔥 视觉调参区 (在右侧检查器可直接调整)
@export var explosion_duration: float = 0.15  # 爆炸速度：越小炸得越快、越干脆
@export var texture_base_radius: float = 50.0 # 贴图原半径：如果美术画的爆炸图是 100x100，这里填 50
@export var visual_radius_ratio: float = 0.72

# 获取节点
@onready var anim_sprite: AnimatedSprite2D = $AnimatedSprite2D # 播放预警的两帧
@onready var explosion_sprite: Sprite2D = $explosion           # 用于放大消失的爆炸图
@onready var explosion_area: Area2D = $explosion_area
@onready var collision_shape: CollisionShape2D = $explosion_area/CollisionShape2D

# 音乐因素
@export var 爆炸_sfx: AudioStream

func _ready():
	# 初始状态配置
	collision_shape.set_deferred("disabled", true)
	anim_sprite.show() # 显示预警果实
	explosion_sprite.hide() # 隐藏爆炸特效
	explosion_area.monitoring = true
	explosion_area.monitorable = true
	explosion_area.collision_layer = 4
	explosion_area.collision_mask = 2

# 发射接口：由大树的技能控制器调用
func launch(start_pos: Vector2, target_pos: Vector2, radius: float, damage: float) -> void:
	collision_shape.set_deferred("disabled", true)
	anim_sprite.show()
	explosion_sprite.hide()
	global_position = start_pos
	explosion_radius = radius
	collision_shape.scale = Vector2.ONE
	
	# 🛡️【Game Jam 避坑神技】：
	# Godot 中相同的节点资源是默认共享的。如果不同时存在多个爆炸果实，
	# 强行改 radius 会导致所有果实的范围一起突变！新建一个 Shape 彻底隔离！
	var new_shape = CircleShape2D.new()
	new_shape.radius = radius
	collision_shape.shape = new_shape 
	
	var duration = 0.5 # 飞行时间
	
	var tween = create_tween().set_parallel(true)
	
	# 1. 直线飞向目标点
	tween.tween_property(self, "global_position", target_pos, duration)
	
	# 2. 视觉欺骗：往上弹再落下
	var jump_tween = create_tween()
	jump_tween.tween_property(anim_sprite, "position:y", -60.0, duration / 2.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	jump_tween.tween_property(anim_sprite, "position:y", 0.0, duration / 2.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	
	# 3. 飞行结束后，不要立刻炸，进入“引爆预警”阶段！
	tween.chain().tween_callback(func(): _trigger_fuse(damage))

func _trigger_fuse(damage: float) -> void:
	# 播放那 2 帧闪烁动画
	anim_sprite.play("warning")
	
	# 🌟 神级语法：挂起代码，死等动画播放完毕！
	await anim_sprite.animation_finished
	
	# 动画播完，正式引爆！
	_explode(damage)

func _explode(damage: float) -> void:
	# ==========================================
	# 💥 状态切换：隐藏果实，亮出爆炸图
	# ==========================================
	anim_sprite.hide()
	explosion_sprite.show()
	
	# ==========================================
	# ⚔️ 伤害判定
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
	# 🎨 特效表现 (Juice)：动态适配物理判定范围！
	# ==========================================
	# 核心算法：让爆炸图放大到刚刚好覆盖真实的杀伤半径
	var final_scale_size = (explosion_radius / texture_base_radius) * clampf(visual_radius_ratio, 0.1, 2.0)
	
	explosion_sprite.scale = Vector2(0.08, 0.08)
	explosion_sprite.modulate.a = 1.0 
	
	var tween = create_tween().set_parallel(true)
	# 瞬间炸开到动态计算出的大小 (配合 Ease_Out 冲击力极强)
	tween.tween_property(explosion_sprite, "scale", Vector2(final_scale_size, final_scale_size), explosion_duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	# 颜色迅速变透明
	tween.tween_property(explosion_sprite, "modulate:a", 0.0, explosion_duration)
	
	# 👇 【替换在这里】调用全局 AudioManager 播放爆炸声！
	# 参数说明：(音频文件, 音量微调, 开启微小随机音高增强打击感, 最多同屏限制 3 个防止爆音)
	if 爆炸_sfx:
		AudioManager.play_sfx(爆炸_sfx, 10, true, 3)
	
	# 尘归尘土归土，特效放完立刻销毁进入对象池
	tween.chain().tween_callback(PoolManager.return_effect.bind(self, "exploding_fruit"))
