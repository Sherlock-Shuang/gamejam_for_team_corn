# 《树独》项目逻辑分析文档

## 📋 项目概述

**项目名称**: 树独
**引擎**: Godot 4.6
**项目类型**: 2D Roguelite 割草游戏
**开发背景**: 72小时 Game Jam 项目
**核心玩法**: 玩家扮演一棵孤独的树，通过拖拽弹射树干抽打敌人，击杀敌人获得经验升级，选择技能强化，抵御从自然虫害到人类伐木机甲的三阶段敌人进攻。

---

## 🏗️ 项目架构

### 目录结构
```text
project/
├── Main.tscn                    # 主场景入口
├── project.godot               # Godot项目配置文件
├── scripts/                    # 脚本目录
│   ├── Main.gd                 # 游戏主控制器
│   ├── actors/                 # 角色脚本
│   │   ├── treehead.gd        # 树干物理与战斗逻辑
│   │   └── EnemyAI.gd         # 敌人AI行为
│   ├── autoloads/             # 自动加载单例
│   │   ├── SignalBus.gd       # 全局事件总线
│   │   ├── GameData.gd        # 全局数据中心
│   │   └── PoolManager.gd     # 对象池管理器(临时)
│   ├── components/            # 组件脚本
│   │   ├── WaveManager.gd     # 波次管理器
│   │   └── SkillExecutor.gd   # 技能引擎核心（实装技能效果）
│   └── ui/                    # UI脚本
│       ├── HUD.gd             # 年轮式状态UI
│       ├── UpgradeUI.gd       # 三选一升级弹窗
│       └── AnnualRingMenu.gd  # 局外年轮选关主菜单界面
├── scenes/                    # 场景目录
│   ├── actors/                # 角色场景
│   │   ├── tree.tscn         # 树的场景
│   │   ├── tree.gd           # 树的形态演化脚本
│   │   ├── vine_whip.gd      # 藤条鞭打物理机制
│   │   └── Enemy.tscn        # 敌人场景
│   └── ui/                    # UI场景
│       ├── HUD.tscn          # 状态UI场景
│       ├── UpgradeUI.tscn    # 升级UI场景
│       └── AnnualRingMenu.tscn# 年轮选关UI场景
├── assets/                    # 资源目录 (包含音效、贴图等)
├── resources/                 # 资源文件夹
└── .godot/                    # Godot引擎生成文件
```

### 技术架构特点

1. **单例模式(Autoload)**: 使用Godot的自动加载功能实现全局单例。
2. **事件驱动架构**: 通过SignalBus实现模块间解耦通信。
3. **组件化设计**: 将功能拆分为独立组件(如 `WaveManager`, `SkillExecutor`)便于维护。
4. **数据驱动**: GameData集中管理所有游戏内数值和局外进度。

---

## 🎮 核心功能模块

### 1. 主控制器 (Main.gd)

**功能定位**: 游戏主控制中心，协调UI、数据和游戏世界。

**核心功能**:
- 游戏初始化与系统连接
- 模拟经验自动增长(测试用)
- 自动攻击演示(测试用)
- 升级逻辑处理
- 技能选择响应

**重要函数**:

| 函数名 | 功能 | 位置 |
|--------|------|------|
| `_ready()` | 初始化游戏，建立系统连接 | scripts/Main.gd |
| `_test_auto_attack()` | 自动攻击演示，生成彩色菱形投掷物 | scripts/Main.gd |
| `_test_add_experience()` | 模拟获得经验，检查升级条件 | scripts/Main.gd |
| `_level_up()` | 升级处理，重置经验，发送升级信号 | scripts/Main.gd |
| `_on_skill_chosen(skill_id: String)` | 响应技能选择，应用技能效果 | scripts/Main.gd |

---

### 2. 全局数据中心 (GameData.gd)

**功能定位**: 集中管理所有游戏数值，实现数据驱动设计，涵盖局内运行与局外进度。

**核心数据结构**:

#### 局内运行时状态
```gdscript
var current_level: int = 1      # 当前等级
var current_exp: float = 0.0    # 当前经验值
var current_hp: float = 100.0   # 当前生命值
var current_wave: int = 0       # 当前波次
```

#### 局外进度状态
```gdscript
var current_max_stage: int = 1                         # 当前解锁的最大关卡数（年轮数）
var skill_history_per_stage: Dictionary = {}           # 各关卡解锁技能历史
var current_playing_stage: int = 1                     # 当前正在挑战的关卡
```

