extends RigidBody2D

# ==========================================
# 基础配置
# ==========================================
@export var tree_root: Node2D
@export var max_drag_dist: float = 150.0
@export var grab_radius: float = 120.0

# ==========================================
# 【神级手感参数】彻底抛弃物理关节，纯手写弹力！
# ==========================================
@export var spring_stiffness: float = 1500.0 # 弹簧刚度：越高，松手瞬间爆发的速度越狂暴！(推荐 1000~3000)
@export var spring_damping: float = 15.0     # 弹簧阻尼：决定晃动几下停住。太低会鬼畜，太高像烂泥。(推荐 10~30)

var is_dragging: bool = false

func _ready() -> void:
	# 强制禁止休眠，防止刚体“睡死”导致假死bug
	can_sleep = false 
	print("[TreeHead] Ready! Custom Spring Physics Engaged!")
	if not get_node_or_null("Sprite2D"):
		print("[TreeHead] WARNING: Sprite2D not found!")

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		var dist = global_position.distance_to(get_global_mouse_position())
		
		if event.pressed:
			if dist <= grab_radius:
				is_dragging = true
				print("[TreeHead] ✓ Drag START - 拉满弓弦！")
				get_viewport().set_input_as_handled()
		else:
			if is_dragging:
				is_dragging = false
				print("[TreeHead] ✓ Drag END - 狂暴发射！")
				get_viewport().set_input_as_handled()
				
				# 💡 Juice 建议：在这里触发音效和微小的屏幕后坐力震动！

func _integrate_forces(state: PhysicsDirectBodyState2D) -> void:
	if not tree_root:
		return

	if is_dragging:
		# --------------------------------------------------
		# 状态 A：玩家拖拽中 (绝对控制)
		# --------------------------------------------------
		var mouse_pos = get_global_mouse_position()
		var anchor_pos = tree_root.global_position

		var delta_pos = mouse_pos - anchor_pos
		var target_pos = anchor_pos
		
		if delta_pos.length() > 0.001:
			var clamped_delta = delta_pos.limit_length(max_drag_dist)
			target_pos = anchor_pos + clamped_delta
		
		# 直接接管位置，不参与物理碰撞乱飞
		state.transform = Transform2D(state.transform.get_rotation(), target_pos)
		state.linear_velocity = Vector2.ZERO
		state.angular_velocity = 0.0

	else:
		# --------------------------------------------------
		# 状态 B：松手回弹 (纯数学计算的完美弹簧)
		# --------------------------------------------------
		# 1. 计算位移向量 (偏离树根有多远)
		var displacement = global_position - tree_root.global_position
		
		# 2. 计算弹簧拉力：利用胡克定律公式
		var spring_force = -spring_stiffness * displacement
		
		# 3. 计算阻尼力：防止树干变成永动机一直鬼畜
		var damping_force = -spring_damping * state.linear_velocity
		
		# 4. 将合力狠狠地砸进刚体里！
		state.apply_central_force(spring_force + damping_force)
