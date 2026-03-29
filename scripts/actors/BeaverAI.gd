# BeaverAI.gd (河狸专属 AI)
extends EnemyBase

# ==========================================
# 河狸专属战斗参数
# ==========================================
@export var attack_range: float = 90.0      # 啃咬触发距离（根据你的树根大小微调）
@export var attack_interval: float = 0.8    # 啃咬频率（每 0.8 秒咬一口）

var attack_timer: float = 0.0

# 获取我们在场景里搭好的攻击框（HitBox）的碰撞体
@onready var hitbox_shape: CollisionShape2D = $HitBox/CollisionShape2D

func _ready() -> void:
	super._ready() # 必须调用老祖宗的初始化！
	
	# 游戏开始时，河狸还没碰到树，先把它的“牙齿”（攻击框）收起来
	if hitbox_shape:
		hitbox_shape.set_deferred("disabled", true)

# 重写老祖宗留下的空壳函数：专属逻辑全写在这里！
func _custom_behavior(delta: float) -> void:
	if not is_instance_valid(target_tree): return
	
	# 计算到大树中心的距离
	var distance_to_tree = global_position.distance_to(target_tree.global_position)
	
	# ==========================================
	# 状态机：攻击状态 VS 移动状态
	# ==========================================
	if distance_to_tree <= attack_range:
		# 1. 靠近大树，停下脚步！
		
		# 2. 播放 4 帧的啃咬动画
		if anim.animation != "attack":
			anim.play("attack")
			
		# 3. 攻击计时器流逝
		attack_timer -= delta
		if attack_timer <= 0:
			perform_attack()
			attack_timer = attack_interval # 重置计时器，准备下一口
			
	else:
		# 1. 离树还有距离，继续往前顶！
		
		# 2. 播放 2 帧的走路动画
		if anim.animation != "walk":
			anim.play("walk")
			
		# 3. 只要没在咬人，就确保计时器是满的，这样一碰到树就能【瞬间】咬出第一口！
		attack_timer = 0.0
		if hitbox_shape and not hitbox_shape.disabled:
			hitbox_shape.set_deferred("disabled", true)

# ==========================================
# 核心伤害触发 (Juice 打磨点)
# ==========================================
func perform_attack() -> void:
	# Game Jam 暴力解法：瞬间开启 HitBox，形成一次干脆的“打击”判定
	if hitbox_shape:
		hitbox_shape.set_deferred("disabled", false)
		
		# 0.1 秒后立刻关掉它。这样大树的 HurtBox 只会收到一次 area_entered 信号，而不是持续扣血！
		get_tree().create_timer(0.1, false).timeout.connect(func():
			if is_instance_valid(hitbox_shape):
				hitbox_shape.set_deferred("disabled", true)
		)
