extends Node
# ═══════════════════════════════════════════════════════════════
#  GameData.gd — 全局数据中心 (Autoload 单例)
#  所有游戏数值集中管理，策划改一个数字就能影响全局。
# ═══════════════════════════════════════════════════════════════

# ── 局内运行时状态 (单局游戏) ──
var current_level: int = 1
var current_exp: float = 0.0
var current_hp: float = 100.0
var current_wave: int = 0
var current_run_skill_ids: Array[String] = []
var current_run_skill_levels: Dictionary = {}
var current_run_skill_route_bonus: Dictionary = {}
var current_run_skill_route_history: Dictionary = {}

# --- 局外进度状态 (年轮界面) ──
var current_max_stage: int = 1                         # 当前解锁的最大关卡数（年轮数）
var skill_history_per_stage: Dictionary = {}           # 格式: { stage_id : [ "skill_a", "skill_b" ] }
var current_playing_stage: int = 1                     # 玩家当前正在挑战哪一关
var is_endless_unlocked: bool = false                  # 是否解锁无尽模式
var is_endless_mode: bool = false                      # 当前是否在打无尽模式
var selected_sapling: int = 1                          # 无尽模式下选择的形态
var is_restoring_history: bool = false                 # 是否正在加载历史技能（加载时不应再次存档）
var just_finished_final_stage: bool = false            # 【剧情专用】是否刚刚打通第四关回到菜单
var has_seen_endless_intro: bool = false               # 无尽模式字幕是否已看过
var endless_time: float = 0.0                          # 无尽模式已运行的总时长
var is_in_ending_cinematic: bool = false               # 是否正在播放结局动画

## 获取无尽模式下的属性增强倍率 (每 10 秒增加 10%)
func get_endless_multiplier() -> float:
	if not is_endless_mode: return 1.0
	# 阶梯式增长：10s(1.1x), 20s(1.2x), 30s(1.3x)...
	return 1.0 + floor(endless_time / 10.0) * 0.05



const SAVE_PATH = "user://tree_survivor_save.json"
const MAX_STAGES = 4
const RIVER_Y_THRESHOLD: float = 200.0

# 👇【新增】：用于存储不规则河流边界的数据
var river_polygon: PackedVector2Array = []
var river_transform: Transform2D = Transform2D()

func _ready():
	load_game()

# --- 存档系统 ---
func save_game():
	var file = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file:
		var data = {
			"current_max_stage": current_max_stage,
			"skill_history_per_stage": skill_history_per_stage,
			"is_endless_unlocked": is_endless_unlocked
		}
		file.store_string(JSON.stringify(data))

func load_game():
	if FileAccess.file_exists(SAVE_PATH):
		var file = FileAccess.open(SAVE_PATH, FileAccess.READ)
		if file:
			var content = file.get_as_text()
			var json = JSON.new()
			var error = json.parse(content)
			if error == OK:
				var data = json.get_data()
				if typeof(data) == TYPE_DICTIONARY:
					current_max_stage = data.get("current_max_stage", 1)
					is_endless_unlocked = data.get("is_endless_unlocked", false)
					
					var saved_history = data.get("skill_history_per_stage", {})
					skill_history_per_stage.clear()
					for k in saved_history.keys():
						# JSON 解析的 key 必然是字符串，转回 int
						var stage_id = k.to_int()
						if stage_id != 99:
							skill_history_per_stage[stage_id] = saved_history[k]



# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#  玩家基础属性
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
const DEFAULT_PLAYER_BASE_STATS: Dictionary = {
	"max_hp": 100.0,
	"attack_power": 10.0,
	"attack_range": 1.0,   # 倍率
	"attack_speed": 1.0,   # 倍率
	"hp_regen": 0.0,       # 每秒恢复
	"move_speed": 1.0,     # 倍率
	"skill_damage_mult": 1.0, # 全局技能伤害倍率 (光合强化等触发)
}


var player_base_stats: Dictionary = DEFAULT_PLAYER_BASE_STATS.duplicate(true)

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#  成长阶段 (幼苗 → 小树 → 大树 → 神木)
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
var growth_stages: Array = [
	{"name": "幼苗", "level_threshold": 1,  "scale_mult": 1.0, "base_damage_bonus": 0.0,  "description": "攻速快但范围小"},
	{"name": "小树", "level_threshold": 5,  "scale_mult": 1.3, "base_damage_bonus": 10.0, "description": "初具规模"},
	{"name": "大树", "level_threshold": 12, "scale_mult": 1.7, "base_damage_bonus": 20.0, "description": "枝繁叶茂"},
	{"name": "神木", "level_threshold": 20, "scale_mult": 2.2, "base_damage_bonus": 35.0, "description": "附带地震效果"},
]

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#  经验值公式: 每级所需经验 = base * (level ^ exponent)
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
var exp_base: float = 50.0
var exp_exponent: float = 1.25

