extends RigidBody2D

# ==========================================
# 基础配置
# ==========================================
@onready var trunk_line: Line2D = $"../TrunkLine"
@onready var crown_target: Marker2D = $CrownTarget



@export var tree_root: Node2D
@export var grab_radius: float = 200
@export var max_drag_angle_deg: float = 60.0 


# ==========================================
# 【手感参数 1】拉扯张力与阻力感 (Tension)
# ==========================================
@export var base_pull_speed: float = 20.0     # 基础拉拽速度
@export var edge_resistance: float = 0.95     # 边缘张力阻力 (拉到极限时越来越难拉)

# ==========================================
# 【手感参数 2】假目标与过冲鞭打 (Overshoot)
# ==========================================
@export var angular_stiffness: float = 990000.0 
@export var angular_damping_whip: float = 9000.0    # 松手瞬间极低阻尼 (让它狂甩)
@export var angular_damping_settle: float = 30000.0  # 甩完高阻尼 (让它稳住)
@export var whip_recover_time: float = 0.3        
@export var whip_overshoot_ratio: float = 1.2     

# ==========================================
# 【战斗参数】伤害判定阈值
# ==========================================
@export var damage_velocity_threshold: float = 3.0   # 角速度超过 8 才有杀伤力

var is_dragging: bool = false
var time_since_release: float = 999.0 
var fake_target_angle: float = 0.0 

func _ready() -> void:
	can_sleep = false 
	print("[TreeHead] Ready! Ultimate Whip Physics & Combat Engaged!")
	
var curve_segments: int = 15 

func _process(delta: float) -> void:
	if not is_instance_valid(trunk_line) or not is_instance_valid(tree_root) or not is_instance_valid(crown_target):
		return
		
	trunk_line.clear_points()
	
	# ==========================================
	# 🔥 核心魔法：二次贝塞尔曲线 (Quadratic Bezier)
	# ==========================================
	# 1. 获取全局的 起点(树根) 和 终点(树冠)
	var p0 = tree_root.global_position
	var p2 = crown_target.global_position
	
	# 2. 寻找“控制点 (p1)”：这就是决定树干往哪边弯曲的灵魂！
	# 为了让树根看起来是死死扎在土里（笔直向上），我们把控制点放在树根的正上方。
	var dist = p0.distance_to(p2)
	# Vector2.UP (0, -1) 代表正上方。0.6 是弯曲系数，你可以微调这个数字改变弯曲的弧度。
	var p1 = p0 + Vector2.UP * (dist * 0.6) 
	
	# 3. 坐标系转换 (转为 Line2D 的局部坐标)
	p0 = trunk_line.to_local(p0)
	p1 = trunk_line.to_local(p1)
	p2 = trunk_line.to_local(p2)
	
	# 4. 循环生成曲线上的点
	for i in range(curve_segments + 1):
		var t = float(i) / float(curve_segments) # t 的范围是 0.0 到 1.0
		
		# 贝塞尔曲线的数学插值公式
		var q0 = p0.lerp(p1, t)
		var q1 = p1.lerp(p2, t)
		var curve_point = q0.lerp(q1, t)
		
		# 将算好的点塞进 Line2D
		trunk_line.add_point(curve_point)
		
func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		var dist = global_position.distance_to(get_global_mouse_position())
		if event.pressed:
			if dist <= grab_radius:
				is_dragging = true
				get_viewport().set_input_as_handled()
		else:
			if is_dragging:
				is_dragging = false
				# 计算假目标，准备鞭打！
				var current_pull_angle = wrapf(global_transform.get_rotation(), -PI, PI)
				fake_target_angle = -current_pull_angle * whip_overshoot_ratio
				time_since_release = 0.0 
				get_viewport().set_input_as_handled()

func _integrate_forces(state: PhysicsDirectBodyState2D) -> void:
	if not tree_root:
		return

	var anchor_pos = tree_root.global_position

	if is_dragging:
		# --- 状态 A：玩家拖拽中 (带动态阻力的粘滞跟随) ---
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
		# --- 状态 B：松手回弹 (过冲瞄准 + 两段式阻尼) ---
		time_since_release += state.step 
		
		var current_angle = state.transform.get_rotation()
		state.transform = Transform2D(current_angle, anchor_pos)
		state.linear_velocity = Vector2.ZERO

		var progress = clamp(time_since_release / whip_recover_time, 0.0, 1.0)
		var ease_progress = progress * (2.0 - progress) 
		var current_dynamic_target = lerp(fake_target_angle, 0.0, ease_progress)
		var angle_diff = wrapf(current_angle - current_dynamic_target, -PI, PI) 
		
		var dynamic_angular_damping = lerp(angular_damping_whip, angular_damping_settle, progress)
		var torque = -angular_stiffness * angle_diff - dynamic_angular_damping * state.angular_velocity
		state.apply_torque(torque)
		
					 # 强制熄火

# ==========================================
# 状态 C：割草打击判定 (Area 打 Area)
# ==========================================
func _on_hitbox_area_entered(area: Area2D) -> void:
	# 第一步：核对身份。用分组（Group）判断撞到的是不是敌人
	if area.is_in_group("Enemy"):
		
		# 第二步：测速。获取当前树干狂飙的“角速度”绝对值
		var current_whip_speed = abs(angular_velocity)
		
		# 如果速度够快，说明是在剧烈弹射中！
		if current_whip_speed > damage_velocity_threshold:
			# 修正：area是敌人的hurtbox(Area2D)，需要获取其父节点(敌人本体)
			var enemy_body = area.get_parent()
			if enemy_body and enemy_body.has_method("die"):
				enemy_body.die()

				# 💡 果汁感 (Juice) 预留口：
				# 这里就是你之后写 Engine.time_scale = 0.05 制造打击顿挫感的地方！
				# print("Hit! 瞬间抽击速度: ", current_whip_speed)
