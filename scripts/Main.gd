extends Node
# ═══════════════════════════════════════════════════════════════
#  Main.gd — 游戏主控制中心
#  负责协调 UI、数据和游戏世界，模拟核心 Roguelite 循环。
# ═══════════════════════════════════════════════════════════════

@onready var tree = $tree
@onready var hud = $HUD
@onready var upgrade_ui = $UpgradeUI

@export var bg_1 :AudioStream
@export var bg_2 :AudioStream
@export var bg_3 :AudioStream

@export var 升级_sfx :AudioStream
@export var 死亡_music :AudioStream

@export_group("Ending Cinematic")
@export var ending_hit_tex_1: Texture2D
@export var ending_hit_tex_2: Texture2D
@export var ending_hit_tex_3: Texture2D
@export var ending_hit_tex_4: Texture2D
@export var ending_broken_screen: Texture2D
@export var ending_hit_sfx: AudioStream
@export var ending_shatter_sfx: AudioStream

var attack_timer: Timer
# --- 关卡时间控制 ---
var level_timer: float = 30.0
var is_level_active: bool = true
var _hp_regen_accumulator: float = 0.0
const HP_REGEN_TICK: float = 0.5 # 每 0.5 秒回血一次

func _ready():
	# 确保从其他场景（或被特效卡主时间的时候）返回时，时间流速和暂停状态是正常的
	Engine.time_scale = 1.0
	get_tree().paused = false

	
	print("[Main] 游戏启动，正在建立各系统连接...")

	# 初始化数据
	GameData.reset()
	
	# 根据当前正在游玩的关卡，让树苗直接长到对应的第二/第三种形态
	if tree.has_method("evolve_to_stage"):
		if GameData.is_endless_mode:
			tree.evolve_to_stage(GameData.selected_sapling - 1)
		else:
			# 强制把当前关卡的索引（从1开始）减1作为进化阶段
			tree.evolve_to_stage(GameData.current_playing_stage - 1)

	if GameData.is_endless_mode:
		level_timer = 0.0
		print("[Main] 无尽模式：计时器从 0 开始。")
	else:
		match GameData.current_playing_stage:
			1: level_timer = 30.0
			2: level_timer = 60.0
			3: level_timer = 100.0
			4: level_timer = 10.0
			_: level_timer = 60.0
		print("[Main] 关卡计时器初始化: ", level_timer, "s")
	
	# 重置波次
	GameData.current_wave = 0
	
	# 装载核心引擎：把《技能执行器》组件挂载到树身上
	var skill_executor_script = load("res://scripts/components/SkillExecutor.gd")
	var skill_executor = skill_executor_script.new()
	skill_executor.name = "SkillExecutor"
	tree.add_child(skill_executor)
	print("[Main] SkillExecutor 已成功挂载到 PlayerTree 下。")
	
	# 加载历史技能叠加 (除了无尽模式)
	GameData.apply_historical_skills()
	
	# 监听玩家的选择
	SignalBus.on_upgrade_selected.connect(_on_skill_chosen)
	
	# 监听升级UI打开请求 (Dev A 触发 → Main 暂停攻击计时器 → Dev B 的UI弹出)
	SignalBus.open_upgrade_ui.connect(_on_open_upgrade_ui)
	
	# 监听返回年轮主界面请求 (代替了之前的退出)
	SignalBus.on_return_requested.connect(_on_return_requested)

	# 监听敌人死亡事件
	SignalBus.on_enemy_died.connect(_on_enemy_died)


	AudioManager.play_music(bg_1) # 启动时播放第一首背景音乐

	# 监听暂停请求
	SignalBus.on_pause_requested.connect(_on_pause_requested)
	
	# 监听死亡结束请求
	SignalBus.on_game_over.connect(_on_game_over)


func _level_up():
	if not is_level_active: return # 如果过关或进了结局，彻底禁止升级
	
	var needed = GameData.get_exp_to_next_level(GameData.current_level)
	GameData.current_level += 1
	GameData.current_exp = maxf(0.0, GameData.current_exp - needed)
	
	print("[Main] 升级了！当前等级: ", GameData.current_level)
	SignalBus.on_level_up.emit(GameData.current_level)
		
func _on_skill_chosen(skill_id: String):
	# 如果正在恢复历史技能，不要再次记录到当前历史中
	if GameData.is_restoring_history:
		return

	print("[Main] 收到进化指令: ", skill_id)
	var payload = GameData.decode_upgrade_payload(skill_id)
	var real_skill_id = str(payload.get("skill_id", skill_id))
	
	# 👉 对接到局外存储：记录这把在这一圈年轮上拿到的能力！
	if not GameData.is_endless_mode:
		GameData.record_skill_for_stage(GameData.current_playing_stage, real_skill_id)
	