func get_exp_to_next_level(level: int) -> float:
	return exp_base * pow(level, exp_exponent)

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#  技能词条池 (三选一升级)
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
var skill_pool: Dictionary = {
	"thorn_shot": {
		"id": "thorn_shot",
		"name": "树毒匕首",
		"category": "衍生攻击",
		"description": "自动向最近的敌人发射毒刺，造成持续中毒伤害。",
		"icon": "",
		"max_level": 5,
		"effects": {"poison_damage": 20, "interval": 1.5, "pierce_count": 2, "projectile_count": 1, "speed_mult": 1.0, "launch_end_scale_x": 0.1, "launch_end_scale_y": 0.62},
		"level_effects": [
			{"poison_damage": 20, "interval": 1.5, "pierce_count": 5, "projectile_count": 1, "speed_mult": 1.0, "launch_end_scale_x": 0.1, "launch_end_scale_y": 0.62},
			{"poison_damage": 25, "interval": 1.2, "pierce_count": 6, "projectile_count": 2, "speed_mult": 1.0, "launch_end_scale_x": 0.1, "launch_end_scale_y": 0.62},
			{"poison_damage": 25, "interval": 0.9, "pierce_count": 7, "projectile_count": 3, "speed_mult": 1.0, "launch_end_scale_x": 0.1, "launch_end_scale_y": 0.62},
			{"poison_damage": 30, "interval": 0.6, "pierce_count": 9, "projectile_count": 4, "speed_mult": 2.0, "launch_end_scale_x": 0.1, "launch_end_scale_y": 0.62},
			{"poison_damage": 40, "interval": 0.5, "pierce_count": 10, "projectile_count": 5, "speed_mult": 2.0, "launch_end_scale_x": 0.1, "launch_end_scale_y": 0.62}
		],
		"level_descriptions": [
			"自动向最近敌人发射毒刺，可穿透多个目标。",
			"毒刺裂变为双发，穿透力与射速提升。",
			"三叉毒刺齐发，冷却大幅缩短。",
			"四连毒刺高速射出，毒性深入骨髓。",
			"毒刺风暴：五道剧毒飞针如暴雨般倾泻，贯穿一切。"
		],
		"upgrade_routes": [
			{"id": "damage_up", "title": "毒性强化", "description": "伤害提升", "effects": {"poison_damage": 8}},
			{"id": "cooldown_down", "title": "连发节奏", "description": "冷却缩短", "effects": {"interval": -0.2}},
			{"id": "multi_shot", "title": "分叉毒刺", "description": "额外发射1个投射物", "effects": {"projectile_count": 1}}
		]
	},
	"exploding_fruit": {
		"id": "exploding_fruit",
		"name": "酱爆",
		"category": "衍生攻击",
		"description": "定期抛射果实，落地后爆炸对范围内敌人造成伤害。",
		"icon": "",
		"max_level": 5,
		"effects": {"explosion_damage": 22, "radius": 300.0, "interval": 3.0, "cast_count": 1},
		"level_effects": [
			{"explosion_damage": 22, "radius": 300.0, "interval": 3.0, "cast_count": 1},
			{"explosion_damage": 32, "radius": 350.0, "interval": 3.0, "cast_count": 3},
			{"explosion_damage": 32, "radius": 410.0, "interval": 2.75, "cast_count": 5},
			{"explosion_damage": 38, "radius": 480.0, "interval": 2.2, "cast_count": 7},
			{"explosion_damage": 42, "radius": 560.0, "interval": 1.6, "cast_count": 9}
		],
		"level_descriptions": [
			"周期性向地面投掷爆裂果实，造成大范围爆炸。",
			"果实数量翻倍，爆炸半径与威力显著提升。",
			"果实数量增至3个，极大范围的高能爆破。",
			"果实产量惊人，连环爆炸几乎覆盖主战场。",
			"神木之赐：爆裂果实如雨点般落下，彻底净化森林。"
		],
		"upgrade_routes": [
			{"id": "radius_up", "title": "果实膨胀", "description": "判定半径提升", "effects": {"radius": 40.0}},
			{"id": "damage_up", "title": "爆压提升", "description": "爆炸伤害提升", "effects": {"explosion_damage": 10.0}},
			{"id": "cooldown_down", "title": "快速结果", "description": "冷却缩短", "effects": {"interval": -0.3}},
			{"id": "double_cast", "title": "双生果实", "description": "一次额外发射2个", "effects": {"cast_count": 2}}
		]
	},
	"lightning_field": {
		"id": "lightning_field",
		"name": "球状闪电",
		"category": "衍生攻击",
		"description": "投射缓慢移动的闪电球，扩散后形成短暂滞留电场。",
		"icon": "",
		"max_level": 5,
		"effects": {"explosion_damage": 20, "radius": 290.0, "interval": 3.5, "cast_count": 1, "cast_range_min": 150.0, "cast_range_max": 650.0, "speed_ratio": 0.4, "linger_duration": 0.4, "linger_scale_ratio": 0.06, "burst_overshoot_ratio": 1.1, "scale_settle_duration": 0.12},
		"level_effects": [
			{"explosion_damage": 16, "radius": 290.0, "interval": 3.5, "cast_count": 1, "cast_range_min": 150.0, "cast_range_max": 650.0, "speed_ratio": 0.4, "linger_duration": 0.1, "linger_scale_ratio": 0.018, "burst_overshoot_ratio": 1.1, "scale_settle_duration": 0.2},
			{"explosion_damage": 22, "radius": 340.0, "interval": 3.2, "cast_count": 1, "cast_range_min": 150.0, "cast_range_max": 700.0, "speed_ratio": 0.46, "linger_duration": 0.14, "linger_scale_ratio": 0.018, "burst_overshoot_ratio": 1.2, "scale_settle_duration": 0.18},
			{"explosion_damage": 26, "radius": 380.0, "interval": 2.8, "cast_count": 2, "cast_range_min": 150.0, "cast_range_max": 700.0, "speed_ratio": 0.48, "linger_duration": 0.2, "linger_scale_ratio": 0.019, "burst_overshoot_ratio": 1.2, "scale_settle_duration": 0.15},
			{"explosion_damage": 32, "radius": 440.0, "interval": 2.6, "cast_count": 3, "cast_range_min": 150.0, "cast_range_max": 750.0, "speed_ratio": 0.52, "linger_duration": 0.28, "linger_scale_ratio": 0.020, "burst_overshoot_ratio": 1.2, "scale_settle_duration": 0.12},
			{"explosion_damage": 40, "radius": 500.0, "interval": 2.3, "cast_count": 4, "cast_range_min": 150.0, "cast_range_max": 800.0, "speed_ratio": 0.55, "linger_duration": 0.35, "linger_scale_ratio": 0.020, "burst_overshoot_ratio": 1.2, "scale_settle_duration": 0.1}
		],
		"level_descriptions": [
			"投射缓慢移动的闪电球，扩散后形成短暂滞留电场。",
			"闪电球数量翻倍，电场范围与持续时间增加。",
			"电场进入超载状态，造成持续的高频雷击伤害。",
			"雷暴升级，产生的闪电球数量与电场范围显著增强。",
			"天谴：超载电场长时间滞留，大面积抹杀一切侵略者。"
		],
		"upgrade_routes": [
			{"id": "radius_up", "title": "电场扩容", "description": "判定半径提升", "effects": {"radius": 35.0}},
			{"id": "damage_up", "title": "电压过载", "description": "伤害提升", "effects": {"explosion_damage": 8.0}},
			{"id": "cooldown_down", "title": "导能提速", "description": "冷却缩短", "effects": {"interval": -0.18}},
			{"id": "double_cast", "title": "双星并发", "description": "一次额外发射1个", "effects": {"cast_count": 1}}
		]
	},
	"vine_spread": {
		"id": "vine_spread",
		"name": "触手形态",
		"category": "衍生攻击",
		"description": "在地表蔓延藤蔓，把一定数量的敌人拖进地下",
		"icon": "",
		"max_level": 5,
		"effects": {"target_count": 3, "search_radius": 350.0, "damage": 100.0, "interval": 4.0, "rise_duration": 0.22, "hold_duration": 0.2, "sink_duration": 0.4, "tentacle_peak_scale": 1.2, "tentacle_initial_scale_x": 0.3},
		"level_effects": [
			{"target_count": 4, "search_radius": 350.0, "damage": 100.0, "interval": 4.0, "rise_duration": 0.22, "hold_duration": 0.2, "sink_duration": 0.4, "tentacle_peak_scale": 1.2, "tentacle_initial_scale_x": 0.36},
			{"target_count": 5, "search_radius": 430.0, "damage": 145.0, "interval": 3.4, "rise_duration": 0.2, "hold_duration": 0.24, "sink_duration": 0.36, "tentacle_peak_scale": 1.28, "tentacle_initial_scale_x": 0.4},
			{"target_count": 6, "search_radius": 520.0, "damage": 205.0, "interval": 2.8, "rise_duration": 0.18, "hold_duration": 0.28, "sink_duration": 0.32, "tentacle_peak_scale": 1.36, "tentacle_initial_scale_x": 0.5},
			{"target_count": 8, "search_radius": 600.0, "damage": 280.0, "interval": 2.4, "rise_duration": 0.16, "hold_duration": 0.32, "sink_duration": 0.28, "tentacle_peak_scale": 1.45, "tentacle_initial_scale_x": 0.6},
			{"target_count": 10, "search_radius": 700.0, "damage": 400.0, "interval": 1.8, "rise_duration": 0.14, "hold_duration": 0.36, "sink_duration": 0.24, "tentacle_peak_scale": 1.55, "tentacle_initial_scale_x": 0.7}
		],
		"level_descriptions": [
			"在地表蔓延藤蔓，将附近的4名敌人拖进地下。",
			"数量上限增至5名，捕获范围与单次伤害提升。",
			"终极触手形态，一次性吞噬6名敌人，攻击频率大幅加快。",
			"捕获数量增至8名，藤蔓更粗壮且陷阱生效极快。",
			"大地的愤怒：地底触手疯狂伸展，瞬间吞没整支伐木工小队。"
		],
		"upgrade_routes": [
			{"id": "range_up", "title": "藤网扩张", "description": "扩大索敌范围", "effects": {"search_radius": 60.0}},
			{"id": "grab_up", "title": "缠绕增殖", "description": "可拖拽目标+1", "effects": {"target_count": 1}}
		]
	},
	"seed_bomb": {
		"id": "seed_bomb",
		"name": "播种",
		"category": "衍生攻击",
		"description": "播撒种子，短暂延迟后长出小树苗对周围敌人造成伤害。",
		"icon": "",
		"max_level": 5,
		"effects": {"sapling_damage": 12, "delay": 1.5, "interval": 3.5, "radius": 250.0, "damage_interval": 0.5, "lifetime": 8.0, "cast_range": 600.0, "fly_scale": 0.1, "grown_scale": 0.2, "grow_duration": 0.3},
		"level_effects": [
			{"sapling_damage": 10, "delay": 1.5, "interval": 3.5, "radius": 250.0, "damage_interval": 0.5, "lifetime": 8.0, "cast_range": 600.0, "fly_scale": 0.1, "grown_scale": 0.2, "grow_duration": 0.3},
			{"sapling_damage": 16, "delay": 1.2, "interval": 3.0, "radius": 300.0, "damage_interval": 0.45, "lifetime": 9.0, "cast_range": 640.0, "fly_scale": 0.11, "grown_scale": 0.24, "grow_duration": 0.26},
			{"sapling_damage": 22, "delay": 1.0, "interval": 2.5, "radius": 340.0, "damage_interval": 0.45, "lifetime": 10.0, "cast_range": 700.0, "fly_scale": 0.12, "grown_scale": 0.28, "grow_duration": 0.22},
			{"sapling_damage": 28, "delay": 0.8, "interval": 2.0, "radius": 400.0, "damage_interval": 0.4, "lifetime": 11.0, "cast_range": 760.0, "fly_scale": 0.14, "grown_scale": 0.35, "grow_duration": 0.18},
			{"sapling_damage": 36, "delay": 0.7, "interval": 1.6, "radius": 480.0, "damage_interval": 0.35, "lifetime": 12.0, "cast_range": 850.0, "fly_scale": 0.16, "grown_scale": 0.45, "grow_duration": 0.14}
		],
		"level_descriptions": [
			"由于树冠种子掉落，在地面长出带有尖刺的幼苗。",
			"幼苗生长时间缩短，毒性伤害与攻击半径提升。",
			"种子几乎瞬间着陆生长，形成一片致命的密林陷阱。",
			"小树苗毒性大增，几乎在落地瞬间就能长成并造成重创。",
			"神木化身：播撒出的种子瞬间形成参天大树，撕碎一切不敬之物。"
		],
		"upgrade_routes": [
			{"id": "damage_up", "title": "幼苗毒性", "description": "种子伤害提升", "effects": {"sapling_damage": 6.0}},
			{"id": "cooldown_down", "title": "播种提速", "description": "发射冷却缩短", "effects": {"interval": -0.18}}
		]
	},
	"fire_enchant": {
		"id": "fire_enchant",
		"name": "三昧",
		"category": "元素附魔",
		"description": "攻击附带火焰，使敌人持续燃烧3秒。",
		"icon": "",
		"max_level": 5,
		"effects": {"burn_dps": 4, "burn_duration": 3.0, "burn_interval": 0.4, "burn_tick_damage": 5.0},
		"level_effects": [
			{"burn_dps": 4, "burn_duration": 3.0, "burn_interval": 0.4, "burn_tick_damage": 5.0},
			{"burn_dps": 6, "burn_duration": 3.5, "burn_interval": 0.3, "burn_tick_damage": 7.0},
			{"burn_dps": 9, "burn_duration": 4.0, "burn_interval": 0.2, "burn_tick_damage": 9.0},
			{"burn_dps": 14, "burn_duration": 4.5, "burn_interval": 0.15, "burn_tick_damage": 12.0},
			{"burn_dps": 22, "burn_duration": 5.0, "burn_interval": 0.1, "burn_tick_damage": 16.0}
		],
		"level_descriptions": [
			"普攻赋予三昧真火，使敌人每秒承受高额灼烧。",
			"火焰穿透力增强，灼烧频率与持续时间增加。",
			"地狱之火，灼烧伤害呈指数级跳跃，快速灰化强敌。",
			"极温之焰：燃烧频率大幅提高，灼烧效果难以驱散。",
			"红莲地狱：所有受到攻击的敌人都会在极短时间内化为灰烬。"
		],
	},
	"ice_enchant": {
		"id": "ice_enchant",
		"name": "艾莎",
		"category": "元素附魔",
		"description": "攻击附带冰冻效果，减速敌人50%持续2秒。",
		"icon": "",
		"max_level": 5,
		"effects": {"slow_percent": 0.5, "slow_duration": 2.0},
		"level_effects": [
			{"slow_percent": 0.5, "slow_duration": 3.0},
			{"slow_percent": 0.58, "slow_duration": 3.5},
			{"slow_percent": 0.65, "slow_duration": 4.0},
			{"slow_percent": 0.73, "slow_duration": 4.8},
			{"slow_percent": 0.8, "slow_duration": 5.4}
		],
		"level_descriptions": [
			"为普攻注入极寒，造成50%减速效果。",
			"寒气扩散，减速效果持续时间增加。",
			"绝对零度，减速效果极大幅度提升，几乎冻结强敌。",
			"极寒加深：减速效果达到 75%，敌人动作变得极为迟钝。",
			"凝望深渊：近乎 90% 的停顿效果，将怪物的动作近乎冻结在时间中。"
		],
	},
	"lightning_enchant": {
		"id": "lightning_enchant",
		"name": "电动力学",
		"category": "元素附魔",
		"description": "攻击附带连锁闪电，跳跃至最多3个相邻敌人。",
		"icon": "",
		"max_level": 5,
		"effects": {"chain_damage": 5, "chain_count": 4},
		"level_effects": [
			{"chain_damage": 4, "chain_count": 4},
			{"chain_damage": 7, "chain_count": 7},
			{"chain_damage": 10, "chain_count": 10},
			{"chain_damage": 13, "chain_count": 14},
			{"chain_damage": 17, "chain_count": 20}
		],
		"level_descriptions": [
			"普攻产生连锁闪电，在4个敌人间跳跃。",
			"电弧分支增多，最多在7个目标间造成传导。",
			"雷神降世，单次攻击可传导至10个目标，伴随粗壮电弧。",
			"高压电弧：弹射14次，单次伤害显著提升。",
			"雷霆万钧：20次连锁弹射足以瞬间清空一片战场。"
		],
	},
	"thick_bark": {
		"id": "thick_bark",
		"name": "厚实树皮",
		"category": "基础数值",
		"description": "树干硬化，最大生命值 +20。",
		"icon": "",
		"max_level": 5,
		"effects": {"max_hp_bonus": 20, "trunk_width_mult": 1.2},
		"level_effects": [
			{"max_hp_bonus": 50, "trunk_width_mult": 1.3},
			{"max_hp_bonus": 100, "trunk_width_mult": 1.6},
			{"max_hp_bonus": 150, "trunk_width_mult": 1.9},
			{"max_hp_bonus": 250, "trunk_width_mult": 2.3},
			{"max_hp_bonus": 400, "trunk_width_mult": 2.8}
		],
		"level_descriptions": [
			"树皮增厚，生命值上限提升 50 点。",
			"生命上限提升 100 点，树体外观变得更加厚实。",
			"金刚外壳，生命上限提升 150 点，大幅度提高容错。",
			"地堡防御：生命上限增加 250 点，树干外观厚重如磐石。",
			"不灭神木：生命上限增加 450 点，任何物理攻击都难以撼动。"
		],
	},
	"deep_roots": {
		"id": "deep_roots",
		"name": "深扎根系",
		"category": "基础数值",
		"description": "根系深扎大地，每秒恢复2点生命。",
		"icon": "",
		"max_level": 5,
		"effects": {"hp_regen": 2.0, "root_scale_mult": 1.3},
		"level_effects": [
			{"hp_regen": 1.0, "root_scale_mult": 1.3},
			{"hp_regen": 3.0, "root_scale_mult": 1.79},
			{"hp_regen": 5.0, "root_scale_mult": 2.397},
			{"hp_regen": 7.0, "root_scale_mult": 3.2},
			{"hp_regen": 10.0, "root_scale_mult": 4.5}
		],
		"level_descriptions": [
			"根系稍微深扎，每秒恢复 1 点生命值。",
			"根系穿透岩层，回血速度翻倍，根系范围扩大。",
			"源源不断的生命力，极致自我修补速度。",
			"地脉共鸣：每秒恢复 8 点生命，扎根极深赋予无穷潜力。",
			"大地之子：肉眼可见的恐怖回血速度，只要不被秒杀就能瞬间重生。"
		],
	},
	"wide_canopy": {
		"id": "wide_canopy",
		"name": "宽阔树冠",
		"category": "基础数值",
		"description": "树冠扩展，攻击范围增加30%。",
		"icon": "",
		"max_level": 5,
		"effects": {"range_mult": 1.2, "canopy_sprite_mult": 1.2, "hitbox_shape_mult": 1.2},
		"level_effects": [
			{"range_mult": 1.2, "canopy_sprite_mult": 1.2, "hitbox_shape_mult": 1.2},
			{"range_mult": 1.44, "canopy_sprite_mult": 1.44, "hitbox_shape_mult": 1.44},
			{"range_mult": 1.728, "canopy_sprite_mult": 1.728, "hitbox_shape_mult": 1.728},
			{"range_mult": 2.15, "canopy_sprite_mult": 2.15, "hitbox_shape_mult": 2.15},
			{"range_mult": 2.8, "canopy_sprite_mult": 2.8, "hitbox_shape_mult": 2.8}
		],
		"level_descriptions": [
			"树冠向外舒展，攻击范围增加 20%。",
			"树冠进一步遮天蔽日，攻击半径大幅越迁。",
			"冠绝全林，极广阔的防御圈，将敌人阻隔在远方。",
			"遮天蔽日：攻击范围扩充至两倍以上，形成不可逾越的领域。",
			"远古巨木：整片森林皆在你的树冠笼罩之下，掌控局势。"
		],
	},
	"elastic_trunk": {
		"id": "elastic_trunk",
		"name": "弹性树干",
		"category": "基础数值",
		"description": "树干柔韧度大幅增强，形变拉伸极限增加！",
		"icon": "",
		"max_level": 5,
		"effects": {"stretch_scale_bonus": 0.5},
		"level_effects": [
			{"stretch_scale_bonus": 0.8},
			{"stretch_scale_bonus": 1.6},
			{"stretch_scale_bonus": 2.4},
			{"stretch_scale_bonus": 3.2},
			{"stretch_scale_bonus": 4.0}
		],
		"level_descriptions": [
			"树干弹性提升，形变拉伸极限增加 0.8。",
			"拉伸极限翻倍，反弹爆发力增强。",
			"如橡胶般柔韧，最大拉伸距离达至巅峰。",
			"超级纤维：树干可以进行极大幅度的弯曲和蓄力，爆发力惊人。",
			"时空回旋：极致的弹性让你在弹射瞬间如同撕裂空间，力道无穷。"
		],
	},
	"photosynthesis": {
		"id": "photosynthesis",
		"name": "光合强化",
		"category": "基础数值",
		"description": "增强光合作用，普攻提升25%，且每次升级都使其他全技能伤害提升20%。",
		"icon": "",
		"max_level": 5,
		"effects": {"attack_mult": 1.3},
		"level_effects": [
			{"attack_mult": 1.8},
			{"attack_mult": 2.7},
			{"attack_mult": 4.0},
			{"attack_mult": 6.2},
			{"attack_mult": 10.0}
		],
		"level_descriptions": [
			"光合效率提升，普攻提升80%，所有技能额外20%增益。",
			"光合作用过载，普攻倍率达 2.7x，全技能再次20%增幅。",
			"神木神迹，普攻伤害暴涨至 4.0x，全技能伤害叠乘至极限。",
			"超强效光合：普攻倍率达 6.2x，对所有技能的增益效果再次裂变。",
			"太阳神恩惠：普攻伤害狂增至 10.0x，你已成为森林中绝对的主宰。"
		],
	},
}

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#  敌人属性表
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
var enemy_stats: Dictionary = {
	# 第一阶段：自然虫害
	"beetle": {
		"name": "甲虫", "hp": 22, "speed": 120.0, "damage": 3.0,
		"exp_drop": 2.0, "phase": 1
	},
	# 第二阶段：哺乳动物
	"beaver": {
		"name": "河狸", "hp": 120, "speed": 60.0, "damage": 8.0,
		"exp_drop": 5.0, "phase": 2
	},
	# 第三阶段：人类
	"lumberjack": {
		"name": "伐木工", "hp": 300, "speed": 70.0, "damage": 9.0,
		"exp_drop": 8.0, "phase": 3
	},
	"mech_boss": {
		"name": "伐木机甲", "hp": 700, "speed": 60.0, "damage": 14.0,
		"exp_drop": 12.0, "phase": 3
	},
}

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#  波次时间表
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
var wave_table: Array = [
	# wave 1-3: 虫害阶段 (前3分钟，让玩家快速升级体验割草感)
	{"wave": 1, "duration": 30.0, "enemies": ["beetle"],               "spawn_interval": 1.5, "max_enemies": 20},
	{"wave": 2, "duration": 40.0, "enemies": ["beetle", "caterpillar"],"spawn_interval": 1.2, "max_enemies": 40},
	{"wave": 3, "duration": 50.0, "enemies": ["beetle", "caterpillar", "mosquito"], "spawn_interval": 1.0, "max_enemies": 60},
	# wave 4-6: 加入河狸
	{"wave": 4, "duration": 50.0, "enemies": ["caterpillar", "mosquito", "beaver"], "spawn_interval": 0.9, "max_enemies": 60},
	{"wave": 5, "duration": 60.0, "enemies": ["mosquito", "beaver"],  "spawn_interval": 0.8, "max_enemies": 70},
	{"wave": 6, "duration": 60.0, "enemies": ["beaver"],              "spawn_interval": 0.7, "max_enemies": 55},
	# wave 7-9: 人类阶段
	{"wave": 7, "duration": 60.0, "enemies": ["beaver", "lumberjack"],"spawn_interval": 0.8, "max_enemies": 60},
	{"wave": 8, "duration": 70.0, "enemies": ["lumberjack", "flamethrower"], "spawn_interval": 0.7, "max_enemies": 80},
	{"wave": 9, "duration": 80.0, "enemies": ["flamethrower", "lumberjack"], "spawn_interval": 0.6, "max_enemies": 90},
	# wave 10: Boss 波
	{"wave": 10, "duration": 90.0, "enemies": ["flamethrower", "mech_boss"], "spawn_interval": 2.0, "max_enemies": 50},
]

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#  工具方法
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

