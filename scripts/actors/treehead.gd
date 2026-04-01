extends RigidBody2D

# ==========================================
# 基础配置
# ==========================================
@onready var trunk_line: Line2D = $"../TrunkLine"
@onready var crown_target: Marker2D = $CrownTarget
@onready var hit_shapes = [$hitbox/Shape1, $hitbox/Shape2, $hitbox/Shape3, $hitbox/Shape4]

@onready var head_sprites = [$HeadSprite1, $HeadSprite2, $HeadSprite3, $HeadSprite4]

@export var tree_root: Node2D
@export var grab_radius: float = 200
@export var max_drag_angle_deg: float = 60.0 

# ==========================================
# 形变参数：体积守恒与动态拉伸
# ==========================================
@export var stretch_sensitivity: float = 0.6 
@export var max_stretch_scale: float = 1.5
   
@export var drag_tension_stretch: float = 1.3 
@export var squash_power: float = 0.6 

# 🔥突刺专项参数 (蓄力爆发流)
@export var thrust_charge_dist: float = 250.0 
@export var max_compress_ratio: float = 0.5   
@export var max_thrust_scale: float = 2.5     
@export var thrust_duration: float = 0.3      

var base_crown_pos: Vector2
var base_hitbox_pos: Vector2
var base_hitbox_scale: Vector2
var base_sprite_positions: Array[Vector2] = []
var base_hit_shape_scales: Array[Vector2] = []

# ==========================================
# 手感与战斗参数
# ==========================================
@export var base_pull_speed: float = 20.0     
@export var edge_resistance: float = 0.95     
@export var angular_stiffness: float = 990000.0 
@export var angular_damping_whip: float = 9000.0    
@export var angular_damping_settle: float = 30000.0 
@export var whip_recover_time: float = 0.3        
@export var whip_overshoot_ratio: float = 1.2
@export var damage_velocity_threshold: float = 3.0   
@export var damage_multiplier: float = 1.0           
@export var hit_knockback: float = 120.0           

@export_group("Charge Damage Tiers")
@export var tier_damage_perfect: float = 40
@export var tier_damage_high: float = 15.0
@export var tier_damage_mid: float = 9.0
@export var tier_damage_low: float = 5.0

# ==========================================
# 音乐参数
# ==========================================
@onready var charge_audio: AudioStreamPlayer = $ChargeAudio
@export var 蓄力_sfx : AudioStream
@export var 击中_sfx : AudioStream
@export var 释放破空_sfx : AudioStream

var is_dragging: bool = false
var time_since_release: float = 999.0 
var fake_target_angle: float = 0.0 
var curve_segments: int = 15 
var current_stage_index: int = 0 

# ==========================================
# 混合控制参数 (键鼠/手柄)
# ==========================================
var is_mouse_dragging: bool = false
var is_controller_dragging: bool = false
var current_drag_delta: Vector2 = Vector2.ZERO 

# ==========================================
# 🔥【新增】双形态状态机与伤害锁
# ==========================================
var is_thrust_charging: bool = false   
var is_thrust_releasing: bool = false  
var stored_thrust_power: float = 0.0   

# 记录每次松手时的“锁定伤害”，保证打击全程伤害一致
var locked_attack_damage: float = 0.0 

func _ready() -> void:
	can_sleep = false 
	_set_hitbox_active(false)
	
	base_crown_pos = crown_target.position
	if has_node("hitbox"):
		base_hitbox_pos = $hitbox.position
		base_hitbox_scale = $hitbox.scale
		
	for sprite in head_sprites:
		if sprite:
			base_sprite_positions.append(sprite.position)
	for shape in hit_shapes:
		if shape:
			base_hit_shape_scales.append(shape.scale)
		
	print("[treehead] 终极战斗形态：段位蓄力锁定伤害已实装！")

func apply_hit_shape_scale_multiplier(mult: float) -> void:
	for i in range(hit_shapes.size()):
		if i < base_hit_shape_scales.size() and hit_shapes[i]:
			base_hit_shape_scales[i] *= mult
			hit_shapes[i].scale = base_hit_shape_scales[i]
	
