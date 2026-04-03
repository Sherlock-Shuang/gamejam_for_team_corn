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
var _last_timer_sec: int = -1 # 用于节流 UI 时钟更新

func _ready():
	Engine.time_scale = 1.0
	GameData.set_game_paused(false)
	GameData.is_in_ending_cinematic = false

	
	print("[Main] 游戏启动，正在建立各系统连接...")

	# 初始化数据
	# 无尽模式 或 第一关：完整重置（全新开局）
	# 剧情模式第 2~4 关：仅增量重置（保留等级和技能）
	if GameData.is_endless_mode or GameData.current_playing_stage == 1:
		GameData.reset_run()
	else:
		GameData.reset_stage()
	
	# 从年轮选关进入第 2+ 关时，技能被 reset_run 清空；从历史存档恢复前关技能
	if not GameData.is_endless_mode and GameData.current_playing_stage >= 2 and GameData.current_run_skill_ids.is_empty():
		GameData.apply_historical_skills()
	
	# HUD._ready() 先于 Main._ready() 执行，可能读到上一局残留的 current_level
	if hud and hud.has_node("HUDMargin/HUDContainer/RingContainer/LevelLabel"):
		hud.get_node("HUDMargin/HUDContainer/RingContainer/LevelLabel").text = "Lv." + str(GameData.current_level)
		var needed = GameData.get_exp_to_next_level(GameData.current_level)
		var exp_ratio = GameData.current_exp / needed if needed > 0 else 0.0
		hud.get_node("HUDMargin/HUDContainer/RingContainer/ExpRing").value = exp_ratio * 100.0
	
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
			1: level_timer = 50.0
			2: level_timer = 55.0
			3: level_timer = 80.0
			4: level_timer = 100.0
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
	
	# 初始技能加载已迁移至 SkillExecutor._sync_on_ready()，通过内部同步保证稳定
	
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
	
	# 监听首个精英怪出现
	SignalBus.on_first_elite_spawned.connect(_on_first_elite_spawned)


func _level_up():
	if not is_level_active: return 
	
	var needed = GameData.get_exp_to_next_level(GameData.current_level)
	GameData.current_level += 1
	GameData.current_exp = maxf(0.0, GameData.current_exp - needed)
	
	print("[Main] 升级了！当前级: ", GameData.current_level)
	SignalBus.on_level_up.emit(GameData.current_level)
	
	# --- 1. 获取候选技能并弹出 UI ---
	var candidates = GameData.get_random_skills(3)
	
	if candidates.is_empty():
		print("[Main] 所有技能已升满。")
		return
		
	# 弹出三选一 UI
	SignalBus.open_upgrade_ui.emit(candidates)