# ── 打开升级选择 UI ─────────────────────────────────────────────
func _on_open_upgrade_ui():
	print("[Main] 升级UI请求：暂停攻击计时器")
	# UpgradeUI 自己监听 open_upgrade_ui 信号并显示，Main 不直接操作它

# ── 返回年轮主界面 ────────────────────────────────────────────────────
func _on_return_requested():
	print("[Main] 收到返回请求，正在退回年轮...")
	get_tree().change_scene_to_file("res://scenes/ui/AnnualRingMenu.tscn")

# ── 键盘快捷键 ─────────────────────────────────────────────────
func _input(event      : InputEvent):
	# Escape 键呼出暂停菜单
	if event.is_action_pressed("ui_cancel"):
		_on_pause_requested()

# ── 倒计时与通关逻辑 ───────────────────────────────────────────
func _process(delta):
	if not is_level_active: return
	_apply_hp_regen(delta)
	
	if GameData.is_endless_mode:
		level_timer += delta
		if hud.has_method("update_timer"):
			hud.update_timer(level_timer)
		return
		
	if level_timer > 0:
		level_timer -= delta
		if hud.has_method("update_timer"):
			hud.update_timer(max(level_timer, 0.0))
			
		if level_timer <= 0:
			_level_completed()

func _apply_hp_regen(delta: float) -> void:
	var regen_per_sec = float(GameData.player_base_stats.get("hp_regen", 0.0))
	if regen_per_sec <= 0.0 or GameData.current_hp <= 0.0:
		return
	var max_hp = float(GameData.player_base_stats.get("max_hp", 100.0))
	if GameData.current_hp >= max_hp:
		return
		
	_hp_regen_accumulator += delta
	if _hp_regen_accumulator >= HP_REGEN_TICK:
		var amount_to_heal = regen_per_sec * _hp_regen_accumulator
		_hp_regen_accumulator = 0.0
		
		var next_hp = minf(GameData.current_hp + amount_to_heal, max_hp)
		GameData.current_hp = next_hp
		# 终于告别满屏信号风暴啦！仅在跨越刻度时投递 UI 更新
		SignalBus.on_player_hp_changed.emit(GameData.current_hp, max_hp)

func _level_completed():
	is_level_active = false
	print("[Main] 关卡 30s 倒计时结束，通关！")
		
	# 如果是第一次打过当前最高关卡，则解锁下一关
	if GameData.current_playing_stage == GameData.current_max_stage:
		if GameData.current_max_stage < GameData.MAX_STAGES:
			GameData.current_max_stage += 1
		GameData.save_game()
	
	if GameData.current_playing_stage >= GameData.MAX_STAGES:
		# 解锁无尽模式并去结局界面
		GameData.is_endless_unlocked = true
		GameData.save_game()
		_play_true_ending_cinematic() # 触发结局狂暴动画！
	else:
		_show_level_clear_popup(false)

