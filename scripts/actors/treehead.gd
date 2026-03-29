extends RigidBody2D

# ==========================================
# 基础配置 (路径已为你完美匹配)
# ==========================================
@onready var trunk_line: Line2D = $"../TrunkLine"
@onready var crown_target: Marker2D = $CrownTarget

# 【重要】假设 hitbox 下面的多边形叫 Shape1 到 Shape4，如果名字不对请修改这里！
@onready var hit_shapes = [$hitbox/Shape1, $hitbox/Shape2, $hitbox/Shape3, $hitbox/Shape4]

@export var tree_root: Node2D # <--- 【注意】在检查器里，把 treeroot 节点拖给它！
@export var grab_radius: float = 200
@export var max_drag_angle_deg: float = 60.0 

# ==========================================
# 【手感参数】保留了你的高爆发设定
# ==========================================
@export var base_pull_speed: float = 20.0     
@export var edge_resistance: float = 0.95     
@export var angular_stiffness: float = 990000.0 
@export var angular_damping_whip: float = 9000.0    
@export var angular_damping_settle: float = 30000.0 
@export var whip_recover_time: float = 0.3        
@export var whip_overshoot_ratio: float = 1.2     

# ==========================================
# 【战斗参数】伤害判定阈值
# ==========================================
@export var damage_velocity_threshold: float = 3.0   # 角速度超过 8 才有杀伤力
@export var damage_multiplier: float = 1.0           # 伤害倍率

var is_dragging: bool = false
var time_since_release: float = 999.0 
var fake_target_angle: float = 0.0 
var curve_segments: int = 15 

# 追踪当前的阶段 (0 对应 Shape1, 3 对应 Shape4)
var current_stage_index: int = 0 

func _ready() -> void:
	can_sleep = false 
	_set_hitbox_active(false)
	print("[treehead] 物理打手已就绪！")
	
func _process(delta: float) -> void:
	if not is_instance_valid(trunk_line) or not is_instance_valid(tree_root) or not is_instance_valid(crown_target):
		return
		
	trunk_line.clear_points()
	
	# ==========================================
	# 🔥 核心修改：反转画线方向，解决贴图颠倒！
	# ==========================================
	# 1. 交换起点和终点：从【树冠】开始画，画到【树根】结束
	var p0 = crown_target.global_position  # 起点变成树冠
	var p2 = tree_root.global_position     # 终点变成树根
	
	var dist = p0.distance_to(p2)
	
	# 2. 寻找“控制点 (p1)”：
	# 【极其重要】：因为现在树根变成了 p2，所以控制点必须基于 p2 向上偏移！
	var p1 = p2 + Vector2.UP * (dist * 0.6) 
	
	# 3. 坐标系转换
	p0 = trunk_line.to_local(p0)
	p1 = trunk_line.to_local(p1)
	p2 = trunk_line.to_local(p2)
	
	# 4. 循环生成曲线上的点
	for i in range(curve_segments + 1):
		var t = float(i) / float(curve_segments) 
		var q0 = p0.lerp(p1, t)
		var q1 = p1.lerp(p2, t)
		var curve_point = q0.lerp(q1, t)
		trunk_line.add_point(curve_point)
		
func _input(event: InputEvent) -> void:
	# 测试后门：仅在无尽模式可以这样切换，非无尽模式下根据关卡自动固定
	if event is InputEventKey and event.pressed and GameData.is_endless_mode:
		if event.keycode == KEY_1: evolve_test(0)
		elif event.keycode == KEY_2: evolve_test(1)
		elif event.keycode == KEY_3: evolve_test(2)
		elif event.keycode == KEY_4: evolve_test(3)
	
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		var dist = global_position.distance_to(get_global_mouse_position())
		if event.pressed:
			if dist <= grab_radius:
				is_dragging = true
				_set_hitbox_active(false) # 拖拽时收起刀刃
				get_viewport().set_input_as_handled()
		else:
			if is_dragging:
				is_dragging = false
				var current_pull_angle = wrapf(global_transform.get_rotation(), -PI, PI)
				fake_target_angle = -current_pull_angle * whip_overshoot_ratio
				time_since_release = 0.0 
				
				_set_hitbox_active(true) # 💥 松手瞬间，亮出刀刃
				
				get_viewport().set_input_as_handled()

