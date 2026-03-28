extends RigidBody2D

# ==========================================
# 基础配置
# ==========================================
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
@export var angular_stiffness: float = 1600000.0 
@export var angular_damping_whip: float = 14000.0    # 松手瞬间极低阻尼 (让它狂甩)
@export var angular_damping_settle: float = 30000.0  # 甩完高阻尼 (让它稳住)
@export var whip_recover_time: float = 0.3        
@export var whip_overshoot_ratio: float = 1.2     

# ==========================================
# 【战斗参数】伤害判定阈值
# ==========================================
@export var damage_velocity_threshold: float = 8.0   # 角速度超过 8 才有杀伤力

var is_dragging: bool = false
var time_since_release: float = 999.0 
var fake_target_angle: float = 0.0 

func _ready() -> void:
	can_sleep = false 
	print("[TreeHead] Ready! Ultimate Whip Physics & Combat Engaged!")

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

# ==========================================
# 状态 C：割草打击判定 (Area 打 Area)
# ==========================================
func _on_hitbox_area_entered(area: Area2D) -> void:
	# 确保撞到的是敌人的 Hurtbox (记得在检查器里给 Hurtbox 加上 "Enemy" 分组)
	if area.is_in_group("Enemy"):
		var current_whip_speed = abs(angular_velocity)
		
		# 如果抽打速度足够快！
		if current_whip_speed > damage_velocity_threshold:
			# Hurtbox 的爸爸就是 Enemy (CharacterBody2D)，呼叫它去死！
			var enemy_body = area.get_parent() 
			if enemy_body.has_method("die"):
				enemy_body.die()
