extends Node

var UI交互_sfx :AudioStream = preload("res://assets/audio/sfx/UI交互3.wav")

func _ready() -> void:
    process_mode = Node.PROCESS_MODE_ALWAYS

func _enter_tree() -> void:
    get_tree().node_added.connect(_on_node_added)

func _on_node_added(node: Node) -> void:
    if node is BaseButton:
        if node.is_in_group("silent_ui"):
            return
            
        if not node.button_down.is_connected(_play_click_sound):
            node.button_down.connect(_play_click_sound)

func _play_click_sound() -> void:
    if UI交互_sfx:
        AudioManager.play_sfx(UI交互_sfx, 0.0, false, 2)
    else:
        # 加个保险打印，如果还是没声音，看控制台有没有这句红字
        printerr("⚠️ 警告：UI交互音效没有被正确加载，请检查 preload 里的文件路径！")