func _process(delta: float) -> void:
	if not is_instance_valid(trunk_line) or not is_instance_valid(tree_root) or not is_instance_valid(crown_target):
		return
		
	_handle_virtual_inputs()
		
	var current_stretch = 1.0
	
	if is_dragging:
		var delta_pos = current_drag_delta
		
		# 扇区判定：如果往下拖动
		if delta_pos.y > 0 and delta_pos.y > abs(delta_pos.x):
			is_thrust_charging = true
			is_thrust_releasing = false
			
			# 蓄力压缩计算
			stored_thrust_power = clamp(delta_pos.y / thrust_charge_dist, 0.0, 1.0)
			current_stretch = 1.0 - (stored_thrust_power * max_compress_ratio)
			
			_set_hitbox_active(false)
		else:
			is_thrust_charging = false
			current_stretch = drag_tension_stretch
			_set_hitbox_active(false)
	else:
		if is_thrust_releasing:
			var t = time_since_release / thrust_duration
			if t < 1.0:
				var peak_stretch = 1.0 + (stored_thrust_power * (max_thrust_scale - 1.0))
				if t < 0.2:
					var shoot_t = t / 0.2
					current_stretch = lerp(1.0 - (stored_thrust_power * max_compress_ratio), peak_stretch, shoot_t)
				else:
					var settle_t = (t - 0.2) / 0.8
					settle_t = 1.0 - pow(1.0 - settle_t, 3.0)
					current_stretch = lerp(peak_stretch, 1.0, settle_t)
			else:
				current_stretch = 1.0
				is_thrust_releasing = false
				_set_hitbox_active(false)
		else:
			# 传统的横扫表现
			var current_speed = abs(angular_velocity)
			var dynamic_stretch = current_speed * stretch_sensitivity
			current_stretch = 1.0 + clamp(dynamic_stretch, 0.0, max_stretch_scale - 1.0)
		
	# 体积守恒与拉伸应用
	var current_squeeze = pow(1.0 / current_stretch, squash_power)
		
	crown_target.position = base_crown_pos * current_stretch
	
	if has_node("hitbox"):
		$hitbox.position = base_hitbox_pos * current_stretch
		$hitbox.scale = base_hitbox_scale * Vector2(current_squeeze, current_stretch)

	if head_sprites.size() > current_stage_index and head_sprites[current_stage_index]:
		var current_sprite = head_sprites[current_stage_index]
		current_sprite.position = base_sprite_positions[current_stage_index] * current_stretch

	# 绘制曲线
	trunk_line.clear_points()
	var p0 = crown_target.global_position  
	var p2 = tree_root.global_position     
	var dist = p0.distance_to(p2)
	var p1 = p2 + Vector2.UP * (dist * 0.6) 
	
	p0 = trunk_line.to_local(p0)
	p1 = trunk_line.to_local(p1)
	p2 = trunk_line.to_local(p2)
	
	for i in range(curve_segments + 1):
		var t = float(i) / float(curve_segments) 
		var q0 = p0.lerp(p1, t)
		var q1 = p1.lerp(p2, t)
		var curve_point = q0.lerp(q1, t)
		trunk_line.add_point(curve_point)
		
	var parent_node = $".."
	var base_trunk_width = 20.0
	if parent_node and "trunk_widths" in parent_node:
		base_trunk_width = parent_node.trunk_widths[current_stage_index]
	
	trunk_line.width = base_trunk_width * current_squeeze

# ==========================================
# 🔥【核心机制】：蓄力段数伤害计算
# 传入一个 0.0 到 1.0 的蓄力比例，返回对应的基础伤害
# ==========================================
func calculate_tier_damage(charge_ratio: float) -> float:
	if charge_ratio >= 0.93:       # 达到 93% 以上 (即差距在 7% 以内) -> 完美蓄力！
		return tier_damage_perfect
	elif charge_ratio >= 0.80:     # 达到 80% 到 93% 之间 (差距在 7%~20%)
		return tier_damage_high
	elif charge_ratio >= 0.60:     # 达到 60% 到 80% 之间 (差距在 20%~40%)
		return tier_damage_mid
	else:                          # 连 60% 都没到 -> 软弱无力
		return tier_damage_low