## 随机抽取 count 个不重复的技能
func get_random_skills(count: int = 3) -> Array:
	var unique_skill_ids: Array = []
	for s_id in skill_pool.keys():
		if can_upgrade_skill(s_id):
			unique_skill_ids.append(s_id)
	
	unique_skill_ids.shuffle()
	
	var result: Array = []
	var selected_count = mini(count, unique_skill_ids.size())
	
	for i in range(selected_count):
		var skill_id = unique_skill_ids[i]
		var routes = get_skill_upgrade_routes(skill_id)
		var cur_level = get_skill_level(skill_id)
		
		# 如果是新技能或者没有路线，直接作为候选
		if cur_level <= 0 or routes.is_empty():
			result.append(_build_upgrade_candidate(skill_id, ""))
		else:
			# 如果有路线，随机选一个路线作为该技能的本次展示项
			var random_route = routes.pick_random()
			result.append(_build_upgrade_candidate(skill_id, str(random_route.get("id", ""))))
			
	return result

func _build_upgrade_candidate(skill_id: String, route_id: String) -> Dictionary:
	var base = skill_pool[skill_id].duplicate(true)
	var current_level = get_skill_level(skill_id)
	var max_level = get_skill_max_level(skill_id)
	var next_level = mini(current_level + 1, max_level)
	var preview_effects = get_skill_effects(skill_id, next_level, route_id)
	var payload = encode_upgrade_payload(skill_id, route_id)
	var route_desc = ""
	if route_id != "":
		var route = get_skill_route(skill_id, route_id)
		if not route.is_empty():
			route_desc = str(route.get("title", route_id))
	base["id"] = payload
	base["skill_id"] = skill_id
	base["route_id"] = route_id
	base["route_title"] = route_desc
	base["current_level"] = current_level
	base["next_level"] = next_level
	base["max_level"] = max_level
	base["effects"] = preview_effects
	
	# 优先从字典预定义的等级描述中读取文字
	var level_descs = base.get("level_descriptions", [])
	if level_descs.size() >= next_level:
		base["description"] = "【 升级至 Lv.%d 】\n%s" % [next_level, level_descs[next_level-1]]
	elif current_level > 0:
		var current_effects = get_skill_effects(skill_id, current_level, route_id)
		var delta_text = _format_effect_delta(current_effects, preview_effects)
		base["description"] = "【 升级至 Lv.%d 】\n%s" % [next_level, delta_text]
	else:
		base["description"] = "【 获得新能力 】\n" + str(base.get("description", ""))
		
	return base




