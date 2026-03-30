extends Control

@onready var anim_player: AnimationPlayer = $AnimationPlayer
@onready var close_button: Button = $Panel/CloseButton
@onready var instruction_panel: Panel = $Panel
@onready var hp_hint_panel: Panel = $HpHintPanel
@onready var skill_hint_panel: Panel = $SkillHintPanel
@onready var endless_hint_panel: Panel = $EndlessHintPanel
@onready var hp_close_button: Button = $HpHintPanel/CloseButton
@onready var skill_close_button: Button = $SkillHintPanel/CloseButton
@onready var endless_close_button: Button = $EndlessHintPanel/CloseButton

func _ready():
	# 初始状态
	modulate.a = 0
	visible = false
	instruction_panel.visible = false
	hp_hint_panel.visible = false
	skill_hint_panel.visible = false
	endless_hint_panel.visible = false
	
	# 如果是第一次进入第一关，显示教程
	if GameData.current_playing_stage == 1 and not GameData.is_endless_mode:
		instruction_panel.visible = true
		show_tutorial()
	elif GameData.is_endless_mode:
		instruction_panel.visible = false
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
	tween.tween_property(instruction_panel, "modulate:a", 0.0, 0.3)
	await tween.finished
	instruction_panel.visible = false
	
	show_hp_hint()

func show_hp_hint():
	hp_hint_panel.visible = true
	var tween = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_property(hp_hint_panel, "modulate:a", 1.0, 0.4)
	
	if not hp_close_button.pressed.is_connected(_on_hp_hint_closed):
		hp_close_button.pressed.connect(_on_hp_hint_closed)

func _on_hp_hint_closed():
	var tween = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_property(hp_hint_panel, "modulate:a", 0.0, 0.3)
	await tween.finished
	hp_hint_panel.visible = false
	visible = false
	get_tree().paused = false

func show_skill_hint():
	visible = true
	get_tree().set_deferred("paused", true)
	modulate.a = 1.0
	skill_hint_panel.visible = true
	var tween = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_property(skill_hint_panel, "modulate:a", 1.0, 0.4)
	
	if not skill_close_button.pressed.is_connected(_on_skill_hint_closed):
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
	endless_hint_panel.visible = true
	var tween = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_property(endless_hint_panel, "modulate:a", 1.0, 0.4)
	
	if not endless_close_button.pressed.is_connected(_on_endless_hint_closed):
		endless_close_button.pressed.connect(_on_endless_hint_closed)

func _on_endless_hint_closed():
	var tween = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_property(self, "modulate:a", 0.0, 0.3)
	await tween.finished
	visible = false
	get_tree().paused = false
	queue_free()
