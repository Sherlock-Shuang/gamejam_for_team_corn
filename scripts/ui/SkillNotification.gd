extends Control

@onready var icon_rect: TextureRect = $HBoxContainer/IconRect
@onready var name_label: Label = $HBoxContainer/NameLabel

func _ready():
	modulate.a = 0
	SignalBus.on_upgrade_selected.connect(_on_skill_acquired)

func _on_skill_acquired(payload: String):
	var data = GameData.decode_upgrade_payload(payload)
	var skill_id = data.get("skill_id", payload)
	
	if not GameData.skill_pool.has(skill_id):
		return
		
	var skill_data = GameData.skill_pool[skill_id]
	var skill_name = skill_data.get("name", skill_id)
	
	# 获取图标路径 (直接复用 AnnualRingMenu 里的逻辑或者 GameData 补全)
	var icon_path = _get_icon_path(skill_id)
	if icon_path != "":
		icon_rect.texture = load(icon_path)
	
	name_label.text = "获得技能: " + skill_name
	
	# 如果是本局第一个技能且是第一关，触发暂停指引
	if GameData.current_playing_stage == 1 and GameData.current_run_skill_ids.size() <= 1 and not GameData.is_restoring_history:
		_play_first_skill_hint()
	else:
		_play_animation()

func _play_first_skill_hint():
	_play_animation() # 继续播放原本的弹幕
	
	# 查找并触发大框教学
	var tutorial = get_tree().root.find_child("TutorialUI", true, false)
	if tutorial and tutorial.has_method("show_skill_hint"):
		tutorial.show_skill_hint()
	else:
		# 备用方案：如果没有 TutorialUI，就用简单的
		get_tree().paused = true
		await _wait_for_click()
		get_tree().paused = false

func _wait_for_click():
	# 简单的协程等待点击
	while true:
		if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			# 等待松开以防连带操作
			while Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
				await get_tree().process_frame
			return
		await get_tree().process_frame

func _get_icon_path(skill_id: String) -> String:
	# 这里逻辑可以写在 GameData 里更统一，但现在先写在这
	var icons = {
		"thorn_shot": "res://assets/sprites/effects/毒刺.png",
		"exploding_fruit": "res://assets/sprites/effects/爆炸果.png",
		"lightning_field": "res://assets/sprites/effects/flash1.png",
		"vine_spread": "res://assets/sprites/effects/vine.png",
		"seed_bomb": "res://assets/sprites/effects/种子.png",
		"fire_enchant": "res://assets/sprites/effects/4fruits.png",
		"ice_enchant": "res://assets/sprites/effects/flash3.png",
		"lightning_enchant": "res://assets/sprites/effects/electric.png",
		"thick_bark": "res://assets/sprites/trees/1h.png",
		"deep_roots": "res://assets/sprites/effects/4rattan.png",
		"wide_canopy": "res://assets/sprites/trees/1l.png",
		"elastic_trunk": "res://assets/sprites/trees/2h.png",
		"photosynthesis": "res://assets/sprites/effects/shade.png"
	}
	return icons.get(skill_id, "")

func _play_animation():
	var tween = create_tween()
	tween.set_parallel(true)
	
	# 初始位置微调
	position.y += 20
	
	# 淡入并上浮
	tween.tween_property(self, "modulate:a", 1.0, 0.4)
	tween.tween_property(self, "position:y", position.y - 20, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	
	# 停留一段时间
	tween.set_parallel(false)
	tween.tween_interval(2.0)
	
	# 淡出
	tween.set_parallel(true)
	tween.tween_property(self, "modulate:a", 0.0, 0.6)
	tween.tween_property(self, "position:y", position.y - 40, 0.6)
