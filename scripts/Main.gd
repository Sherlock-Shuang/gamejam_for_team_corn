extends Node
# ═══════════════════════════════════════════════════════════════
#  Main.gd — 游戏主控制中心
#  负责协调 UI、数据和游戏世界，模拟核心 Roguelite 循环。
# ═══════════════════════════════════════════════════════════════

@onready var tree = $tree
@onready var hud = $HUD
@onready var upgrade_ui = $UpgradeUI

var attack_timer: Timer

func _ready():
	print("[Main] 游戏启动，正在建立各系统连接...")

	# 初始化数据
	GameData.reset()
	
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

	# ====== 经验自动增长测试 ======
	var timer = Timer.new()
	timer.wait_time = 0.1
	timer.autostart = true
	add_child(timer)
	timer.timeout.connect(_test_add_experience)
	
	# ====== 自动攻击演示测试 ======
	attack_timer = Timer.new()
	attack_timer.wait_time = 0.8  # 攻速：0.8秒一发
	attack_timer.autostart = true
	add_child(attack_timer)
	attack_timer.timeout.connect(_test_auto_attack)

func _test_auto_attack():
	# 生成一个临时的菱形作为“攻击投掷物”
	var projectile = Polygon2D.new()
	# 绘制一个简单的四边形
	projectile.polygon = PackedVector2Array([
		Vector2(-10, 0), Vector2(0, -10), Vector2(10, 0), Vector2(0, 10)
	])
	# 随机一点酷炫的“自然魔法”颜色
	projectile.color = [Color(0.6, 1.0, 0.3), Color(0.3, 0.9, 0.8), Color(1.0, 0.9, 0.2)].pick_random()
	
	# 从树的心发射
	projectile.global_position = tree.global_position
	add_child(projectile)
	
	# 随机一个方向飞出去
	var angle = randf() * TAU
	var direction = Vector2.RIGHT.rotated(angle)
	var distance = 500.0  # 飞行距离
	
	# 做个简单的飞行与渐隐动画
	var tween = create_tween().set_parallel(true)
	tween.tween_property(projectile, "position", projectile.global_position + direction * distance, 0.6).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(projectile, "scale", Vector2(1.5, 1.5), 0.6)
	tween.tween_property(projectile, "modulate", Color(1, 1, 1, 0), 0.6)
	
	# 动画结束自动删除节点，保护内存！(类似 Dev A 写的对象池思维)
	tween.chain().tween_callback(projectile.queue_free)

# 模拟获得经验
func _test_add_experience():
	# 每次增加一点点经验
	var exp_to_add = 0.5
	GameData.current_exp += exp_to_add
	
	var needed = GameData.get_exp_to_next_level(GameData.current_level)
	var ratio = GameData.current_exp / needed
	
	# 通知 HUD 更新！
	SignalBus.on_exp_gained.emit(ratio)
	
	# 如果经验满了 -> 升级
	if GameData.current_exp >= needed:
		_level_up()

func _level_up():
	GameData.current_level += 1
	GameData.current_exp = 0.0
	
	print("[Main] 升级了！当前等级: ", GameData.current_level)
	SignalBus.on_level_up.emit(GameData.current_level)
	
	# 👉【Demo 已关闭】不再自动通关，你可以一直玩下去测试了
	# if GameData.current_level >= 3:
	# 	print("[Main] 🌲 恭喜通关当前年轮！正在解锁下一个年轮周期并返回...")
	# 	if GameData.current_max_stage == GameData.current_playing_stage:
	# 		GameData.current_max_stage += 1 # 局外最大解锁数 +1
	# 	# 延迟1秒返回，让玩家看到升级
	# 	get_tree().create_timer(1.0).timeout.connect(func(): SignalBus.on_return_requested.emit())
	pass
		
func _on_skill_chosen(skill_id: String):
	print("[Main] 收到进化指令: ", skill_id)
	
	# 👉 对接到局外存储：记录这把在这一圈年轮上拿到的能力！
	GameData.record_skill_for_stage(GameData.current_playing_stage, skill_id)
	
	# 技能让树木变得更大，并暂时提升攻速！
	var tween = create_tween().set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	var target_scale = Vector2(2.0, 2.0) + Vector2(0.12, 0.12) * GameData.current_level
	tween.tween_property(tree, "scale", target_scale, 0.8)

	# 升级后让攻击变快一点，让玩家有正反馈
	if attack_timer.wait_time > 0.15:
		attack_timer.wait_time -= 0.05

# ── 打开升级选择 UI ─────────────────────────────────────────────
func _on_open_upgrade_ui():
	print("[Main] 升级UI请求：暂停攻击计时器")
	attack_timer.paused = true
	# UpgradeUI 自己监听 open_upgrade_ui 信号并显示，Main 不直接操作它

# ── 返回年轮主界面 ────────────────────────────────────────────────────
func _on_return_requested():
	print("[Main] 收到返回请求，正在退回年轮...")
	get_tree().change_scene_to_file("res://scenes/ui/AnnualRingMenu.tscn")

# ── 键盘快捷键 ─────────────────────────────────────────────────
func _input(event: InputEvent):
	# Escape 键暂时用作返回
	if event.is_action_pressed("ui_cancel"):
		SignalBus.on_return_requested.emit()

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
