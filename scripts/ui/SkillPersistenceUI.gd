extends Control

@onready var container: Container = $FlowContainer

# 记录当前已显示的技能图标快照 { skill_id: Node }
var skill_slots = {}

func _ready():
	# 初始彻底清空容器
	for child in container.get_children():
		child.queue_free()
	skill_slots.clear()
	
	# 改为监听 on_skill_actived，这个信号在 SkillExecutor 增加等级后发出
	if SignalBus.on_skill_actived.is_connected(_on_skill_actived):
		SignalBus.on_skill_actived.disconnect(_on_skill_actived)
	SignalBus.on_skill_actived.connect(_on_skill_actived)
	
	# 延后一帧执行，确保 Main.gd 里的历史技能加载已经完成
	call_deferred("_refresh_historical_skills")

func _refresh_historical_skills():
	# 不要在这里 clear()，因为 _on_skill_actived 可能在 deferred 之前就被信号触发过了
	for skill_id in GameData.current_run_skill_ids:
		_on_skill_actived(skill_id)

const SKILL_SLOT_SCENE = preload("res://scenes/ui/SkillSlot.tscn")

func _on_skill_actived(skill_id: String):
	if not GameData.skill_pool.has(skill_id):
		return
		
	var level = GameData.get_skill_level(skill_id)
	if level <= 0: return
	
	if skill_slots.has(skill_id):
		# 更新已有项
		var slot = skill_slots[skill_id]
		var label = slot.find_child("LevelLabel", true, false)
		if label:
			label.text = "Lv." + str(level) + " "
		_play_update_effect(slot)
	else:
		# 创建新木框行
		var slot = _create_skill_slot(skill_id, level)
		container.add_child(slot)
		skill_slots[skill_id] = slot

func _create_skill_slot(skill_id: String, level: int) -> Control:
	var slot = SKILL_SLOT_SCENE.instantiate()
	var icon_rect = slot.find_child("Icon", true, false)
	var name_label = slot.find_child("NameLabel", true, false)
	var level_label = slot.find_child("LevelLabel", true, false)
	
	var skill_name = GameData.skill_pool[skill_id].get("name", skill_id)
	name_label.text = skill_name
	level_label.text = "Lv." + str(level) + " "
	
	var icons_map = {
		"thorn_shot": "res://assets/sprites/effects/毒刺.png",
		"exploding_fruit": "res://assets/sprites/effects/爆炸果.png",
		"lightning_field": "res://assets/sprites/effects/flash1.png",
		"vine_spread": "res://assets/sprites/effects/4rattan.png",
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
	
	var icon_path = icons_map.get(skill_id, "")
	if icon_path != "":
		icon_rect.texture = load(icon_path)
	
	# 设置锚点枢轴，以便缩放动画
	slot.pivot_offset = Vector2(140, 25)
	
	return slot

func _play_update_effect(node):
	var tween = create_tween()
	tween.tween_property(node, "scale", Vector2(1.1, 1.1), 0.1)
	tween.tween_property(node, "scale", Vector2.ONE, 0.2)
