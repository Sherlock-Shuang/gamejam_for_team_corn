extends Control
@export var 前置_bgm: AudioStream
@export var 点击_sfx: AudioStream
# 👉 这里填入你真正的游戏主界面路径（比如之前的年轮选关界面）
@export var next_scene_path: String = "res://scenes/ui/IntroScene.tscn"
@onready var logo = $TextureRect
@onready var prompt_label = $Label

var can_skip: bool = false

func _ready():
	# 🎵 新增：游戏一启动，立刻让管家播放前置音乐！
	if 前置_bgm:
		AudioManager.play_music(前置_bgm)
		
	# 初始状态：让 Logo 和提示文字完全透明
	logo.modulate.a = 0.0
	# 初始状态：让 Logo 和提示文字完全透明
	logo.modulate.a = 0.0
	if prompt_label:
		prompt_label.modulate.a = 0.0
	
	# 创建一个 Tween 动画器，让 Logo 花 1.5 秒丝滑淡入
	var tween = create_tween()
	tween.tween_property(logo, "modulate:a", 1.0, 1.5).set_trans(Tween.TRANS_SINE)
	
	# 接着让提示文字花 1.0 秒淡入
	if prompt_label:
		tween.tween_property(prompt_label, "modulate:a", 1.0, 1.0)
		
	# 为了防止游戏刚启动玩家不小心碰到键盘瞬间跳过，设置 0.5 秒的防误触保护
	await get_tree().create_timer(0.5).timeout
	can_skip = true

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