func register_current_run_skill(skill_id: String) -> int:
	var max_level = get_skill_max_level(skill_id)
	if max_level <= 0:
		return 0
	var next_level = mini(get_skill_level(skill_id) + 1, max_level)
	current_run_skill_levels[skill_id] = next_level
	if not current_run_skill_ids.has(skill_id):
		current_run_skill_ids.append(skill_id)
	return next_level

func apply_skill_upgrade(skill_id: String, route_id: String = "") -> Dictionary:
	var prev_level = get_skill_level(skill_id)
	if prev_level >= get_skill_max_level(skill_id):
		return {
			"skill_id": skill_id,
			"route_id": route_id,
			"prev_level": prev_level,
			"skill_level": prev_level,
			"effects": get_skill_effects(skill_id, prev_level),
			"prev_effects": get_skill_effects(skill_id, prev_level)
		}
	var prev_effects = get_skill_effects(skill_id, prev_level)
	var next_level = register_current_run_skill(skill_id)
	if route_id != "":
		_apply_route_bonus(skill_id, route_id)
	var next_effects = get_skill_effects(skill_id, next_level)
	return {
		"skill_id": skill_id,
		"route_id": route_id,
		"prev_level": prev_level,
		"skill_level": next_level,
		"effects": next_effects,
		"prev_effects": prev_effects
	}

