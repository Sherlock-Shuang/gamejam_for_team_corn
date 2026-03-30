extends CanvasLayer
# ═══════════════════════════════════════════════════════════════
#  UpgradeUI.gd — 三选一升级弹窗
#  监听 SignalBus.on_level_up，弹出技能选择面板
# ═══════════════════════════════════════════════════════════════

@onready var root_node: Control = $Root
@onready var card_container: HBoxContainer = $Root/CenterContainer/VBoxContainer/HBoxContainer
@onready var title_label: Label = $Root/CenterContainer/VBoxContainer/TitleLabel

# 创建全局卡片样式
var style_normal: StyleBoxFlat
var style_hover: StyleBoxFlat
var style_pressed: StyleBoxFlat

@export var 升级_sfx: AudioStream

func _ready():
	hide()
	
	# 初始化卡片材质
	_init_styles()
	_apply_styles_to_cards()
	
	# 监听升级信号 → 自动弹出面板
	if SignalBus.on_level_up.is_connected(_on_level_up):
		SignalBus.on_level_up.disconnect(_on_level_up)
	SignalBus.on_level_up.connect(_on_level_up)

func _init_styles():
	style_normal = StyleBoxFlat.new()
	style_normal.bg_color = Color(0.18, 0.14, 0.09, 1.0) # 深褐色木板
	style_normal.border_width_left = 6
	style_normal.border_width_top = 6
	style_normal.border_width_right = 6
	style_normal.border_width_bottom = 6
	style_normal.border_color = Color(0.35, 0.25, 0.15, 1.0)
	style_normal.corner_radius_top_left = 16
	style_normal.corner_radius_top_right = 16
	style_normal.corner_radius_bottom_right = 16
	style_normal.corner_radius_bottom_left = 16
	style_normal.shadow_color = Color(0.05, 0.03, 0.02, 1.0)
	style_normal.shadow_size = 1
	style_normal.shadow_offset = Vector2(8, 8)
	style_normal.anti_aliasing = false
	
	style_hover = style_normal.duplicate()
	style_hover.bg_color = Color(0.45, 0.35, 0.2, 1.0) # 悬停琥珀色
	style_hover.border_color = Color(0.7, 0.6, 0.4, 1.0)
	style_hover.shadow_offset = Vector2(16, 16)
	
	style_pressed = style_normal.duplicate()
	style_pressed.bg_color = Color(0.25, 0.18, 0.1, 1.0)
	style_pressed.shadow_offset = Vector2(0, 0)
	
func _apply_styles_to_cards():
	var empty_focus = StyleBoxEmpty.new()
	for card in card_container.get_children():
		if card is Button:
			card.add_theme_stylebox_override("normal", style_normal)
			card.add_theme_stylebox_override("hover", style_hover)
			card.add_theme_stylebox_override("pressed", style_pressed)
			card.add_theme_stylebox_override("focus", empty_focus)
			# 绑定悬停动效
			if not card.mouse_entered.is_connected(_on_card_hovered.bind(card)):
				card.mouse_entered.connect(_on_card_hovered.bind(card))
			if not card.mouse_exited.is_connected(_on_card_exited.bind(card)):
				card.mouse_exited.connect(_on_card_exited.bind(card))

			# 把内部文字颜色调得不那么“AI味”
			var name_label = card.get_node("CardContent/NameLabel") as Label
			var cat_label = card.get_node("CardContent/CategoryLabel") as Label
			var desc_label = card.get_node("CardContent/DescLabel") as Label
			name_label.add_theme_color_override("font_color", Color(0.95, 0.85, 0.55))
			name_label.add_theme_color_override("font_shadow_color", Color(0.1, 0.05, 0.02))
			name_label.add_theme_constant_override("shadow_offset_x", 3)
			name_label.add_theme_constant_override("shadow_offset_y", 3)
			cat_label.add_theme_color_override("font_color", Color(0.85, 0.7, 0.4))
			desc_label.add_theme_color_override("font_color", Color(0.85, 0.8, 0.7))

func _on_card_hovered(card: Button):
	var tween = create_tween()
	tween.tween_property(card, "scale", Vector2(1.05, 1.05), 0.1).set_trans(Tween.TRANS_SINE)

func _on_card_exited(card: Button):
	var tween = create_tween()
	tween.tween_property(card, "scale", Vector2(1.0, 1.0), 0.1).set_trans(Tween.TRANS_SINE)

func _on_level_up(_new_level: int):
	show_upgrade()

func show_upgrade():
	get_tree().paused = true
	show()

	# 👇 【新增：在这里播放升级提示音】
	if 升级_sfx:
		# 这里不需要随机音高，正常原声播放即可
		AudioManager.play_sfx(升级_sfx, 25)  # 音量可以根据需要调整
	root_node.modulate.a = 0.0
	var enter_tween = create_tween()
	enter_tween.tween_property(root_node, "modulate:a", 1.0, 0.3).set_trans(Tween.TRANS_CUBIC)
	
	var cards = card_container.get_children()
	var choices = GameData.get_random_skills(cards.size())

	if choices.is_empty():
		hide()
		get_tree().paused = false
		return
	
	for i in range(cards.size()):
		var card = cards[i] as Button
		# 重置属性
		card.scale = Vector2.ONE
		card.pivot_offset = card.size / 2.0
		
		# 飞入动画 (阶梯式)
		card.position.y = 200
		var float_tween = create_tween()
		float_tween.tween_interval(i * 0.1) # stagger
		float_tween.tween_property(card, "position:y", 0.0, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

		if i >= choices.size():
			card.disabled = true
			card.visible = false
			continue
			
		card.disabled = false
		card.visible = true
		var skill_data = choices[i]
		
		# 填充卡牌内容
		var name_label = card.get_node("CardContent/NameLabel") as Label
		var category_label = card.get_node("CardContent/CategoryLabel") as Label
		var desc_label = card.get_node("CardContent/DescLabel") as Label
		var current_level = int(skill_data.get("current_level", 0))
		var next_level = int(skill_data.get("next_level", current_level + 1))
		var route_title = str(skill_data.get("route_title", ""))
		
		name_label.text = skill_data["name"]
		name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART # 防止名字太长
		
		category_label.text = "[" + skill_data["category"] + "]  Lv." + str(current_level) + " → Lv." + str(next_level)
		if route_title != "":
			category_label.text += "  " + route_title
		category_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			
		desc_label.text = skill_data["description"]
		desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART # 解决描述超出边框
		
		# 绑定点击事件
		var callable = _on_card_selected.bind(skill_data["id"])
		for connection in card.pressed.get_connections():
			card.pressed.disconnect(connection["callable"])
		card.pressed.connect(callable)

func _on_card_selected(skill_id: String):
	print("[UpgradeUI] 选择了技能: ", skill_id)
	var exit_tween = create_tween()
	exit_tween.tween_property(root_node, "modulate:a", 0.0, 0.15)
	exit_tween.tween_callback(func():
		hide()
		SignalBus.on_upgrade_selected.emit(skill_id)
		get_tree().paused = false
	)