#### 玩家基础属性与成长阶段系统
- 管理生命值、攻击、攻速、移速等基础属性。
- 成长阶段分为 `幼苗`, `小树`, `大树`, `神木`，随等级变化改变形态与属性倍率。

#### 技能池与敌人配置
- 技能分为三大类：**衍生攻击类**、**元素附魔类**、**基础数值类**。
- 敌人分为三大阶段：**第一阶段(自然虫害)**、**第二阶段(哺乳动物)**、**第三阶段(人类文明)**。

**重要函数**:

| 函数名 | 功能 | 位置 |
|--------|------|------|
| `get_exp_to_next_level(level: int)` | 计算升级所需经验 | scripts/autoloads/GameData.gd |
| `get_random_skills(count: int)` | 随机抽取不重复技能 | scripts/autoloads/GameData.gd |
| `record_skill_for_stage(stage_id, skill_id)` | 记录在某关获得的技能，保存至进度中 | scripts/autoloads/GameData.gd |
| `reset_for_new_game()` | 重置局内状态，保留局外进度 | scripts/autoloads/GameData.gd |

---

### 3. 事件总线 (SignalBus.gd)

**功能定位**: 全局事件通信中心，实现模块间解耦。
通过定义如 `on_enemy_died`, `on_level_up`, `on_upgrade_selected`, `on_skill_actived` 等信号，实现各组件之间的零耦合通信。

---

### 4. 树干物理与战斗 (treehead.gd & tree.gd & vine_whip.gd)

**功能定位**: 核心操作机制与玩家实体管理。

#### 玩家实体 (tree.gd)
- **功能**: 管理树的各个形态阶段表现。
- **机制**: `evolve_to_stage(stage_index)` 函数负责切换不同阶段的树根和树干贴图，并基于 `create_tween()` 执行弹性(Q弹)放大动画，模拟生长的视觉反馈。

#### 树干弹射 (treehead.gd)
- **机制**: 基于 RigidBody2D 的物理模拟。玩家向后拖拽并松开，树干产生回弹(如弹弓)。
- **手感设计**: 使用 `lerp_angle` 和多段阻尼(鞭打时的低阻尼、稳定时的高阻尼)实现鞭打的过冲效果。战斗判定依赖于角速度(角速度超过阈值才造成伤害)。

#### 藤条鞭打机制 (vine_whip.gd)
- **机制**: 采用贝塞尔曲线动态绘制藤条。
- **物理包裹**: 沿着生成的曲线节点动态计算法线，实时构建 `CollisionPolygon2D` 形成伤害判定区域。
- **伤害判定**: 利用尖端速度(`tip_velocity.length()`)判断是否超过杀伤阈值来击杀敌人。

---

### 5. 技能引擎 (SkillExecutor.gd)

**功能定位**: 玩家技能核心组件，负责解析和实装 `GameData` 里的技能效果。作为 `tree` 节点的子节点运行。

**核心机制**:
1. **衍生攻击类 (A类)**: 
   - 如 `thorn_shot`, `exploding_fruit`。
   - 使用 `_create_skill_timer` 创建独立计时器，定时执行攻击逻辑(如发射毒刺)。结合 `Tween` 实现弹道和简易伤害判定。
2. **元素附魔类 (B类)**: 
   - 如 `ice_enchant`, `fire_enchant`。
   - 监听 `SignalBus.on_enemy_hit` 事件，当触发普攻时对目标附加对应效果(如减速、持续伤害)。
3. **基础数值类 (C类)**: 
   - 如 `thick_bark`, `wide_canopy`。
   - 在技能解锁时，直接修改 `GameData` 属性或改变角色节点的 Scale。

---

### 6. 敌人AI与波次管理 (EnemyAI.gd & WaveManager.gd)

**敌人AI**: 
- 基于Boids算法变种(分离+寻路)。计算指向树的引力与同类间的斥力并合成最终向量，使用 `move_and_slide()` 进行平滑移动。

**波次管理**: 
- `WaveManager` 通过定时器控制敌人生成。随波次递增难度(时间、生成数量与频率)，并在随机角度边缘异步生成敌人实例。

---

### 7. UI与选关系统 (HUD.gd, UpgradeUI.gd, AnnualRingMenu.gd)