func get_skill_level(skill_id: String) -> int:
	return int(current_run_skill_levels.get(skill_id, 0))

func get_skill_max_level(skill_id: String) -> int:
	if not skill_pool.has(skill_id):
		return 1
	return maxi(1, int(skill_pool[skill_id].get("max_level", 1)))

func can_upgrade_skill(skill_id: String) -> bool:
	return get_skill_level(skill_id) < get_skill_max_level(skill_id)

func get_skill_upgrade_routes(skill_id: String) -> Array:
	if not skill_pool.has(skill_id):
		return []
	var data = skill_pool[skill_id]
	if not data.has("upgrade_routes"):
		return []
	var routes = data["upgrade_routes"]
	if routes is Array:
		return routes
	return []

func get_skill_route(skill_id: String, route_id: String) -> Dictionary:
	var routes = get_skill_upgrade_routes(skill_id)
	for route in routes:
		if str(route.get("id", "")) == route_id:
			return route
	return {}

func _apply_route_bonus(skill_id: String, route_id: String) -> void:
	var route = get_skill_route(skill_id, route_id)
	if route.is_empty():
		return
	var route_eff = route.get("effects", {})
	if not current_run_skill_route_bonus.has(skill_id):
		current_run_skill_route_bonus[skill_id] = {}
	var bonus = current_run_skill_route_bonus[skill_id]
	for key in route_eff.keys():
		var value = route_eff[key]
		if typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT:
			bonus[key] = float(bonus.get(key, 0.0)) + float(value)
		else:
			bonus[key] = value
	current_run_skill_route_bonus[skill_id] = bonus
	if not current_run_skill_route_history.has(skill_id):
		current_run_skill_route_history[skill_id] = []
	current_run_skill_route_history[skill_id].append(route_id)