func _on_skill_chosen(skill_id: String):
	# 如果正在恢复历史技能，不要再次记录到当前历史中
	if GameData.is_restoring_history:
		return

	print("[Main] 收到进化指令: ", skill_id)
	
	# --- 2. 检查是否还有连续升级 ---
	# 我们在此处延迟检查，在玩家选完一个之后立即检查是否满足下一级条件
	# 延迟一点时间确保 UI 关闭逻辑彻底完成
	get_tree().create_timer(0.2).timeout.connect(func():
		var next_needed = GameData.get_exp_to_next_level(GameData.current_level)
		if GameData.current_exp >= next_needed:
			_level_up()
	)
	
	var payload = GameData.decode_upgrade_payload(skill_id)
	var real_skill_id = str(payload.get("skill_id", skill_id))
	
	# 👉 对接到局外存储：改在通关(Level Clear)时才统一保存这一整组技能
	# 以往在这里实时 record 会导致死亡后技能依然残留，现在删除了这里的逻辑
	pass
	

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
		GameData.endless_time = level_timer # 同步到全局数据供难度缩放使用
		if hud.has_method("update_timer"):
			var current_sec = floori(level_timer)
			if current_sec != _last_timer_sec:
				_last_timer_sec = current_sec
				hud.update_timer(float(current_sec))
		return
		
	if level_timer > 0:
		level_timer -= delta
		if hud.has_method("update_timer"):
			var current_sec = floori(maxf(level_timer, 0.0))
			if current_sec != _last_timer_sec:
				_last_timer_sec = current_sec
				hud.update_timer(float(current_sec))
			
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
		
	# 【存档修正】：在通关瞬间，将这局选好的技能组合固化到历史存档中
	if not GameData.is_endless_mode:
		GameData.record_skill_for_stage(GameData.current_playing_stage)
		
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
	GameData.is_in_ending_cinematic = true
	# 停止游戏：树不再攻击，怪物停止行进
	var skill_executor = tree.get_node_or_null("SkillExecutor")
	if skill_executor:
		skill_executor.set_process(false)
		# 停止所有技能定时器
		for child in skill_executor.get_children():
			if child is Timer:
				child.stop()
	
	$WaveManager/WaveTimer.stop()
	
	var enemies = get_tree().get_nodes_in_group("enemies")
	for enemy in enemies:
		if enemy.has_method("set_physics_process"):
			enemy.set_physics_process(false)
	
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
			audio_player.volume_db = 10.0
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
	AudioManager.stop_all() # 🎵【新增】：黑屏瞬间关掉所有背景杂音(音乐+脚步声等)
	
	if ending_shatter_sfx:
		audio_player.stream = ending_shatter_sfx
		audio_player.volume_db = 15.0
		audio_player.play()
	
	# 最剧烈的震动
	var cam = get_viewport().get_camera_2d()
	if cam:
		cam.offset = Vector2(randf_range(-150, 150), randf_range(-150, 150) - 200)
		create_tween().tween_property(cam, "offset", Vector2(0, -200), 1.0)
		
	# 6. 等待最后的破碎画面停留
	await get_tree().create_timer(3.0).timeout
	
	# 画面一：神罚与归寂 (取代 THE END)
	print("[Cinematic] 进入画面一：神罚与归寂")
	var viewport_size = get_viewport().size
	var viewport_w = viewport_size.x
	
	var scene_1_root = Control.new()
	scene_1_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	scene_1_root.modulate.a = 0.0
	end_layer.add_child(scene_1_root)
	
	var scene_1_center = CenterContainer.new()
	scene_1_center.set_anchors_preset(Control.PRESET_FULL_RECT)
	scene_1_root.add_child(scene_1_center)
	
	var scene_1_box = VBoxContainer.new()
	scene_1_box.add_theme_constant_override("separation", 30)
	scene_1_center.add_child(scene_1_box)
	
	var custom_font = load("res://assets/fonts/朝华标题A.ttf")
	
	var scene_1_title = Label.new()
	scene_1_title.text = "神树降下神罚"
	if custom_font: scene_1_title.add_theme_font_override("font", custom_font)
	scene_1_title.add_theme_font_size_override("font_size", 120)
	scene_1_title.add_theme_color_override("font_color", Color(1.0, 0.9, 0.4))
	scene_1_title.add_theme_constant_override("outline_size", 24)
	scene_1_title.add_theme_color_override("font_outline_color", Color(0.5, 0.2, 0.0))
	scene_1_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	scene_1_box.add_child(scene_1_title)
	
	var scene_1_sub = Label.new()
	scene_1_sub.text = "屏幕碎裂，万物归寂"
	if custom_font: scene_1_sub.add_theme_font_override("font", custom_font)
	scene_1_sub.add_theme_font_size_override("font_size", 48)
	scene_1_sub.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	scene_1_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	scene_1_box.add_child(scene_1_sub)

	# 等待一帧让布局系统计算出 label 的实际尺寸
	await get_tree().process_frame

	# 隐去裂痕，浮现画面一 (带震撼缩放，从屏幕正中央展开)
	scene_1_title.pivot_offset = scene_1_title.size / 2.0
	scene_1_title.scale = Vector2(0.3, 0.3)
	
	var scene_1_tw = create_tween().set_parallel(true)
	scene_1_tw.tween_property(hit_rect, "modulate:a", 0.0, 1.5)
	scene_1_tw.tween_property(scene_1_root, "modulate:a", 1.0, 1.5)
	scene_1_tw.tween_property(scene_1_title, "scale", Vector2(1.0, 1.0), 0.5).set_trans(Tween.TRANS_BOUNCE)
	
	# 文本轻微颤动效果（基于 0 点偏移，结束后复位）
	for i in range(15):
		scene_1_tw.tween_property(scene_1_title, "position:x", randf_range(-10, 10), 0.1).set_delay(i * 0.1)
	scene_1_tw.chain().tween_property(scene_1_title, "position:x", 0.0, 0.05)
		
	await get_tree().create_timer(8.0).timeout
	
	# 隐去画面一
	var fade_1_tw = create_tween()
	fade_1_tw.tween_property(scene_1_root, "modulate:a", 0.0, 1.5)
	await fade_1_tw.finished
	scene_1_root.queue_free()

	# 画面二：记忆与时间
	print("[Cinematic] 进入画面二：记忆与时间")
	var scene_2_root = Control.new()
	scene_2_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	scene_2_root.modulate.a = 0.0
	end_layer.add_child(scene_2_root)
	
	var scene_2_center = CenterContainer.new()
	scene_2_center.set_anchors_preset(Control.PRESET_FULL_RECT)
	scene_2_root.add_child(scene_2_center)
	
	var scene_2_box = VBoxContainer.new()
	scene_2_box.add_theme_constant_override("separation", 60)
	scene_2_center.add_child(scene_2_box)
	
	var scene_2_title = Label.new()
	scene_2_title.text = "世界记住了那棵树，\n但树选择了成为时间本身。"
	scene_2_title.add_theme_font_size_override("font_size", 60)
	scene_2_title.add_theme_color_override("font_color", Color(0.9, 0.85, 0.7))
	scene_2_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	scene_2_box.add_child(scene_2_title)
	
	var scene_2_poem = Label.new()
	scene_2_poem.text = "“孤独不是生长之敌，遗忘才是。\n当最后一片年轮归于混沌，\n你已不再是风景——\n你成了轮回的理由。”"
	scene_2_poem.add_theme_font_size_override("font_size", 32)
	scene_2_poem.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7, 0.8)) # 稍微透明，浮现感
	scene_2_poem.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	scene_2_box.add_child(scene_2_poem)

	# 浮现画面二
	var scene_2_tw = create_tween()
	scene_2_tw.tween_property(scene_2_root, "modulate:a", 1.0, 2.5)
	await get_tree().create_timer(10.0).timeout
	
	# 最终黑屏准备跳转
	var exit_tw = create_tween()
	exit_tw.tween_property(scene_2_root, "modulate:a", 0.0, 2.0)
	await exit_tw.finished
	scene_2_root.queue_free()

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
			GameData.set_game_paused(false)
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
			GameData.set_game_paused(false)
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
			GameData.set_game_paused(false)
			get_tree().change_scene_to_file("res://scenes/ui/AnnualRingMenu.tscn")
		)
		btn_container.add_child(btn_return)
		
	# 暂停游戏物理，等待玩家点击
	GameData.set_game_paused(true)
	popup.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(popup)


