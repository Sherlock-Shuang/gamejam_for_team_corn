extends Node2D

var ready_time: int = 0
var start_time: float = 0.0

func _ready():
	ready_time = Time.get_ticks_msec()
	
	var forest_node = $Forest
	var trees = forest_node.get_children()
	var label = $UI/Label
	var hint = $UI/Hint
	
	# 初始状态：全部全透明
	label.modulate.a = 0.0
	hint.modulate.a = 0.0
	
	# 提取 Tree11 作为主角
	var tree_11 = forest_node.get_node("Tree11")
	
	# ── 阶段 1：中心神木觉醒 ──
	var intro_tw = create_tween()
	intro_tw.tween_property(tree_11, "modulate:a", 1.0, 1.5).set_trans(Tween.TRANS_SINE)
	
	# ── 阶段 2：万木齐发 ──
	var stagger_tw = create_tween()
	stagger_tw.set_parallel(true)
	var delay = 1.0
	for tree in trees:
		if tree == tree_11: continue
		stagger_tw.tween_property(tree, "modulate:a", 1.0, 1.0).set_delay(delay).set_trans(Tween.TRANS_SINE)
		delay += 0.3
	
	# ── 阶段 3：显示文字 ──
	var ui_tw = create_tween()
	ui_tw.tween_interval(delay + 0.5)
	ui_tw.tween_property(label, "modulate:a", 1.0, 2.0)
	ui_tw.tween_property(hint, "modulate:a", 0.7, 1.5)
	
	# ── 持续状态：背景微风摆动 ──
	var sway_tw = create_tween().set_loops()
	for tree in trees:
		var random_time = randf_range(2.0, 4.0)
		var random_rot = randf_range(-0.02, 0.02)
		sway_tw.parallel().tween_property(tree, "rotation", random_rot, random_time).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		sway_tw.parallel().tween_property(tree, "rotation", -random_rot, random_time).set_delay(random_time).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func _input(event):
	# 强制等待 3 秒，防止误触闪退
	if Time.get_ticks_msec() - ready_time < 3000:
		return
	if Time.get_ticks_msec() - start_time < 3000:
		return
		
	if event is InputEventMouseButton and event.pressed:
		get_tree().change_scene_to_file("res://scenes/ui/AnnualRingMenu.tscn")
	elif event is InputEventKey and event.pressed:
		get_tree().change_scene_to_file("res://scenes/ui/AnnualRingMenu.tscn")