#### 年轮选关界面 (AnnualRingMenu.gd)
- **功能**: 局外的进度大地图菜单。
- **视觉实现**: 使用 Godot 的 `_draw()` 纯代码渲染同心圆年轮。最外圈为当前最高进度并带有呼吸灯特效。
- **交互**: 鼠标悬停高亮计算基于中心距离。在对应的年轮上会绘制出该关卡已解锁过的技能“历史印记”。点击后更新 `GameData.current_playing_stage` 并切换至 `Main.tscn`。

#### 局内UI (HUD.gd & UpgradeUI.gd)
- **HUD**: 创新的年轮式UI，外圈显示经验进度，中心随血量变色(绿→黄→红)。
- **升级**: `UpgradeUI` 监听升级信号并暂停游戏，从 `GameData` 抽取3个不重复技能供玩家选择，选后通过总线分发解锁事件。

---

## 🔑 重要变量汇总

### 全局状态变量 (GameData.gd)
| 变量 | 类型 | 用途 |
|------|------|------|
| `current_level` / `current_exp` / `current_hp` | 数值 | 局内当前等级、经验值、生命值 |
| `current_max_stage` | int | 局外进度，当前最大解锁关卡 |
| `current_playing_stage` | int | 局内正在游玩的关卡 |
| `skill_history_per_stage` | Dictionary | 记录每个关卡中玩家选过的技能 |

### 核心物理/战斗变量
| 变量 | 所在文件 | 用途 |
|------|----------|------|
| `base_pull_speed` / `angular_stiffness` | treehead.gd | 基础拉拽速度与角度刚度(决定弹射手感) |
| `damage_velocity_threshold` | treehead.gd | 角速度超过此阈值才会判定为有效鞭打伤害 |
| `spring_stiffness` / `damage_speed_threshold` | vine_whip.gd | 藤条弹簧刚度与尖端杀伤速度阈值 |
| `hitbox_thickness` | vine_whip.gd | 藤条杀伤范围的碰撞厚度 |

---

## 🚀 待实现/已完成功能列表

### ✅ 已完成
- 主控制器与核心游戏循环
- 全局数据中心 (局内外进度分离)
- 事件总线系统解耦
- 树干拖拽物理与弹性手感
- 敌人AI寻路 (Boids集群变种)
- 波次管理系统
- 年轮式局内UI与升级选择UI
- 技能池配置与**技能效果引擎实装** (`SkillExecutor`)
- 动态贝塞尔曲线藤条机制 (`vine_whip.gd`)
- **局外年轮进度与选关系统** (`AnnualRingMenu`)

### ❌ 待完善
- 真正的对象池实现 (`PoolManager` 目前还是直接实例化)
- 经验球系统 (当前为直接获得经验)
- 详细的敌人伤害受击表现
- 游戏结束(Game Over)结算与重开逻辑
- 完善的音效与粒子特效反馈
- 打击顿挫感(Hit Stop)
- 存档/读档系统持久化保存 `GameData`

---

## 📝 总结与技术亮点

这是一个设计精良且充满创意的 Godot 4 Roguelite 割草游戏原型。
在原有框架基础上，项目实现了**数据驱动**与**事件解耦**的高度统一。

**新架构亮点**:
1. **纯代码视觉表达**: `AnnualRingMenu` 使用 `_draw()` 动态绘制大地图年轮，无需外部贴图即可呈现优秀的美术与交互概念。
2. **物理碰撞动态生成**: `vine_whip.gd` 利用贝塞尔曲线和法线运算，每帧动态生成多边形碰撞(`CollisionPolygon2D`)，实现了极佳的“软体鞭打”手感和精确判定。
3. **高扩展性技能引擎**: `SkillExecutor` 充分利用节点事件和 Tween 动画，将数值成长、元素附魔、衍生攻击逻辑与主体剥离，后续添加新技能只需在 `GameData` 配置并在引擎中追加分支。
4. **弹性生长表现**: 充分利用 Godot 补间动画引擎 (`Tween.TRANS_ELASTIC`) 为树木成长、属性扩展提供了直观且Q弹的“生命力”表现。

项目为 Game Jam 级别打下了坚实的基础，并在核心玩法手感上做出了十分深入的探索。

---
*文档更新时间: 2026-03-28*
*项目版本: Game Jam 开发中 (Update)*
*文档版本: 1.1*

