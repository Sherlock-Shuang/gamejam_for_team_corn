extends Control

@onready var close_button: Button = $Panel/VBoxContainer/CloseButton
@onready var instruction_panel: Panel = $Panel
@onready var hp_hint_panel: Panel = get_node_or_null("HpHintPanel")
@onready var skill_hint_panel: Panel = $SkillHintPanel
@onready var endless_hint_panel: Panel = $EndlessHintPanel

@onready var hp_close_button: Button = $HpHintPanel/VBox/CloseButton
@onready var skill_close_button: Button = $SkillHintPanel/VBox/CloseButton
@onready var endless_close_button: Button = $EndlessHintPanel/VBox/CloseButton

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

var _is_transitioning: bool = false

func _input(event: InputEvent) -> void:
	if not visible or _is_transitioning:
		return
	if (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT) or event.is_action_pressed("ui_accept"):
		get_viewport().set_input_as_handled()
		UiSoundManager._play_click_sound()
		if instruction_panel.visible:
			_on_close_pressed()
		elif hp_hint_panel.visible:
			_on_hp_hint_closed()
		elif skill_hint_panel.visible:
			_on_skill_hint_closed()
		elif endless_hint_panel.visible:
			_on_endless_hint_closed()

func show_tutorial():
	visible = true
	GameData.call_deferred("set_game_paused", true) # 延后一帧暂停，确保覆盖 Main.gd 的初始化
	var tween = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_property(self, "modulate:a", 1.0, 0.5)
	
	if not close_button.pressed.is_connected(_on_close_pressed):
		close_button.pressed.connect(_on_close_pressed)

func _on_close_pressed():
	if _is_transitioning: return
	_is_transitioning = true
	# 第一阶段关闭，转场到 HP 提示
	var tween = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_property(instruction_panel, "modulate:a", 0.0, 0.3)
	await tween.finished
	instruction_panel.visible = false
	_is_transitioning = false
	
	show_hp_hint()

func show_hp_hint():
	hp_hint_panel.visible = true
	hp_hint_panel.modulate.a = 0.0
	var tween = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_property(hp_hint_panel, "modulate:a", 1.0, 0.4)
	
	if not hp_close_button.pressed.is_connected(_on_hp_hint_closed):
		hp_close_button.pressed.connect(_on_hp_hint_closed)

func _on_hp_hint_closed():
	if _is_transitioning: return
	_is_transitioning = true
	var tween = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_property(hp_hint_panel, "modulate:a", 0.0, 0.3)
	await tween.finished
	hp_hint_panel.visible = false
	visible = false
	_is_transitioning = false
	GameData.set_game_paused(false)

func show_skill_hint():
	visible = true
	GameData.call_deferred("set_game_paused", true)
	modulate.a = 1.0
	skill_hint_panel.visible = true
	skill_hint_panel.modulate.a = 0.0
	var tween = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_property(skill_hint_panel, "modulate:a", 1.0, 0.4)
	
	if not skill_close_button.pressed.is_connected(_on_skill_hint_closed):
		skill_close_button.pressed.connect(_on_skill_hint_closed)

func _on_skill_hint_closed():
	if _is_transitioning: return
	_is_transitioning = true
	var tween = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_property(self, "modulate:a", 0.0, 0.3)
	await tween.finished
	visible = false
	_is_transitioning = false
	GameData.set_game_paused(false)
	queue_free()

func show_endless_hint():
	visible = true
	GameData.call_deferred("set_game_paused", true)
	modulate.a = 1.0
	endless_hint_panel.visible = true
	endless_hint_panel.modulate.a = 0.0
	var tween = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_property(endless_hint_panel, "modulate:a", 1.0, 0.4)
	
	if not endless_close_button.pressed.is_connected(_on_endless_hint_closed):
		endless_close_button.pressed.connect(_on_endless_hint_closed)

func _on_endless_hint_closed():
	if _is_transitioning: return
	_is_transitioning = true
	var tween = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_property(self, "modulate:a", 0.0, 0.3)
	await tween.finished
	visible = false
	_is_transitioning = false
	GameData.set_game_paused(false)
	queue_free()
