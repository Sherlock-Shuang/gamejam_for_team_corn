extends Node2D

@onready var root_sprites = [$treeroot/RootSprite1, $treeroot/RootSprite2, $treeroot/RootSprite3, $treeroot/RootSprite4]
@onready var head_sprites = [$treehead/HeadSprite1, $treehead/HeadSprite2, $treehead/HeadSprite3, $treehead/HeadSprite4]
@onready var trunk_line: Line2D = $TrunkLine

# 🛡️ 新增：获取你刚建好的 4 个受伤判定框
@onready var hurtbox_shapes = [
	$HurtBox/CollisionShape2D1,
	$HurtBox/CollisionShape2D2,
	$HurtBox/CollisionShape2D3,
	$HurtBox/CollisionShape2D4
]

var trunk_widths: Array[float] = [10.0, 40.0, 70.0, 90.0] 

# 🌲 编辑器配置项
@export_range(0, 3) var initial_stage: int = 0    # 在编辑器里直接选 0,1,2,3 对应不同大小
@export var is_static_decoration: bool = false    # 如果勾选，由于是背景装饰树，会禁用物理和摄像机

# 🔥 核心状态缓存与计算
var base_root_scales: Array[Vector2] = []
var base_head_scales: Array[Vector2] = []
var is_invincible: bool = false
var invincibility_duration: float = 0.5 # 0.5秒无敌帧

func _ready() -> void:
	# 游戏刚启动时，把所有贴图你在编辑器里调的 Scale 存进数组里！
	for i in range(4):
		base_root_scales.append(root_sprites[i].scale)
		base_head_scales.append(head_sprites[i].scale)
		
	# 根据设置的初始阶段进行演化
	evolve_to_stage(initial_stage)
	
	# 如果是背景装饰树，关闭不必要的交互逻辑
	if is_static_decoration:
		if has_node("Camera2D"): $Camera2D.queue_free()
		if has_node("treehead"):
			$treehead.process_mode = Node.PROCESS_MODE_DISABLED # 禁用拉动逻辑
			$treehead.freeze = true # 锁定物理，不然它会掉下去或到处飘
		if has_node("HurtBox"): $HurtBox.queue_free()

# ==========================================
# 💥 核心：玩家受击逻辑与震动反馈
# ==========================================
func take_damage(amount: float) -> void:
	if is_invincible or GameData.current_hp <= 0:
		return
		
	# 1. 扣血并通知 UI
	GameData.current_hp -= amount
	SignalBus.on_player_hp_changed.emit(GameData.current_hp, GameData.player_base_stats["max_hp"])
	print("[Tree] 受到了 ", amount, " 点伤害！当前血量: ", GameData.current_hp)
	
	# 2. 死亡判定
	if GameData.current_hp <= 0:
		GameData.current_hp = 0
		print("[Tree] 树木枯萎了，游戏结束！")
		SignalBus.on_player_died.emit()
		SignalBus.on_game_over.emit()
		return
		
	# 3. 开启无敌帧
	is_invincible = true
	get_tree().create_timer(invincibility_duration).timeout.connect(func(): is_invincible = false)
	
	# 4. 视觉表现：闪红与短暂震动
	_play_hurt_juice()

func _play_hurt_juice() -> void:
	# 让当前显示的树冠和树根变红
	for sprite in root_sprites + head_sprites:
		if sprite.visible:
			sprite.modulate = Color(1.0, 0.2, 0.2, 1.0)
			var reset_tween = create_tween()
			reset_tween.tween_property(sprite, "modulate", Color.WHITE, 0.3)
	
	# 镜头短暂震动 (Camera Shake)
	if has_node("Camera2D"):
		var cam = $Camera2D
		var original_offset = cam.offset
		var shake_tween = create_tween()
		# 疯狂抖动几次
		for i in range(4):
			var random_offset = Vector2(randf_range(-15, 15), randf_range(-15, 15))
			shake_tween.tween_property(cam, "offset", original_offset + random_offset, 0.05)
		# 最后归位
		shake_tween.tween_property(cam, "offset", original_offset, 0.05)

func apply_trunk_width_multiplier(mult: float) -> void:
	for i in range(trunk_widths.size()):
		trunk_widths[i] *= mult
	var stage_index = clamp($treehead.current_stage_index, 0, trunk_widths.size() - 1)
	if is_instance_valid(trunk_line):
		trunk_line.width = trunk_widths[stage_index]

func apply_root_scale_multiplier(mult: float) -> void:
	for i in range(base_root_scales.size()):
		base_root_scales[i].x *= mult
		root_sprites[i].scale = base_root_scales[i]

func apply_canopy_scale_multiplier(mult: float) -> void:
	for i in range(base_head_scales.size()):
		base_head_scales[i] *= mult
		head_sprites[i].scale = base_head_scales[i]

func evolve_to_stage(stage_index: int) -> void:
	if stage_index < 0 or stage_index > 3:
		return
		
	for i in range(4):
		var is_current = (i == stage_index)
		# 1. 切换视觉贴图
		root_sprites[i].visible = is_current
		head_sprites[i].visible = is_current
		
		# 2. 🛡️ 切换物理判定框 (Godot 核心安全写法)
		# 使用 set_deferred 确保在物理计算的空闲帧关闭/开启碰撞，绝不报错！
		# 注意：disabled 为 true 表示关闭碰撞，所以我们传入 !is_current
		hurtbox_shapes[i].set_deferred("disabled", !is_current)
		
	if is_instance_valid(trunk_line):
		trunk_line.width = trunk_widths[stage_index]
	
	$treehead.current_stage_index = stage_index
	
	# ==========================================
	# 修复后的 Q 弹动画：充满生命力的 Juice 表现
	# ==========================================
	var tween = create_tween().set_parallel(true)
	
	# 获取你调好的目标大小
	var target_head_scale = base_head_scales[stage_index]
	var target_root_scale = base_root_scales[stage_index]
	
	# 从目标大小的 50% 开始弹起
	head_sprites[stage_index].scale = target_head_scale * 0.5
	root_sprites[stage_index].scale = target_root_scale * 0.5
	
	# 弹回到你设定的目标大小
	tween.tween_property(head_sprites[stage_index], "scale", target_head_scale, 0.5).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(root_sprites[stage_index], "scale", target_root_scale, 0.5).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)

	print("🌟 大脑发布指令：全树已进化至形态 ", stage_index + 1)