func _start_drag():
	is_dragging = true
	charge_audio.play() 

func _release_drag():
	is_dragging = false
	time_since_release = 0.0 
	charge_audio.stop() 
	AudioManager.play_sfx(释放破空_sfx, -10.0, false)
	
	if is_thrust_charging:
		locked_attack_damage = calculate_tier_damage(stored_thrust_power)
		is_thrust_charging = false
		is_thrust_releasing = true
		_set_hitbox_active(true)
	else:
		var current_angle = wrapf(global_transform.get_rotation(), -PI, PI)
		var max_rad = deg_to_rad(max_drag_angle_deg)
		var current_charge_ratio = clamp(abs(current_angle) / max_rad, 0.0, 1.0)
		locked_attack_damage = calculate_tier_damage(current_charge_ratio)
		fake_target_angle = -current_angle * whip_overshoot_ratio
		_set_hitbox_active(true)

func _handle_virtual_inputs() -> void:
	var kb_dir = Vector2.ZERO
	if Input.is_physical_key_pressed(KEY_A) or Input.is_action_pressed("ui_left"): kb_dir.x -= 1.0
	if Input.is_physical_key_pressed(KEY_D) or Input.is_action_pressed("ui_right"): kb_dir.x += 1.0
	if Input.is_physical_key_pressed(KEY_W) or Input.is_action_pressed("ui_up"): kb_dir.y -= 1.0
	if Input.is_physical_key_pressed(KEY_S) or Input.is_action_pressed("ui_down"): kb_dir.y += 1.0
	
	var joy_x = Input.get_joy_axis(0, JOY_AXIS_LEFT_X)
	var joy_y = Input.get_joy_axis(0, JOY_AXIS_LEFT_Y)
	if abs(joy_x) > 0.15 or abs(joy_y) > 0.15:
		kb_dir = Vector2(joy_x, joy_y)
	elif kb_dir.length() > 0:
		kb_dir = kb_dir.normalized()
		
	if kb_dir.length() > 0.1:
		is_controller_dragging = true
		if not is_dragging:
			_start_drag()
	else:
		if is_controller_dragging:
			is_controller_dragging = false
			if not is_mouse_dragging and is_dragging:
				_release_drag()
				
	if is_mouse_dragging:
		current_drag_delta = get_global_mouse_position() - tree_root.global_position
	elif is_controller_dragging:
		current_drag_delta = kb_dir * grab_radius
	else:
		current_drag_delta = Vector2.ZERO

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and GameData.is_endless_mode:
		if event.keycode == KEY_1: evolve_test(0)
		elif event.keycode == KEY_2: evolve_test(1)
		elif event.keycode == KEY_3: evolve_test(2)
		elif event.keycode == KEY_4: evolve_test(3)
	
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		var dist = global_position.distance_to(get_global_mouse_position())
		if event.pressed:
			if dist <= grab_radius:
				is_mouse_dragging = true
				if not is_dragging:
					_start_drag()
				get_viewport().set_input_as_handled()
		else:
			if is_mouse_dragging:
				is_mouse_dragging = false
				if not is_controller_dragging and is_dragging:
					_release_drag()

