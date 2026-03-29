extends Sprite2D

func _ready():
    # 刚出生时：缩到很小（0.1倍），稍微带点透明
    scale = Vector2(0.1, 0.1) 
    modulate.a = 0.8 
    
    var tween = create_tween().set_parallel(true)
    
    # 1. 扩散：用 2.0 秒放大到一个合适的尺寸（这里暂定 0.5 倍，你可以根据图片大小自己调）
    tween.tween_property(self, "scale", Vector2(0.5, 0.5), 2.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
    
    # 2. 消失：用 2.0 秒慢慢隐形
    tween.tween_property(self, "modulate:a", 0.0, 2.0)
    
    tween.chain().tween_callback(queue_free)