func _play_true_ending_cinematic():
	# 1. 禁用所有 UI 和普通进程的干扰！
	hud.hide()
	if is_instance_valid(upgrade_ui):
		upgrade_ui.hide()
		upgrade_ui.process_mode = Node.PROCESS_MODE_DISABLED
		
	var treehead = tree.get_node_or_null("treehead")
	if treehead:
		treehead.set_physics_process(false)
		treehead.is_dragging = false
		treehead.set_process_input(false)
		
	# 2. 找到当前正在显示的树冠 Sprite
	var active_crown: Sprite2D = null
	var crown_base_scale := Vector2.ONE
	if treehead:
		for child in treehead.get_children():
			if child is Sprite2D and "HeadSprite" in child.name and child.visible:
				active_crown = child
				crown_base_scale = child.scale
				break
				
	# 3. 大树开始疯狂乱摇
	var wild_tween = create_tween().set_parallel(true)
	if treehead:
		for i in range(20):
			wild_tween.tween_property(treehead, "rotation", randf_range(-PI/2, PI/2), 0.1).set_delay(i * 0.1).set_trans(Tween.TRANS_BOUNCE)
			if active_crown:
				var random_s = crown_base_scale * randf_range(0.8, 1.5)
				wild_tween.tween_property(active_crown, "scale", random_s, 0.1).set_delay(i * 0.1)
	
	# 给玩家看 2 秒的疯狂发癫
	await get_tree().create_timer(2.0).timeout
	
	# 3. 准备覆盖屏幕的节点
	var end_layer = CanvasLayer.new()
	end_layer.layer = 120 # 最高层级
	
	# 全屏黑屏背景 (一开始完全透明)
	var black_bg = ColorRect.new()
	black_bg.color = Color(0, 0, 0, 0)
	black_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	end_layer.add_child(black_bg)
	
	# 屏幕打击贴图
	var hit_rect = TextureRect.new()
	hit_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	hit_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	hit_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	end_layer.add_child(hit_rect)
	
	add_child(end_layer)
	
	# 播放声音的临时节点
	var audio_player = AudioStreamPlayer.new()
	add_child(audio_player)
	
	var textures = [ending_hit_tex_1, ending_hit_tex_2, ending_hit_tex_3, ending_hit_tex_4]
	
	# 4. 依次打击 4 下 (同步动画)
	for i in range(4):
		
		# -- 树冠本体破壁演出 (后仰蓄力 -> 砸向屏幕) --
		if active_crown:
			var tree_tw = create_tween()
			tree_tw.tween_property(active_crown, "scale", crown_base_scale * 0.5, 0.15).set_trans(Tween.TRANS_SINE) # 蓄力缩小
			tree_tw.tween_property(active_crown, "scale", crown_base_scale * 7.0, 0.05).set_trans(Tween.TRANS_EXPO) # 树冠贴脸暴增
			# 砸完之后慢速恢复一点
			tree_tw.tween_property(active_crown, "scale", crown_base_scale * 1.5, 0.4).set_trans(Tween.TRANS_LINEAR)
			await get_tree().create_timer(0.15).timeout
		else:
			await get_tree().create_timer(0.15).timeout
			
		
		# -- 碎屏贴图与音效触发 (大树刚好放到最大的瞬间) --
		if textures[i]:
			hit_rect.texture = textures[i]
		
		# 极大幅度闪缩与震动反馈
		hit_rect.scale = Vector2(1.5, 1.5)
		hit_rect.position = hit_rect.size * -0.25 # 保持居中缩放偏移
		var hit_tw = create_tween()
		hit_tw.tween_property(hit_rect, "scale", Vector2(1.0, 1.0), 0.1).set_trans(Tween.TRANS_BOUNCE)
		hit_tw.parallel().tween_property(hit_rect, "position", Vector2.ZERO, 0.1)
		
		# 加深一次背景黑度
		black_bg.color.a = float(i + 1) * 0.2
		
		if ending_hit_sfx:
			audio_player.stream = ending_hit_sfx
			audio_player.pitch_scale = randf_range(0.9, 1.1)
			audio_player.play()
			
		# 发送强力屏幕震动
		var cam = get_viewport().get_camera_2d()
		if cam:
			cam.offset = Vector2(randf_range(-60, 60), randf_range(-60, 60) - 200)
			
		# 留出充足时间（比如 0.4s）让玩家看到这一砸的结果，再进行下一砸
		await get_tree().create_timer(0.4).timeout
		
	# 5. 第 5 下，终极砸碎屏幕！
	if active_crown:
		var last_tw = create_tween()
		# 最后一下蓄力缩到极小 (0.4s)
		last_tw.tween_property(active_crown, "scale", crown_base_scale * 0.15, 0.4).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		# 极速砸脸 (0.1s)
		last_tw.tween_property(active_crown, "scale", crown_base_scale * 25.0, 0.1).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN)
	
	# 蓄力 0.4s 结束后，在猛冲刚开始的 0.42s 瞬间触发最终碎屏
	await get_tree().create_timer(0.42).timeout 
	
	if ending_broken_screen:
		hit_rect.texture = ending_broken_screen
	
	black_bg.color.a = 1.0 # 彻底切为纯黑
	
	if ending_shatter_sfx:
		audio_player.stream = ending_shatter_sfx
		audio_player.pitch_scale = 1.0
		audio_player.play()
	
	# 最剧烈的震动
	var cam = get_viewport().get_camera_2d()
	if cam:
		cam.offset = Vector2(randf_range(-150, 150), randf_range(-150, 150) - 200)
		create_tween().tween_property(cam, "offset", Vector2(0, -200), 1.0)
		
	# 6. 等待最后的破碎画面停留
	await get_tree().create_timer(3.0).timeout
	
	# 显示感谢名单 / 返回按钮
	var end_label = Label.new()
	end_label.text = "THE END\n\n谢谢你，让神木重归安宁。"
	end_label.add_theme_font_size_override("font_size", 60)
	end_label.add_theme_color_override("font_color", Color.WHITE)
	end_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	end_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	end_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	end_label.modulate.a = 0.0
	end_layer.add_child(end_label)
	
	# 隐去裂痕，浮现字幕
	var final_tw = create_tween()
	final_tw.tween_property(hit_rect, "modulate:a", 0.0, 2.0)
	final_tw.tween_property(end_label, "modulate:a", 1.0, 2.0)
	
	await get_tree().create_timer(5.0).timeout
	GameData.just_finished_final_stage = true # 标记为刚刚通关，触发时钟倒流视觉动画
	get_tree().change_scene_to_file("res://scenes/ui/AnnualRingMenu.tscn")

