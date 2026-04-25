extends Control
@export var 前置_bgm: AudioStream
@export var 点击_sfx: AudioStream
# 👉 这里填入你真正的游戏主界面路径（比如之前的年轮选关界面）
@export var next_scene_path: String = "res://scenes/ui/IntroScene.tscn"
# 原路径: "res://scenes/ui/OpeningVideo.tscn"
@onready var logo = $TextureRect
@onready var prompt_label = $Label

var can_skip: bool = false

func _ready():
	# 🎵 显式加载队标，防止 UID 冲突导致显示默认图标
	logo.texture = load("res://assets/队标2.png")
	
	# 🎵 新增：游戏一启动，立刻让管家播放前置音乐！
	if 前置_bgm:
		AudioManager.play_music(前置_bgm)
		
	# 初始状态：让 Logo 和提示文字完全透明
	logo.modulate.a = 0.0
	if prompt_label:
		prompt_label.modulate.a = 0.0
	
	# 创建一个 Tween 动画器，让 Logo 花 1.5 秒丝滑淡入
	var tween = create_tween()
	tween.tween_property(logo, "modulate:a", 1.0, 1.5).set_trans(Tween.TRANS_SINE)
	
	# 等待 2 秒后显示提示文字并开始闪烁
	await get_tree().create_timer(2.0).timeout
	if prompt_label:
		prompt_label.modulate.a = 1.0
		_start_blinking()
		
	# 两秒后允许跳过
	can_skip = true

func _start_blinking():
	if not prompt_label:
		return
	var blink_tween = create_tween().set_loops()
	blink_tween.tween_property(prompt_label, "modulate:a", 0.0, 1.0).set_trans(Tween.TRANS_SINE)
	blink_tween.tween_property(prompt_label, "modulate:a", 1.0, 1.0).set_trans(Tween.TRANS_SINE)

func _input(event):
	if not can_skip:
		return
		
	# 监听：鼠标按键、键盘按键、手柄按键
	if (event is InputEventMouseButton and event.pressed) or \
	   (event is InputEventKey and event.pressed) or \
	   (event is InputEventJoypadButton and event.pressed):
		
		can_skip = false # 立刻关闭跳过许可，防止玩家疯狂连点导致报错
		_transition_to_next()

func _transition_to_next():
	# 切换到下一个场景
	print("[Splash] 玩家点击，进入主菜单！")
	
	# 🎵 新增：呼叫大管家播放点击音效！
	# 参数：音效文件, 音量(0正常), 是否循环(false), 音调(1.0正常)
	if 点击_sfx:
		AudioManager.play_sfx(点击_sfx, 0.0, false, 1.0)
	print("[Splash] 玩家点击，进入主菜单！")
	get_tree().change_scene_to_file(next_scene_path)
