extends Control

## 图片序列播放器 —— 完全绕开 Godot Theora 解码器
## 将视频帧导出为 JPEG 序列，运行时逐帧加载显示

@export var frames_folder: String  ## res:// 路径，如 "res://assets/开头/frames"
@export var frames_fps: float = 24.0
@export var audio_path: String
@export var next_scene_path: String
@export var auto_play: bool = true

@onready var display: TextureRect = $Display
@onready var audio_player: AudioStreamPlayer = $AudioStreamPlayer
@onready var skip_label: Label = $SkipLabel

var can_skip: bool = false
var playing: bool = false
var elapsed: float = 0.0
var current_frame_idx: int = -1
var total_frames: int = 0
var _display_texture: ImageTexture

func _ready():
	if skip_label:
		skip_label.modulate.a = 0.0

	AudioManager.stop_all()

	total_frames = _count_frames()
	print("[FramePlayer] 帧目录: %s, 检测到 %d 帧, FPS=%s" % [frames_folder, total_frames, frames_fps])

	if total_frames == 0:
		push_error("[FramePlayer] 未找到任何帧文件！路径: %s" % frames_folder)
		return

	if audio_path:
		audio_player.stream = load(audio_path)

	if auto_play:
		start_playback()

	await get_tree().create_timer(2.0).timeout
	can_skip = true
	if skip_label:
		create_tween().tween_property(skip_label, "modulate:a", 0.5, 1.0)


func _count_frames() -> int:
	var count := 0
	while true:
		var path := "%s/frame_%04d.jpg" % [frames_folder, count + 1]
		if not FileAccess.file_exists(path):
			break
		count += 1
	return count


func start_playback():
	await get_tree().process_frame
	playing = true
	elapsed = 0.0
	current_frame_idx = -1

	_show_frame(0)

	if audio_player.stream:
		audio_player.play()


func _process(delta: float):
	if not playing:
		return

	elapsed += delta
	var target := int(elapsed * frames_fps)

	if target >= total_frames:
		_transition_to_next()
		return

	if target != current_frame_idx:
		current_frame_idx = target
		_show_frame(current_frame_idx)


func _show_frame(index: int):
	var path := "%s/frame_%04d.jpg" % [frames_folder, index + 1]
	var file := FileAccess.open(path, FileAccess.READ)
	if not file:
		return

	var data := file.get_buffer(file.get_length())
	var image := Image.new()
	var err := image.load_jpg_from_buffer(data)
	if err != OK:
		return

	if _display_texture == null:
		_display_texture = ImageTexture.create_from_image(image)
		display.texture = _display_texture
	else:
		_display_texture.update(image)


func _input(event: InputEvent):
	if not can_skip:
		return

	if (event is InputEventMouseButton and event.pressed) or \
	   (event is InputEventKey and event.pressed):
		_transition_to_next()


func _transition_to_next():
	if not playing:
		return
	playing = false
	set_process_input(false)
	audio_player.stop()

	if next_scene_path != "":
		get_tree().change_scene_to_file(next_scene_path)
	else:
		push_error("[FramePlayer] 没有设置下一个场景路径！")
