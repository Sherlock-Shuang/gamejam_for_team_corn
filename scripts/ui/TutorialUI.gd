extends Control

@onready var close_button: Button = $Panel/VBoxContainer/CloseButton
@onready var instruction_panel: Panel = $Panel
@onready var hp_hint_panel: Panel = get_node_or_null("HpHintPanel")
@onready var skill_hint_panel: Panel = $SkillHintPanel
@onready var endless_hint_panel: Panel = $EndlessHintPanel
@onready var hp_close_button: Button = get_node_or_null("HpHintPanel/CloseButton")
@onready var skill_close_button: Button = $SkillHintPanel/VBox/CloseButton
@onready var endless_close_button: Button = $EndlessHintPanel/VBox/CloseButton

func _ready():
	# 初始状态
	modulate.a = 0
	visible = false
	if instruction_panel: instruction_panel.visible = false
	if hp_hint_panel: hp_hint_panel.visible = false
	if skill_hint_panel: skill_hint_panel.visible = false
	if endless_hint_panel: endless_hint_panel.visible = false
	
	# 如果是第一次进入第一关，显示教程
	if GameData.current_playing_stage == 1 and not GameData.is_endless_mode:
		if instruction_panel: instruction_panel.visible = true
		show_tutorial()
	elif GameData.is_endless_mode:
		if instruction_panel: instruction_panel.visible = false
		show_endless_hint()


func show_tutorial():
	visible = true
	get_tree().set_deferred("paused", true) # 延后一帧暂停，确保覆盖 Main.gd 的初始化
	var tween = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_property(self, "modulate:a", 1.0, 0.5)
	
	close_button.pressed.connect(_on_close_pressed)

func _on_close_pressed():
	# 第一阶段关闭，转场到 HP 提示
	var tween = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	if instruction_panel:
		tween.tween_property(instruction_panel, "modulate:a", 0.0, 0.3)
	await tween.finished
	if instruction_panel: instruction_panel.visible = false
	
	show_hp_hint()

func show_hp_hint():
	if not hp_hint_panel: 
		# 【补救逻辑】：如果专门的 HP 面板丢了，我们复用主面板来显示内容
		if instruction_panel:
			instruction_panel.visible = true
			instruction_panel.modulate.a = 1.0
			var title = instruction_panel.get_node_or_null("VBoxContainer/Title")
			var content_vbox = instruction_panel.get_node_or_null("VBoxContainer/ContentVBox")
			var close_btn = instruction_panel.get_node_or_null("VBoxContainer/CloseButton")
			
			if title: title.text = "—— 生命守护 ——"
			if content_vbox: content_vbox.visible = false # 隐藏之前的步骤
			
			# 动态创建一个简单的说明文字
			var temp_label = instruction_panel.get_node_or_null("VBoxContainer/TempHPLabel")
			if not temp_label:
				temp_label = Label.new()
				temp_label.name = "TempHPLabel"
				instruction_panel.get_node("VBoxContainer").add_child(temp_label)
				instruction_panel.get_node("VBoxContainer").move_child(temp_label, 2)
			
			temp_label.text = "请时刻注意屏幕下方的树木状态！\n生命值会随受伤而下降，\n若生命耗尽，森林将彻底陷入永夜。"
			temp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			temp_label.add_theme_font_size_override("font_size", 32)
			
			if close_btn:
				close_btn.text = "契约已成，扎根！"
				# 重新连接信号到关闭逻辑
				if close_btn.pressed.is_connected(_on_close_pressed):
					close_btn.pressed.disconnect(_on_close_pressed)
				if not close_btn.pressed.is_connected(_on_hp_hint_closed):
					close_btn.pressed.connect(_on_hp_hint_closed)
			return
		else:
			_on_hp_hint_closed()
			return
		
	hp_hint_panel.visible = true

	var tween = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_property(hp_hint_panel, "modulate:a", 1.0, 0.4)

	
	if not hp_close_button.pressed.is_connected(_on_hp_hint_closed):
		hp_close_button.pressed.connect(_on_hp_hint_closed)

func _on_hp_hint_closed():
	var tween = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	if hp_hint_panel:
		tween.tween_property(hp_hint_panel, "modulate:a", 0.0, 0.3)
		await tween.finished
		hp_hint_panel.visible = false
	visible = false
	get_tree().paused = false


func show_skill_hint():
	visible = true
	get_tree().set_deferred("paused", true)
	modulate.a = 1.0
	if skill_hint_panel:
		skill_hint_panel.visible = true
		var tween = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		tween.tween_property(skill_hint_panel, "modulate:a", 1.0, 0.4)
	
	if skill_close_button and not skill_close_button.pressed.is_connected(_on_skill_hint_closed):
		skill_close_button.pressed.connect(_on_skill_hint_closed)

func _on_skill_hint_closed():
	var tween = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_property(self, "modulate:a", 0.0, 0.3)
	await tween.finished
	visible = false
	get_tree().paused = false
	queue_free()


func show_endless_hint():
	visible = true
	get_tree().set_deferred("paused", true)
	modulate.a = 1.0
	if endless_hint_panel:
		endless_hint_panel.visible = true
		var tween = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		tween.tween_property(endless_hint_panel, "modulate:a", 1.0, 0.4)
	
	if endless_close_button and not endless_close_button.pressed.is_connected(_on_endless_hint_closed):
		endless_close_button.pressed.connect(_on_endless_hint_closed)

func _on_endless_hint_closed():
	var tween = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_property(self, "modulate:a", 0.0, 0.3)
	await tween.finished
	visible = false
	get_tree().paused = false
	queue_free()
