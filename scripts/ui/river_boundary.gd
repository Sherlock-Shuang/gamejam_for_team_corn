extends Area2D

@onready var polygon_node: CollisionPolygon2D = $CollisionPolygon2D
@export var ripple_scene: PackedScene 

var rect_min = Vector2.INF
var rect_max = Vector2(-INF, -INF)

func _ready() -> void:
    GameData.river_polygon = polygon_node.polygon
    GameData.river_transform = global_transform

    if not polygon_node.polygon.is_empty():
        _calculate_bounds()
        _start_ripple_spawner()

func _calculate_bounds():
    for p in polygon_node.polygon:
        rect_min.x = min(rect_min.x, p.x)
        rect_min.y = min(rect_min.y, p.y)
        rect_max.x = max(rect_max.x, p.x)
        rect_max.y = max(rect_max.y, p.y)

func _start_ripple_spawner():
    var timer = Timer.new()
    # 👇【修改点 1】：大幅提高频率！每 0.15 秒就会吐出一个波纹（一秒钟大概 6~7 个）
    timer.wait_time = 0.15 
    timer.autostart = true
    timer.timeout.connect(_spawn_ripple)
    add_child(timer)

func _spawn_ripple():
    if not ripple_scene or polygon_node.polygon.is_empty(): return

    var random_point = Vector2.ZERO
    var found = false
    
    # 算出河流边界往下压的安全线（忽略多边形上半部分 30% 的区域）
    # 这样波纹就绝对不会碰到上方的土地了
    var safe_water_y = lerpf(rect_min.y, rect_max.y, 0.1) 

    for i in range(20):
        # X 轴依然横跨整条河
        random_point.x = randf_range(rect_min.x, rect_max.x)
        # 👇【修改点 2】：Y 轴强制从 safe_water_y 开始往下随机，死死锁在屏幕下方！
        random_point.y = randf_range(safe_water_y, rect_max.y)
        
        if Geometry2D.is_point_in_polygon(random_point, polygon_node.polygon):
            found = true
            break 

    if found:
        var ripple = ripple_scene.instantiate()
        ripple.position = random_point
        ripple.rotation = 0 # 绝对不旋转，保持水平透视
        polygon_node.add_child(ripple)