func _integrate_forces(state: PhysicsDirectBodyState2D) -> void:
	if not tree_root: return

	var anchor_pos = tree_root.global_position

	if is_dragging:
		var mouse_pos = get_global_mouse_position()
		var delta_pos = mouse_pos - anchor_pos
		var current_angle = state.transform.get_rotation()
		var max_rad = deg_to_rad(max_drag_angle_deg)
		
		if delta_pos.length() > 0.001:
			var raw_target = delta_pos.angle() + PI / 2.0
			raw_target = wrapf(raw_target, -PI, PI)
			var clamped_target = clamp(raw_target, -max_rad, max_rad)
			
			var bend_ratio = abs(current_angle) / max_rad
			var current_speed = base_pull_speed * (1.0 - (bend_ratio * edge_resistance))
			var next_angle = lerp_angle(current_angle, clamped_target, current_speed * state.step)
			
			state.transform = Transform2D(next_angle, anchor_pos)
			state.linear_velocity = Vector2.ZERO
			state.angular_velocity = 0.0

	else:
		# --- 状态 B：松手回弹 ---
		time_since_release += state.step 
		
		var current_angle = state.transform.get_rotation()
		state.transform = Transform2D(current_angle, anchor_pos)
		state.linear_velocity = Vector2.ZERO

		# 计算当前角度离原点 (0度) 有多远
		var angle_to_zero = wrapf(current_angle, -PI, PI)
		
		# ==========================================
		# 🛑 终极静止锁：放宽判定条件，直接“拔电源”！
		# ==========================================
		# 当时间过了，角度小于 0.1 弧度(约5度)，转速小于 5 时：
		if time_since_release >= whip_recover_time and abs(angle_to_zero) < 0.1 and abs(state.angular_velocity) < 5.0:
			state.transform = Transform2D(0.0, anchor_pos) # 强制完全立正
			state.angular_velocity = 0.0                   # 强制引擎彻底熄火
			_set_hitbox_active(false)                      # 收起刀刃
			return # <--- 【核心魔法】直接 return 退出！绝对不允许它执行下面的物理运算！

		# ==========================================
		# 如果还没停稳，继续计算弹力...
		# ==========================================
		var progress = clamp(time_since_release / whip_recover_time, 0.0, 1.0)
		var ease_progress = progress * (2.0 - progress) 
		var current_dynamic_target = lerp(fake_target_angle, 0.0, ease_progress)
		var angle_diff = wrapf(current_angle - current_dynamic_target, -PI, PI) 
		
		var dynamic_angular_damping = lerp(angular_damping_whip, angular_damping_settle, progress)
		var torque = -angular_stiffness * angle_diff - dynamic_angular_damping * state.angular_velocity
		state.apply_torque(torque)
		
		# 🛡️ 强制安全锁
		state.angular_velocity = clamp(state.angular_velocity, -100.0, 100.0)
		
		if progress >= 1.0 and abs(angle_diff) < 0.05 and abs(state.angular_velocity) < 2.0:
			state.transform = Transform2D(0.0, anchor_pos) 
			state.angular_velocity = 0.0                   
			_set_hitbox_active(false)                      

func _set_hitbox_active(is_active: bool) -> void:
	for i in range(hit_shapes.size()):
		if i == current_stage_index:
			hit_shapes[i].set_deferred("disabled", not is_active)
		else:
			hit_shapes[i].set_deferred("disabled", true) 

func evolve_test(stage: int) -> void:
	current_stage_index = stage
	var controller = $".."
	if controller.has_method("evolve_to_stage"):
		controller.evolve_to_stage(stage)

# ==========================================
# 状态 C：割草打击判定 (Area 打 Area)
# ==========================================
func _on_hitbox_area_entered(area: Area2D) -> void:
	if area.is_in_group("Enemy"):
		var current_whip_speed = abs(angular_velocity)
		if current_whip_speed > damage_velocity_threshold:
			var enemy_body = area.get_parent()
			
			# 1. 检查是否有 take_damage 方法（走正规扣血流程，而不是直接秒杀）
			if enemy_body and enemy_body.has_method("take_damage"):
				# 2. 根据挥鞭速度计算动态伤害
				var damage = (current_whip_speed - damage_velocity_threshold) * damage_multiplier
				
				# 3. 【核心修复】传入伤害值，并且把树干的 global_position 传过去！
				enemy_body.take_damage(damage, global_position)

				# 4. 触发果汁感 (Juice) —— 打击停顿
				trigger_hit_stop()

# ==========================================
# 表现层：打击顿挫感 (Hit Stop)
# ==========================================
func trigger_hit_stop() -> void:
	# 瞬间将全局时间缩放降至极低，产生强烈的“卡肉感”
	Engine.time_scale = 0.05
	
	# 创建一个计时器，注意必须乘以当前的 time_scale，否则现实中的 0.1 秒会在游戏里变成 2 秒
	await get_tree().create_timer(0.1 * Engine.time_scale).timeout 
	
	# 恢复正常时间
	Engine.time_scale = 1.0
