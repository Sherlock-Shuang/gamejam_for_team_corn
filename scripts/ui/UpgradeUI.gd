extends CanvasLayer
# ═══════════════════════════════════════════════════════════════
#  UpgradeUI.gd — 三选一升级弹窗
#  监听 SignalBus.on_level_up，弹出技能选择面板
# ═══════════════════════════════════════════════════════════════

@onready var card_container: HBoxContainer = $CenterContainer/VBoxContainer/HBoxContainer
@onready var title_label: Label = $CenterContainer/VBoxContainer/TitleLabel

func _ready():
	hide()
	
	# 监听升级信号 → 自动弹出面板
	if SignalBus.on_level_up.is_connected(_on_level_up):
		SignalBus.on_level_up.disconnect(_on_level_up)
	SignalBus.on_level_up.connect(_on_level_up)

func _on_level_up(_new_level: int):
	show_upgrade()

func show_upgrade():
	get_tree().paused = true
	show()
	
	var cards = card_container.get_children()
	var choices = GameData.get_random_skills(cards.size())
	
	for i in range(cards.size()):
		var card = cards[i] as Button
		var skill_data = choices[i]
		
		# 填充卡牌内容
		var name_label = card.get_node("CardContent/NameLabel") as Label
		var category_label = card.get_node("CardContent/CategoryLabel") as Label
		var desc_label = card.get_node("CardContent/DescLabel") as Label
		
		name_label.text = skill_data["name"]
		category_label.text = "[" + skill_data["category"] + "]"
		desc_label.text = skill_data["description"]
		
		# 绑定点击事件
		var callable = _on_card_selected.bind(skill_data["id"])
		for connection in card.pressed.get_connections():
			card.pressed.disconnect(connection["callable"])
		card.pressed.connect(callable)

func _on_card_selected(skill_id: String):
	print("[UpgradeUI] 选择了技能: ", skill_id)
	SignalBus.on_upgrade_selected.emit(skill_id)
	hide()
	get_tree().paused = false
