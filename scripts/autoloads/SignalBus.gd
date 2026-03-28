extends Node
# ═══════════════════════════════════════════════════════════════
#  SignalBus.gd — 全局事件总线 (Autoload 单例)
#  所有模块之间的通信必须通过这里，禁止直接引用节点！
# ═══════════════════════════════════════════════════════════════

# ── 战斗事件 ──
signal on_enemy_died(exp_value: float, position: Vector2)  # 敌人死亡，掉落经验
signal on_enemy_hit(damage: float, position: Vector2)       # 敌人被击中

# ── 经验与升级 ──
signal on_exp_gained(amount: float)       # 获得经验值
signal on_level_up(new_level: int)        # 升级触发

# ── 技能选择 ──
signal on_upgrade_selected(skill_id: String)  # 玩家在三选一弹窗中选择了技能

# ── 玩家状态 ──
signal on_player_hp_changed(current_hp: float, max_hp: float)  # 血量变化
signal on_player_died()                                         # 玩家死亡

# ── 波次系统 ──
signal on_wave_started(wave_number: int)   # 新波次开始
signal on_wave_cleared(wave_number: int)   # 波次清除

# ── 全局控制 ──
signal on_game_over()    # 游戏结束
signal on_game_restart() # 重新开始
