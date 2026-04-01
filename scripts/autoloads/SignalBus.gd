extends Node
# ═══════════════════════════════════════════════════════════════
#  SignalBus.gd — 全局事件总线 (Autoload 单例)
#  ⚠️  规则：所有模块间通信必须通过这里！禁止直接引用其他节点！
#
#  Dev A (战斗/玩家) 和 Dev B (UI/数据) 共同遵守本协议。
#  信号命名规范: on_<事件描述>(参数)
# ═══════════════════════════════════════════════════════════════

# ── 战斗事件 (Dev A 负责 emit) ──────────────────────────────────
## 任意敌人死亡时广播，携带经验值、死亡位置及致死来源
signal on_enemy_died(exp_value: float, position: Vector2, cause: String)
## 敌人被击中时广播 (传递目标 Node2D 方便外接状态)
signal on_enemy_hit(damage: float, position: Vector2, enemy_node: Node2D, cause: String)

# ── 经验与升级 (Dev A emit → Dev B/UI 接收) ─────────────────────
## 经验值变化，ratio = current_exp / exp_needed (0.0 ~ 1.0)
signal on_exp_gained(ratio: float)
## 玩家升级，传入新等级
signal on_level_up(new_level: int)
## 请求打开升级选择 UI（Dev A 触发，Dev B 的 UI 接收）
signal open_upgrade_ui()

# ── 技能选择 (Dev B/UI emit → Dev A/Main 接收) ──────────────────
## 玩家在三选一弹窗中选择了技能
signal on_upgrade_selected(skill_id: String)
## UI通知全服某个技能已正式生效 (SkillExecutor负责监听并开启对应词条能力)
signal on_skill_actived(skill_id: String)

# ── 怪物状态控制与元素特效 (SkillExecutor/Dev A 互通) ─────────
## 施加元素附魔效果：目标，效果名 ("ice_slow", "fire_burn"), 强度数组
signal apply_elemental_effect(target_enemy: Node2D, effect_type: String, args: Dictionary)

# ── 玩家状态 (Dev A emit → HUD 接收) ───────────────────────────
## 血量发生变化
signal on_player_hp_changed(current_hp: float, max_hp: float)
## 玩家死亡
signal on_player_died()

# ── 波次系统 (Main/WaveManager emit) ───────────────────────────
## 新一波次开始
signal on_wave_started(wave_number: int)
## 本波次全部敌人清除
signal on_wave_cleared(wave_number: int)

# ── 全局控制 ────────────────────────────────────────────────────
## 游戏结束 (玩家死亡或通关后触发)
signal on_game_over()
## 玩家请求重新开始
signal on_game_restart()
## 玩家请求返回主界面/年轮界面 (任何地方 emit，Main 响应处理)
signal on_return_requested()
## 玩家请求暂停游戏
signal on_pause_requested()
