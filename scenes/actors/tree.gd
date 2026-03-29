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

var trunk_widths: Array[float] = [10.0, 40.0, 60.0, 80.0] 

# 🔥 用来记忆你在编辑器里调好的大小
var base_root_scales: Array[Vector2] = []
var base_head_scales: Array[Vector2] = []

func _ready() -> void:
	# 游戏刚启动时，把所有贴图你在编辑器里调的 Scale 存进数组里！
	for i in range(4):
		base_root_scales.append(root_sprites[i].scale)
		base_head_scales.append(head_sprites[i].scale)
		
	# 强制初始化为阶段 0 (幼苗阶段)
	evolve_to_stage(0)

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