func _integrate_forces(state: PhysicsDirectBodyState2D) -> void:
	if not tree_root: return
	var anchor_pos = tree_root.global_position

	if is_dragging:
		var delta_pos = current_drag_delta
		
		if is_thrust_charging:
			state.transform = Transform2D(0.0, anchor_pos)
			state.linear_velocity = Vector2.ZERO
			state.angular_velocity = 0.0
		else:
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
		time_since_release += state.step 
		
		if is_thrust_releasing:
			state.transform = Transform2D(0.0, anchor_pos)
			state.linear_velocity = Vector2.ZERO
			state.angular_velocity = 0.0
			return

		var current_angle = state.transform.get_rotation()
		state.transform = Transform2D(current_angle, anchor_pos)
		state.linear_velocity = Vector2.ZERO

		var angle_to_zero = wrapf(current_angle, -PI, PI)
		
		if time_since_release >= whip_recover_time and abs(angle_to_zero) < 0.1 and abs(state.angular_velocity) < 5.0:
			state.transform = Transform2D(0.0, anchor_pos)
			state.angular_velocity = 0.0                   
			_set_hitbox_active(false)                      
			return 

		var progress = clamp(time_since_release / whip_recover_time, 0.0, 1.0)
		var ease_progress = progress * (2.0 - progress) 
		var current_dynamic_target = lerp(fake_target_angle, 0.0, ease_progress)
		var angle_diff = wrapf(current_angle - current_dynamic_target, -PI, PI) 
		
		var dynamic_angular_damping = lerp(angular_damping_whip, angular_damping_settle, progress)
		var torque = -angular_stiffness * angle_diff - dynamic_angular_damping * state.angular_velocity
		state.apply_torque(torque)
		
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

func _on_hitbox_area_entered(area: Area2D) -> void:
	if area.is_in_group("Enemy"):
		AudioManager.play_sfx(击中_sfx, 0.0, true, 3)
		var enemy_body = area.get_parent()
		if not enemy_body or not enemy_body.has_method("take_damage"): return
		
		var base_atk = GameData.player_base_stats.get("attack_power", 0.0)
		var stage_bonus = 0.0
		if GameData.growth_stages.size() > current_stage_index:
			stage_bonus = GameData.growth_stages[current_stage_index].get("base_damage_bonus", 0.0)
			
		var is_valid_hit = false
		
		# 🔥 无论在哪种招式下，只有处于激活打击状态，才触发伤害
		if is_thrust_releasing and has_node("hitbox") and $hitbox.scale.y > 1.2:
			is_valid_hit = true
		elif not is_thrust_releasing and abs(angular_velocity) > damage_velocity_threshold:
			is_valid_hit = true
			
		if is_valid_hit:
			# 真正的最终伤害 = 玩家自身基础攻击力 + 形态加成 + 刚才松手瞬间锁定好的蓄力段位伤害
			var final_damage = base_atk + stage_bonus + locked_attack_damage
			
			# 传入 hit_knockback 的瞬时击退力度，产生出色的打击后坐力效果
			var was_alive = enemy_body.get("current_health") > 0.0 if enemy_body.get("current_health") != null else true
			enemy_body.take_damage(final_damage, global_position, hit_knockback, "canopy_hit")
			SignalBus.on_enemy_hit.emit(final_damage, enemy_body.global_position, enemy_body, "canopy_hit")
			
			# 计数：如果这一击杀死了敌人，则计数
			var is_dead = not is_instance_valid(enemy_body) or enemy_body.get("current_health") <= 0.0
			if was_alive and is_dead:
				_kills_this_swing += 1
				if _kills_this_swing >= 10:
					_trigger_mass_kill_hitstop()

var _kills_this_swing: int = 0
var _last_hitstop_time: float = -1.0

## 在挥舞开始时重置击杀计数 (由外部攻击逻辑调用)
func reset_swing_kills() -> void:
	_kills_this_swing = 0

## 树冠普攻卡肉：仅在一次挥舞中满足 10+ 击杀时触发
func _trigger_mass_kill_hitstop() -> void:
	var now = Time.get_ticks_msec() / 1000.0
	if now - _last_hitstop_time < 0.15:
		return
	_last_hitstop_time = now
	GameData.trigger_hit_stop(0.05, 0.08)

## 保留旧函数签名以防其它地方调用
func trigger_hit_stop() -> void:
	pass # 不再每次击中都全局定格
