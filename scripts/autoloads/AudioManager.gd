extends Node

enum Bus {
	MASTER,
	MUSIC,
	SFX,
}

const MUSIC_BUS = "Music"
const SFX_BUS = "SFX"

## 音乐播放器配置
## 音乐播放器的个数
var music_audio_player_count: int = 2
## 当前播放音乐的播放器的序号，默认是0
var current_music_player_index: int = 0
## 音乐播放器存放的数组，方便调用
var music_players: Array[AudioStreamPlayer]
## 音乐渐变时长
var music_fade_duration:float = 1.0

## 音效播放器的个数
var sfx_audio_player_count: int = 32
## 音效播放器存放的数组，方便调用
var sfx_players: Array[AudioStreamPlayer]

func _ready() -> void:
	print("[声音管理器]: 加载完成")
	init_music_audio_manager()
	init_sfx_audio_manager()

## 初始化音乐播放器
func init_music_audio_manager() -> void:
	for i in music_audio_player_count:
		var audio_player := AudioStreamPlayer.new()
		audio_player.process_mode = Node.PROCESS_MODE_ALWAYS
		audio_player.bus = MUSIC_BUS
		add_child(audio_player)
		music_players.append(audio_player)

## 播放指定音乐
func play_music(_audio: AudioStream, start_time: float = 0) -> void:
	var current_audio_player := music_players[current_music_player_index]
	if current_audio_player.stream == _audio:
		return
	var empty_audio_player_index = 0 if current_music_player_index == 1 else 1
	var empty_audio_player := music_players[empty_audio_player_index]
	# 渐入
	empty_audio_player.stream = _audio
	play_and_fade_in(empty_audio_player, start_time)
	# 渐出
	fade_out_and_stop(current_audio_player)
	current_music_player_index = empty_audio_player_index


## 渐入
func play_and_fade_in(_audio_player: AudioStreamPlayer, start_time: float = 0.0) -> void:
	# 播放前先强行拉到绝对静音，防止开局炸耳
	_audio_player.volume_db = -80.0 
	_audio_player.play(start_time)
	var tween: Tween = create_tween()
	tween.tween_property(_audio_player, "volume_db", 0.0, music_fade_duration)

## 渐出
func fade_out_and_stop(_audio_player: AudioStreamPlayer) -> void:
	var tween: Tween = create_tween()
	# 降到 -80.0 dB 才是真正的彻底静音
	tween.tween_property(_audio_player, "volume_db", -80.0, music_fade_duration) 
	await tween.finished
	_audio_player.stop()
	_audio_player.stream = null

## 初始化音效播放器
func init_sfx_audio_manager() -> void:
	for i in sfx_audio_player_count:
		var audio_player := AudioStreamPlayer.new()
		audio_player.bus = SFX_BUS
		
		# 👇 【关键修复】：允许音效在 get_tree().paused = true 时继续播放
		audio_player.process_mode = Node.PROCESS_MODE_ALWAYS 
		
		add_child(audio_player)
		sfx_players.append(audio_player)

## 播放指定音效 (新增了 max_instances 限制同屏最大数量)
func play_sfx(_audio: AudioStream, volume_db: float = 0.0, _is_random_pitch: bool = false, max_instances: int = 0, start_time: float = 0) -> void:
	
	# 🔥【新增逻辑】：防爆音拦截器
	# 如果设置了最大数量限制，先检查当前有几个播放器正在播这个特定音效
	if max_instances > 0:
		var current_playing_count = 0
		for player in sfx_players:
			if player.playing and player.stream == _audio:
				current_playing_count += 1
		
		# 如果已经有 >= 3（或你设定的数字）个同款声音在播放，直接静默丢弃这次请求！
		if current_playing_count >= max_instances:
			return 

	# ----- 下面的逻辑保持不变 -----
	var pitch := 1.0
	if _is_random_pitch:
		pitch = randf_range(0.9, 1.1)
		
	var oldest_player: AudioStreamPlayer = null
	var longest_playing_time: float = -1.0
	
	for i in sfx_audio_player_count:
		var sfx_audio_player := sfx_players[i]
		
		if not sfx_audio_player.playing:
			sfx_audio_player.stream = _audio
			sfx_audio_player.volume_db = volume_db
			sfx_audio_player.pitch_scale = pitch
			sfx_audio_player.play(start_time)
			return 
			
		var current_play_pos = sfx_audio_player.get_playback_position()
		if current_play_pos > longest_playing_time:
			longest_playing_time = current_play_pos
			oldest_player = sfx_audio_player
			
	if oldest_player:
		oldest_player.stop() 
		oldest_player.stream = _audio
		oldest_player.volume_db = volume_db
		oldest_player.pitch_scale = pitch
		oldest_player.play(start_time)

## 停止所有声音 (用于大结局或特殊场转)
func stop_all() -> void:
	for player in music_players:
		player.stop()
		player.stream = null
	for player in sfx_players:
		player.stop()
		player.stream = null
