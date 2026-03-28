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

# ── 局外进度状态 (年轮界面) ──
var current_max_stage: int = 1                         # 当前解锁的最大关卡数（年轮数）
var skill_history_per_stage: Dictionary = {}           # 格式: { stage_id : [ "skill_a", "skill_b" ] }
var current_playing_stage: int = 1                     # 玩家当前正在挑战哪一关


# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#  玩家基础属性
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
var player_base_stats: Dictionary = {
	"max_hp": 100.0,
	"attack_power": 10.0,
	"attack_range": 1.0,   # 倍率
	"attack_speed": 1.0,   # 倍率
	"hp_regen": 0.0,       # 每秒恢复
	"move_speed": 1.0,     # 倍率
}

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#  成长阶段 (幼苗 → 小树 → 大树 → 神木)
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
var growth_stages: Array = [
	{"name": "幼苗", "level_threshold": 1,  "scale_mult": 1.0,  "description": "攻速快但范围小"},
	{"name": "小树", "level_threshold": 5,  "scale_mult": 1.3,  "description": "初具规模"},
	{"name": "大树", "level_threshold": 12, "scale_mult": 1.7,  "description": "枝繁叶茂"},
	{"name": "神木", "level_threshold": 20, "scale_mult": 2.2,  "description": "附带地震效果"},
]

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#  经验值公式: 每级所需经验 = base * (level ^ exponent)
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
var exp_base: float = 10.0
var exp_exponent: float = 1.2