func _show_level_clear_popup(is_final: bool):
	var popup = CanvasLayer.new()
	popup.layer = 100
	
	var bg = ColorRect.new()
	bg.color = Color(0.05, 0.05, 0.05, 0.85) # 纯净的半透明黑色，高级感拉满
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	popup.add_child(bg)
	
	var center = CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	popup.add_child(center)
	
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 50)
	center.add_child(vbox)
	
	var label = Label.new()
	label.text = "关卡 " + str(GameData.current_playing_stage) + " 历练完成"
	label.add_theme_font_size_override("font_size", 56)
	label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0))
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(label)
	
	var btn_container = VBoxContainer.new()
	btn_container.add_theme_constant_override("separation", 20)
	vbox.add_child(btn_container)
	
	if is_final:
		label.text = "最终试炼通过！\n神秘的无尽模式已现形..."
		var btn_end = Button.new()
		btn_end.text = " 见证最终生长 (进入结局) "
		btn_end.add_theme_font_size_override("font_size", 40)
		btn_end.custom_minimum_size = Vector2(400, 100)
		btn_end.pressed.connect(func():
			get_tree().paused = false
			get_tree().change_scene_to_file("res://scenes/ui/EndingScene.tscn")
		)
		btn_container.add_child(btn_end)
	else:
		# 下一关按钮
		var btn_next = Button.new()
		btn_next.text = " 继续扎根：下一关 "
		btn_next.add_theme_font_size_override("font_size", 40)
		btn_next.add_theme_color_override("font_color", Color(0.9, 1.0, 0.5))
		btn_next.custom_minimum_size = Vector2(400, 100)
		btn_next.pressed.connect(func():
			get_tree().paused = false
			# 如果还能往后打，直接把当前游玩关卡+1
			GameData.current_playing_stage = min(GameData.current_playing_stage + 1, GameData.MAX_STAGES)
			get_tree().change_scene_to_file("res://Main.tscn")
		)
		btn_container.add_child(btn_next)
		
		# 返回年轮按钮
		var btn_return = Button.new()
		btn_return.text = " 返回年轮选关 "
		btn_return.add_theme_font_size_override("font_size", 28)
		btn_return.custom_minimum_size = Vector2(400, 80)
		btn_return.pressed.connect(func():
			get_tree().paused = false
			get_tree().change_scene_to_file("res://scenes/ui/AnnualRingMenu.tscn")
		)
		btn_container.add_child(btn_return)
		
	# 暂停游戏物理，等待玩家点击
	get_tree().paused = true
	popup.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(popup)


func _on_pause_requested():
	if is_level_active:
		print("[Main] 暂停游戏并呼出菜单")
		# 实例化 PauseMenu (如果尚未打开的话)
		var pause_menu = load("res://scenes/ui/PauseMenu.tscn").instantiate()
		add_child(pause_menu)
		get_tree().paused = true

func _on_enemy_died(exp_value: float, position: Vector2):
	if not is_level_active: return # 关卡停止后不再产生新经验
	
	print("[Main] 敌人死亡，获得经验: ", exp_value)

	# 增加经验值
	GameData.current_exp += exp_value

	# 计算经验进度
	var needed = GameData.get_exp_to_next_level(GameData.current_level)
	var ratio = GameData.current_exp / needed

	# 通知 HUD 更新经验条
	SignalBus.on_exp_gained.emit(ratio)

	# 检查是否升级
	if GameData.current_exp >= needed:
		_level_up()