func _on_pause_requested():
	if is_level_active:
		print("[Main] 暂停游戏并呼出菜单")
		# 实例化 PauseMenu (如果尚未打开的话)
		var pause_menu = load("res://scenes/ui/PauseMenu.tscn").instantiate()
		add_child(pause_menu)
		GameData.set_game_paused(true)

func _on_enemy_died(exp_value: float, position: Vector2, cause: String = ""):
	if not is_level_active: return # 关卡停止后不再产生新经验
	


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
	GameData.set_game_paused(true) # 正式冻结游戏
	
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
		GameData.set_game_paused(false)
		get_tree().change_scene_to_file("res://scenes/ui/AnnualRingMenu.tscn")
	)
	vbox.add_child(btn_return)
	
	# 强力的渐进淡入特效
	root_control.modulate.a = 0.0
	popup.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(popup)
	
	var ui_tween = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	ui_tween.tween_property(root_control, "modulate:a", 1.0, 1.2).set_trans(Tween.TRANS_QUAD)

func _on_first_elite_spawned():
	if not is_level_active:
		return
	_show_elite_hint()

func _show_elite_hint():
	var hint_layer = CanvasLayer.new()
	hint_layer.layer = 90
	
	var panel = PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	panel.position = Vector2(-200, 30)
	panel.custom_minimum_size = Vector2(400, 0)
	
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.5, 0.08, 0.08, 0.92)
	style.border_width_left = 3
	style.border_width_right = 3
	style.border_width_top = 3
	style.border_width_bottom = 3
	style.border_color = Color(1.0, 0.3, 0.2, 1.0)
	style.corner_radius_top_left = 12
	style.corner_radius_top_right = 12
	style.corner_radius_bottom_right = 12
	style.corner_radius_bottom_left = 12
	style.content_margin_left = 20
	style.content_margin_right = 20
	style.content_margin_top = 14
	style.content_margin_bottom = 14
	panel.add_theme_stylebox_override("panel", style)
	
	var vb = VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	panel.add_child(vb)
	
	var title = Label.new()
	title.text = "⚠ 精英怪出现！"
	title.add_theme_font_size_override("font_size", 32)
	title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(title)
	
	var desc = Label.new()
	desc.text = "红色发光的敌人是精英单位\n血量极高、体型更大、经验丰厚\n击败它们可快速升级！"
	desc.add_theme_font_size_override("font_size", 20)
	desc.add_theme_color_override("font_color", Color(0.95, 0.9, 0.85))
	desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(desc)
	
	hint_layer.add_child(panel)
	add_child(hint_layer)
	
	panel.modulate.a = 0.0
	var tw = create_tween()
	tw.tween_property(panel, "modulate:a", 1.0, 0.3)
	tw.tween_interval(3.5)
	tw.tween_property(panel, "modulate:a", 0.0, 0.8)
	tw.tween_callback(hint_layer.queue_free)