func get_skill_effects(skill_id: String, level: int = -1, preview_route_id: String = "") -> Dictionary:
	if not skill_pool.has(skill_id):
		return {}
	var query_level = level
	if query_level < 0:
		query_level = get_skill_level(skill_id)
	if query_level <= 0:
		return {}
	var data = skill_pool[skill_id]
	var effects: Dictionary = {}
	if data.has("level_effects"):
		var effects_array = data["level_effects"]
		if effects_array is Array and effects_array.size() > 0:
			var idx = clampi(query_level - 1, 0, effects_array.size() - 1)
			effects = effects_array[idx].duplicate(true)
	if effects.is_empty() and data.has("effects"):
		effects = data["effects"].duplicate(true)
	var bonus = current_run_skill_route_bonus.get(skill_id, {})
	for key in bonus.keys():
		var value = bonus[key]
		if typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT:
			effects[key] = float(effects.get(key, 0.0)) + float(value)
		else:
			effects[key] = value
	if preview_route_id != "":
		var route = get_skill_route(skill_id, preview_route_id)
		if not route.is_empty():
			var route_eff = route.get("effects", {})
			for key in route_eff.keys():
				var value = route_eff[key]
				if typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT:
					effects[key] = float(effects.get(key, 0.0)) + float(value)
				else:
					effects[key] = value
	if effects.has("interval"):
		effects["interval"] = maxf(0.2, float(effects["interval"]))
	if effects.has("cast_count"):
		effects["cast_count"] = maxi(1, int(effects["cast_count"]))
	if effects.has("projectile_count"):
		effects["projectile_count"] = maxi(1, int(effects["projectile_count"]))
	if effects.has("pierce_count"):
		effects["pierce_count"] = maxi(0, int(effects["pierce_count"]))
	return effects

