extends Node2D

# ==========================================
# 节点引用
# ==========================================
@onready var vine_line: Line2D = $VineLine
@onready var hitbox: Area2D = $Hitbox
@onready var hitbox_poly: CollisionPolygon2D = $Hitbox/CollisionPolygon2D # 新抓取的多边形节点！

# ==========================================
# 藤条物理与手感参数
# ==========================================
@export var grab_radius: float = 150.0       
@export var max_pull_distance: float = 250.0 
@export var spring_stiffness: float = 1200.0 
@export var spring_damping: float = 15.0     
@export var damage_speed_threshold: float = 500.0 
@export var hitbox_thickness: float = 20.0   # 🔥 藤条的“杀伤厚度”(半径)，可以调大点增加判定范围！

var is_dragging: bool = false
var tip_pos: Vector2 = Vector2.ZERO      
var tip_velocity: Vector2 = Vector2.ZERO 
var curve_segments: int = 15

func _ready() -> void:
	vine_line.begin_cap_mode = Line2D.LINE_CAP_ROUND
	vine_line.end_cap_mode = Line2D.LINE_CAP_ROUND
	hitbox.area_entered.connect(_on_hitbox_area_entered)
	
	# 确保 Hitbox 坐标归零，因为多边形是相对于原点生成的
	hitbox.position = Vector2.ZERO 

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			var tip_global_pos = to_global(tip_pos)
			if tip_global_pos.distance_to(get_global_mouse_position()) <= grab_radius:
				is_dragging = true
				get_viewport().set_input_as_handled()
		else:
			if is_dragging:
				is_dragging = false
				get_viewport().set_input_as_handled()

func _process(delta: float) -> void:
	if is_dragging:
		var mouse_local = get_local_mouse_position()
		if mouse_local.length() > max_pull_distance:
			mouse_local = mouse_local.normalized() * max_pull_distance
		tip_pos = mouse_local
		tip_velocity = Vector2.ZERO 
	else:
		var spring_force = -tip_pos * spring_stiffness
		tip_velocity += spring_force * delta
		tip_velocity -= tip_velocity * spring_damping * delta
		tip_pos += tip_velocity * delta

	# ==========================================
	# 🎨 第一步：计算贝塞尔曲线的所有点
	# ==========================================
	vine_line.clear_points()
	var p0 = Vector2.ZERO 
	var p2 = tip_pos      
	var mid_point = (p0 + p2) / 2.0
	
	var curl_offset = Vector2.ZERO
	if not is_dragging:
		curl_offset = tip_velocity.orthogonal() * 0.06 
	var p1 = mid_point + curl_offset 
	
	# 用一个数组把算好的点全部存起来
	var curve_points: Array[Vector2] = []
	
	for i in range(curve_segments + 1):
		var t = float(i) / float(curve_segments)
		var q0 = p0.lerp(p1, t)
		var q1 = p1.lerp(p2, t)
		var point = q0.lerp(q1, t)
		
		curve_points.append(point)
		vine_line.add_point(point)
		
	# ==========================================
	# 🔥 第二步：根据画出的线，动态包裹一层物理碰撞外壳！
	# ==========================================
	var poly_array = PackedVector2Array()
	var pts_size = curve_points.size()
	
	if pts_size >= 2:
		# 1. 顺着藤条画出“左边”的轮廓边界
		for i in range(pts_size):
			var dir = Vector2.ZERO
			if i < pts_size - 1:
				dir = (curve_points[i+1] - curve_points[i]).normalized()
			else:
				dir = (curve_points[i] - curve_points[i-1]).normalized()
				
			var normal = dir.orthogonal() # 获取垂直于线条的法线方向
			poly_array.append(curve_points[i] + normal * hitbox_thickness)
			
		# 2. 倒着顺藤条画出“右边”的轮廓边界 (合拢成为一个完整的面)
		for i in range(pts_size - 1, -1, -1):
			var dir = Vector2.ZERO
			if i < pts_size - 1:
				dir = (curve_points[i+1] - curve_points[i]).normalized()
			else:
				dir = (curve_points[i] - curve_points[i-1]).normalized()
				
			var normal = dir.orthogonal()
			poly_array.append(curve_points[i] - normal * hitbox_thickness)
			
		# 3. 将捏好的超精密外壳，强行套给我们的碰撞框！
		hitbox_poly.polygon = poly_array

# ==========================================
# 💥 伤害判定：只要碰到整根藤条的任何部位，统统绞杀！
# ==========================================
func _on_hitbox_area_entered(area: Area2D) -> void:
	if area.is_in_group("Enemy"):
		# 判断速度：既然是整根藤条，我们就用藤条尖端的狂飙速度来判断是否有杀伤力
		if not is_dragging and tip_velocity.length() > damage_speed_threshold:
			var enemy_body = area.get_parent()
			if enemy_body and enemy_body.has_method("die"):
				enemy_body.die()