func get_exp_to_next_level(level: int) -> float:
	return exp_base * pow(level, exp_exponent)

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#  技能词条池 (三选一升级)
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
var skill_pool: Dictionary = {
	# ── 衍生攻击类 ──
	"thorn_shot": {
		"id": "thorn_shot",
		"name": "毒刺发射",
		"category": "衍生攻击",
		"description": "自动向最近的敌人发射毒刺，造成持续中毒伤害。",
		"icon": "",
		"effects": {"poison_damage": 3, "interval": 2.0}
	},
	"exploding_fruit": {
		"id": "exploding_fruit",
		"name": "爆炸果实",
		"category": "衍生攻击",
		"description": "定期抛射果实，落地后爆炸对范围内敌人造成伤害。",
		"icon": "",
		"effects": {"explosion_damage": 8, "radius": 50.0, "interval": 4.0}
	},
	"vine_spread": {
		"id": "vine_spread",
		"name": "绞杀藤蔓",
		"category": "衍生攻击",
		"description": "在地表蔓延藤蔓，减速并持续伤害踩上的敌人。",
		"icon": "",
		"effects": {"slow_percent": 0.4, "dps": 2, "duration": 5.0}
	},
	"seed_bomb": {
		"id": "seed_bomb",
		"name": "种子炸弹",
		"category": "衍生攻击",
		"description": "播撒种子，短暂延迟后长出小树苗对周围敌人造成伤害。",
		"icon": "",
		"effects": {"sapling_damage": 12, "delay": 1.5}
	},
	
	# ── 元素附魔类 ──
	"fire_enchant": {
		"id": "fire_enchant",
		"name": "烈焰附魔",
		"category": "元素附魔",
		"description": "攻击附带火焰，使敌人持续燃烧3秒。",
		"icon": "",
		"effects": {"burn_dps": 4, "burn_duration": 3.0}
	},
	"ice_enchant": {
		"id": "ice_enchant",
		"name": "冰霜附魔",
		"category": "元素附魔",
		"description": "攻击附带冰冻效果，减速敌人50%持续2秒。",
		"icon": "",
		"effects": {"slow_percent": 0.5, "slow_duration": 2.0}
	},
	"lightning_enchant": {
		"id": "lightning_enchant",
		"name": "雷电附魔",
		"category": "元素附魔",
		"description": "攻击附带连锁闪电，跳跃至最多3个相邻敌人。",
		"icon": "",
		"effects": {"chain_damage": 5, "chain_count": 3}
	},
	
	# ── 基础数值类 ──
	"thick_bark": {
		"id": "thick_bark",
		"name": "厚实树皮",
		"category": "基础数值",
		"description": "树干硬化，最大生命值 +20。",
		"icon": "",
		"effects": {"max_hp_bonus": 20}
	},
	"deep_roots": {
		"id": "deep_roots",
		"name": "深扎根系",
		"category": "基础数值",
		"description": "根系深扎大地，每秒恢复2点生命。",
		"icon": "",
		"effects": {"hp_regen": 2.0}
	},
	"wide_canopy": {
		"id": "wide_canopy",
		"name": "宽阔树冠",
		"category": "基础数值",
		"description": "树冠扩展，攻击范围增加30%。",
		"icon": "",
		"effects": {"range_mult": 1.3}
	},
	"elastic_trunk": {
		"id": "elastic_trunk",
		"name": "弹性树干",
		"category": "基础数值",
		"description": "树干弹性增强，弹射击退距离提升40%。",
		"icon": "",
		"effects": {"knockback_mult": 1.4}
	},
	"photosynthesis": {
		"id": "photosynthesis",
		"name": "光合强化",
		"category": "基础数值",
		"description": "增强光合作用，攻击力提升25%。",
		"icon": "",
		"effects": {"attack_mult": 1.25}
	},
}

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#  敌人属性表
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
var enemy_stats: Dictionary = {
	# 第一阶段：自然虫害
	"beetle": {
		"name": "甲虫", "hp": 8, "speed": 40.0, "damage": 2.0,
		"exp_drop": 1.0, "phase": 1
	},
	"caterpillar": {
		"name": "毛毛虫", "hp": 5, "speed": 25.0, "damage": 1.0,
		"exp_drop": 0.5, "phase": 1
	},
	"mosquito": {
		"name": "飞虫", "hp": 3, "speed": 70.0, "damage": 1.5,
		"exp_drop": 0.8, "phase": 1
	},
	# 第二阶段：哺乳动物
	"beaver": {
		"name": "河狸", "hp": 30, "speed": 35.0, "damage": 5.0,
		"exp_drop": 3.0, "phase": 2
	},
	# 第三阶段：人类
	"lumberjack": {
		"name": "伐木工", "hp": 25, "speed": 45.0, "damage": 8.0,
		"exp_drop": 5.0, "phase": 3
	},
	"flamethrower": {
		"name": "喷火兵", "hp": 20, "speed": 40.0, "damage": 12.0,
		"exp_drop": 8.0, "phase": 3
	},
	"mech_boss": {
		"name": "伐木机甲", "hp": 200, "speed": 20.0, "damage": 25.0,
		"exp_drop": 50.0, "phase": 3
	},
}

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#  波次时间表
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
var wave_table: Array = [
	# wave 1-3: 虫害阶段 (前3分钟，让玩家快速升级体验割草感)
	{"wave": 1, "duration": 30.0, "enemies": ["beetle"],               "spawn_interval": 1.5, "max_enemies": 15},
	{"wave": 2, "duration": 40.0, "enemies": ["beetle", "caterpillar"],"spawn_interval": 1.2, "max_enemies": 25},
	{"wave": 3, "duration": 50.0, "enemies": ["beetle", "caterpillar", "mosquito"], "spawn_interval": 1.0, "max_enemies": 40},
	# wave 4-6: 加入河狸
	{"wave": 4, "duration": 50.0, "enemies": ["caterpillar", "mosquito", "beaver"], "spawn_interval": 0.9, "max_enemies": 50},
	{"wave": 5, "duration": 60.0, "enemies": ["mosquito", "beaver"],  "spawn_interval": 0.8, "max_enemies": 60},
	{"wave": 6, "duration": 60.0, "enemies": ["beaver"],              "spawn_interval": 0.7, "max_enemies": 40},
	# wave 7-9: 人类阶段
	{"wave": 7, "duration": 60.0, "enemies": ["beaver", "lumberjack"],"spawn_interval": 0.8, "max_enemies": 50},
	{"wave": 8, "duration": 70.0, "enemies": ["lumberjack", "flamethrower"], "spawn_interval": 0.7, "max_enemies": 45},
	{"wave": 9, "duration": 80.0, "enemies": ["flamethrower", "lumberjack"], "spawn_interval": 0.6, "max_enemies": 50},
	# wave 10: Boss 波
	{"wave": 10, "duration": 90.0, "enemies": ["flamethrower", "mech_boss"], "spawn_interval": 2.0, "max_enemies": 20},
]

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#  工具方法
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

## 随机抽取 count 个不重复的技能
func get_random_skills(count: int = 3) -> Array:
	var all_keys = skill_pool.keys()
	all_keys.shuffle()
	var result: Array = []
	var n = mini(count, all_keys.size())
	for i in range(n):
		result.append(skill_pool[all_keys[i]])
	return result

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

## 记录在某关获得的技能
func record_skill_for_stage(stage_id: int, skill_id: String):
	if not skill_history_per_stage.has(stage_id):
		skill_history_per_stage[stage_id] = []
	if not skill_history_per_stage[stage_id].has(skill_id):
		skill_history_per_stage[stage_id].append(skill_id)

## 重置单局状态 (进入新关卡前调用，保留局外进度)
func reset_for_new_game():
	current_level = 1
	current_exp = 0.0
	current_hp = player_base_stats["max_hp"]
	current_wave = 0
	
	# 下面的代码兼容之前的 Main.gd 里的旧版 reset 调用
func reset():
	reset_for_new_game()