func encode_upgrade_payload(skill_id: String, route_id: String = "") -> String:
	if route_id == "":
		return skill_id
	return skill_id + "::" + route_id

func decode_upgrade_payload(payload: String) -> Dictionary:
	var parts = payload.split("::")
	var skill_id = parts[0]
	var route_id = ""
	if parts.size() > 1:
		route_id = parts[1]
	return {"skill_id": skill_id, "route_id": route_id}

const EFFECT_KEY_NAMES: Dictionary = {
	"poison_damage": "毒伤",
	"interval": "冷却",
	"pierce_count": "穿透",
	"projectile_count": "弹道数",
	"speed_mult": "飞行速度",
	"explosion_damage": "爆炸伤害",
	"radius": "范围",
	"cast_count": "施放数",
	"chain_damage": "链伤",
	"chain_count": "弹射数",
	"burn_dps": "灼烧DPS",
	"burn_duration": "灼烧时长",
	"burn_interval": "灼烧频率",
	"burn_tick_damage": "单次灼烧",
	"slow_percent": "减速率",
	"slow_duration": "减速时长",
	"max_hp_bonus": "生命上限",
	"hp_regen": "每秒回血",
	"attack_mult": "攻击倍率",
	"range_mult": "范围倍率",
	"stretch_scale_bonus": "拉伸极限",
	"target_count": "目标数",
	"search_radius": "索敌范围",
	"damage": "伤害",
	"sapling_damage": "幼苗伤害",
	"lifetime": "持续时间",
	"damage_interval": "伤害频率",
	"cast_range": "施放距离",
}

func _format_effect_delta(before: Dictionary, after: Dictionary) -> String:
	var chunks: Array[String] = []
	for key in after.keys():
		var after_val = after[key]
		var before_val = before.get(key, null)
		if before_val == after_val:
			continue
		var display_name = EFFECT_KEY_NAMES.get(key, "")
		if display_name == "":
			continue
		if typeof(after_val) == TYPE_FLOAT or typeof(after_val) == TYPE_INT:
			if before_val == null:
				chunks.append("%s %.0f" % [display_name, float(after_val)])
			else:
				var delta = float(after_val) - float(before_val)
				if absf(delta) < 0.001:
					continue
				var sign = "+"
				if delta < 0.0:
					sign = ""
				chunks.append("%s %s%.0f" % [display_name, sign, delta])
		else:
			chunks.append("%s %s" % [display_name, str(after_val)])
	if chunks.is_empty():
		return "强化效果：数值保持不变"
	return "强化效果：" + ", ".join(chunks)

## 获取当前成长阶段
func get_current_growth_stage(level: int) -> Dictionary:
	var stage = growth_stages[0]
	for s in growth_stages:
		if level >= s["level_threshold"]:
			stage = s
	return stage

## 获取波次数据 (超出表范围则返回最后一波)
func get_wave_data(wave_number: int) -> Dictionary:
	if wave_number <= 0:
		return wave_table[0]
	if wave_number > wave_table.size():
		return wave_table[wave_table.size() - 1]
	return wave_table[wave_number - 1]

## 获取敌人属性
func get_enemy_stats(enemy_id: String) -> Dictionary:
	if enemy_stats.has(enemy_id):
		return enemy_stats[enemy_id]
	push_warning("GameData: 未知敌人 ID -> " + enemy_id)
	return {}
	
## 【调试用】重置所有进度
func reset_all_progress():
	current_max_stage = 1
	is_endless_unlocked = false
	skill_history_per_stage.clear()
	save_game()
	print("[GameData] 所有进度已重置。")

## 【调试用】解锁所有关卡与无尽模式
func unlock_all():
	current_max_stage = MAX_STAGES
	is_endless_unlocked = true
	save_game()
	print("[GameData] 所有关卡与无尽模式已解锁。")

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#  地形判定：不规则河流算法
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

func is_in_river(position: Vector2) -> bool:
	# 兜底：如果没画多边形，退回到旧版 Y 轴判定
	if river_polygon.is_empty():
		return position.y > RIVER_Y_THRESHOLD
		
	# 将世界坐标转换成多边形的本地坐标
	var local_pos = river_transform.affine_inverse() * position
	# 核心：调用上帝视角的几何引擎，瞬间算出点是否在多边形内！
	return Geometry2D.is_point_in_polygon(local_pos, river_polygon)