func _on_game_over():
	if not is_level_active: return
	is_level_active = false
	print("[Main] 收到玩家死亡信号，游戏结束")
	
	AudioManager.play_sfx(死亡_music, 5, false, 1) # 播放死亡音乐，限制同款音乐只允许1个实例
		
	# 1. 震撼效果：时间极度放慢 (Hit Stop / Slowmo Death)
	Engine.time_scale = 0.1
	
	# 2. 屏幕震动与闪红
	var camera = get_viewport().get_camera_2d()
	if camera:
		var start_offset = camera.offset
		var tween = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		for i in range(15):
			tween.tween_property(camera, "offset", start_offset + Vector2(randf_range(-25, 25), randf_range(-25, 25)), 0.05)
		tween.tween_property(camera, "offset", start_offset, 0.05)
		
	# 闪烁猩红全屏覆盖
	var fx_layer = CanvasLayer.new()
	fx_layer.layer = 99
	var blood_rect = ColorRect.new()
	blood_rect.color = Color(0.8, 0.0, 0.0, 0.5)
	blood_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	fx_layer.add_child(blood_rect)
	add_child(fx_layer)
	
	# 让血红闪烁然后淡出
	var btween = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	btween.tween_property(blood_rect, "color:a", 0.0, 0.8)
	
	# 3. 等待1秒真实时间（在慢动作中让玩家看清死亡）
	await get_tree().create_timer(1.2, true, false, true).timeout
	Engine.time_scale = 1.0 # 跨场景前必须恢复时间
	get_tree().paused = true # 正式冻结游戏
	
	# 4. 原木风复古界面构建
	_show_game_over_ui()

func _show_game_over_ui():
	var popup = CanvasLayer.new()
	popup.layer = 100
	
	var root_control = Control.new()
	root_control.set_anchors_preset(Control.PRESET_FULL_RECT)
	popup.add_child(root_control)
	
	var bg = ColorRect.new()
	bg.color = Color(0.08, 0.03, 0.02, 0.96) # 极深的暗血木色
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	root_control.add_child(bg)
	
	var center = CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	root_control.add_child(center)
	
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 60)
	center.add_child(vbox)
	
	var label = Label.new()
	label.text = "神木倾倒\n\n自然重归死寂"
	label.add_theme_font_size_override("font_size", 72)
	label.add_theme_color_override("font_color", Color(0.9, 0.25, 0.25, 1))
	label.add_theme_color_override("font_shadow_color", Color(0.15, 0.05, 0.05, 1))
	label.add_theme_constant_override("shadow_offset_x", 8)
	label.add_theme_constant_override("shadow_offset_y", 8)
	label.add_theme_constant_override("outline_size", 16)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(label)
	
	# 原木风按钮样式
	var btn_normal = StyleBoxFlat.new()
	btn_normal.bg_color = Color(0.18, 0.12, 0.09, 1)
	btn_normal.border_width_left = 6
	btn_normal.border_width_right = 6
	btn_normal.border_color = Color(0.35, 0.20, 0.15, 1)
	btn_normal.corner_radius_top_left = 8
	btn_normal.corner_radius_top_right = 8
	btn_normal.corner_radius_bottom_right = 8
	btn_normal.corner_radius_bottom_left = 8
	
	var btn_hover = btn_normal.duplicate()
	btn_hover.bg_color = Color(0.40, 0.25, 0.18, 1) # 微微带红的暗金/实木
	btn_hover.border_color = Color(0.70, 0.40, 0.30, 1)
	
	var btn_pressed = btn_normal.duplicate()
	btn_pressed.bg_color = Color(0.12, 0.08, 0.05, 1)
	
	var btn_return = Button.new()
	btn_return.text = " 逝者如斯（返回年轮） "
	btn_return.add_theme_font_size_override("font_size", 36)
	btn_return.add_theme_color_override("font_color", Color(0.95, 0.85, 0.65, 1))
	btn_return.add_theme_stylebox_override("normal", btn_normal)
	btn_return.add_theme_stylebox_override("hover", btn_hover)
	btn_return.add_theme_stylebox_override("pressed", btn_pressed)
	btn_return.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	btn_return.custom_minimum_size = Vector2(400, 90)
	
	btn_return.pressed.connect(func():
		get_tree().paused = false
		get_tree().change_scene_to_file("res://scenes/ui/AnnualRingMenu.tscn")
	)
	vbox.add_child(btn_return)
	
	# 强力的渐进淡入特效
	root_control.modulate.a = 0.0
	popup.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(popup)
	
	var ui_tween = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	ui_tween.tween_property(root_control, "modulate:a", 1.0, 1.2).set_trans(Tween.TRANS_QUAD)
