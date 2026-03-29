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

var attack_timer: Timer
# --- 关卡时间控制 ---
var level_timer: float = 30.0
var is_level_active: bool = true

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

	
	# 装载核心引擎：把《技能执行器》组件挂载到树身上
	var skill_executor_script = load("res://scripts/components/SkillExecutor.gd")
	var skill_executor = skill_executor_script.new()
	skill_executor.name = "SkillExecutor"
	tree.add_child(skill_executor)
	print("[Main] SkillExecutor 已成功挂载到 PlayerTree 下。")
	
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


func _level_up():
	
	GameData.current_level += 1
	GameData.current_exp = 0.0
	
	print("[Main] 升级了！当前等级: ", GameData.current_level)
	SignalBus.on_level_up.emit(GameData.current_level)
		
func _on_skill_chosen(skill_id: String):
	print("[Main] 收到进化指令: ", skill_id)
	
	# 👉 对接到局外存储：记录这把在这一圈年轮上拿到的能力！
	GameData.record_skill_for_stage(GameData.current_playing_stage, skill_id)
	

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
		_show_level_clear_popup(true)
	else:
		_show_level_clear_popup(false)

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