func clamp_to_river_bank(position: Vector2, padding: float = 0.0) -> Vector2:
	# 兜底：如果没画多边形，用旧版方式推回
	if river_polygon.is_empty():
		var safe_position = position
		var bank_y = RIVER_Y_THRESHOLD - absf(padding)
		if safe_position.y > bank_y:
			safe_position.y = bank_y
		return safe_position

	var local_pos = river_transform.affine_inverse() * position
	
	# 如果根本不在水里，直接返回原位置，啥也不用做
	if not Geometry2D.is_point_in_polygon(local_pos, river_polygon):
		return position 

	# 如果掉水里了，寻找距离它最近的一段河岸线
	var closest_dist: float = INF
	var closest_point: Vector2 = local_pos
	
	for i in range(river_polygon.size()):
		var p1 = river_polygon[i]
		var p2 = river_polygon[(i + 1) % river_polygon.size()]
		
		# 算出掉水里的点，到当前河岸线段的最短距离点
		var closest_on_segment = Geometry2D.get_closest_point_to_segment(local_pos, p1, p2)
		var dist = local_pos.distance_squared_to(closest_on_segment)
		if dist < closest_dist:
			closest_dist = dist
			closest_point = closest_on_segment

	# 算出推上岸的方向（从落水点指向最近的岸边）
	var out_dir = (closest_point - local_pos).normalized()
	if out_dir == Vector2.ZERO:
		out_dir = Vector2.UP # 万一重合，强制往上推
		
	# 推到岸边后，再往岸上多走一段安全距离 (padding)
	var final_local = closest_point + out_dir * absf(padding)
	
	# 转换回世界坐标还给系统
	return river_transform * final_local

# ==========================================
# (保留你原本在最底部的 record_skill_for_stage 等代码)

## 记录在某关获得的技能（同时保存技能等级，便于跨关恢复）
func record_skill_for_stage(stage_id: int):
	if is_restoring_history: return
	if is_endless_mode: return

	var snapshot = {}
	for sid in current_run_skill_ids:
		snapshot[sid] = get_skill_level(sid)
	skill_history_per_stage[stage_id] = snapshot
	print("[GameData] 已保存关卡 %d 的通关技能历史: " % stage_id, snapshot)
	save_game() 

## 将前几关的历史技能直接写入运行时数据（在 SkillExecutor 创建之前调用）
## SkillExecutor._sync_on_ready() 会自动读取并初始化
func apply_historical_skills():
	if is_endless_mode:
		return
	
	is_restoring_history = true
	print("[GameData] 正在从通关存档恢复历史技能...")
	for s_id in range(1, current_playing_stage):
		var record = skill_history_per_stage.get(s_id, {})
		# 兼容旧格式（Array 形式的纯 ID 列表）
		if record is Array:
			for skill_id in record:
				if not current_run_skill_ids.has(skill_id):
					current_run_skill_ids.append(skill_id)
					current_run_skill_levels[skill_id] = 1
		elif record is Dictionary:
			for skill_id in record.keys():
				var saved_level = int(record[skill_id])
				if not current_run_skill_ids.has(skill_id):
					current_run_skill_ids.append(skill_id)
					current_run_skill_levels[skill_id] = saved_level
				else:
					current_run_skill_levels[skill_id] = maxi(
						int(current_run_skill_levels.get(skill_id, 0)),
						saved_level
					)
	
	# 根据恢复的技能等级重新计算 player_base_stats
	for skill_id in current_run_skill_ids:
		var lv = int(current_run_skill_levels.get(skill_id, 1))
		var effects = get_skill_effects(skill_id, lv)
		if effects.has("max_hp_bonus"):
			player_base_stats["max_hp"] += float(effects["max_hp_bonus"])
			current_hp = player_base_stats["max_hp"]
		if effects.has("hp_regen"):
			player_base_stats["hp_regen"] += float(effects["hp_regen"])
		if effects.has("attack_mult"):
			player_base_stats["attack_power"] *= float(effects["attack_mult"])
		if effects.has("range_mult"):
			player_base_stats["attack_range"] *= float(effects["range_mult"])
	
	SignalBus.on_player_hp_changed.emit(current_hp, player_base_stats["max_hp"])
	print("[GameData] 历史技能恢复完成: ", current_run_skill_ids, " levels=", current_run_skill_levels)
	is_restoring_history = false

## 重置单局完整状态 (开始第一关或重新开始时调用)
func reset_run():
	player_base_stats = DEFAULT_PLAYER_BASE_STATS.duplicate(true)
	current_level = 1
	current_exp = 0.0
	current_hp = player_base_stats["max_hp"]
	current_wave = 0
	endless_time = 0.0
	is_in_ending_cinematic = false
	current_run_skill_ids.clear()
	current_run_skill_levels.clear()
	current_run_skill_route_bonus.clear()
	current_run_skill_route_history.clear()
	
	SignalBus.on_player_hp_changed.emit(current_hp, player_base_stats["max_hp"])
	
	# 重置对象池，防止上一关的敌人卡在屏幕中
	if PoolManager.has_method("reset_pools"):
		PoolManager.reset_pools()
	print("[GameData] 完整重置：等级 1，无技能")

## 增量重置 (进入下一关时调用，保留技能和等级)
func reset_stage():
	# 保留等级、经验和技能列表，仅重置波次和池
	current_wave = 0
	endless_time = 0.0
	# HP 建议恢复满，如果是硬核模式可以注释掉下一行
	current_hp = player_base_stats["max_hp"]
	SignalBus.on_player_hp_changed.emit(current_hp, player_base_stats["max_hp"])

	if PoolManager.has_method("reset_pools"):
		PoolManager.reset_pools()
	print("[GameData] 关卡重置：级数 %d 已保留" % current_level)

# 下面的代码兼容之前的 Main.gd 里的旧版 reset 调用
func reset():
	reset_run()

# ── 全局打击定格 (Hit-Stop) ──────────────────────────────────────
# time_scale_value: 定格期间的时间缩放 (0.05 = 几乎停止)
# duration: 定格持续时间（秒，真实时间）
func trigger_hit_stop(time_scale_value: float = 0.05, duration: float = 0.07) -> void:
	Engine.time_scale = time_scale_value
	# 使用 SceneTree timer 并乘以 time_scale，这样定格时间是真实时间
	var tree = Engine.get_main_loop() as SceneTree
	if tree:
		await tree.create_timer(duration * time_scale_value).timeout
	Engine.time_scale = 1.0

# ── 安全暂停系统 (避免 SceneTree null 报错) ──────────────────────
func set_game_paused(value: bool) -> void:
	var tree = Engine.get_main_loop() as SceneTree
	if tree:
		tree.paused = value
	else:
		# 极罕见情况：如果 Engine 拿不到 tree，通过打印警告代替崩溃
		push_warning("[GameData] 尝试设置暂停状态 %s 但 SceneTree 为空" % value)
