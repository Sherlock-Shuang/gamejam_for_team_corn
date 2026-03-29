extends Area2D

@onready var polygon_node: CollisionPolygon2D = $CollisionPolygon2D

func _ready() -> void:
    # 游戏一加载，就把画好的多边形坐标强行塞进 GameData 的信箱里！
    GameData.river_polygon = polygon_node.polygon
    GameData.river_transform = global_transform