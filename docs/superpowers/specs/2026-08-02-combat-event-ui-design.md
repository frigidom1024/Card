# 战斗事件 UI 设计

**日期：** 2026-08-02  
**状态：** 已确认，等待文档复核  
**范围：** 单怪物遭遇战的日志回放与结果结算界面

## 目标

为怪物遭遇和 Boss 事件提供一个只读的战斗展示界面：战斗系统先计算完整的 `CombatResult`，UI 按顺序播放其中的 `CombatStep`，玩家最后确认胜利奖励占位或战斗惩罚。战斗期间玩家不选择行动、不修改牌链、不参与伤害计算。

首版的目标是让玩家清楚看到“现有牌链为何导致这一结果”，而不是新增一套可操作的战斗界面。

## 非目标

首版不包含：

- 玩家在战斗中选择卡牌、目标或怪物行动；
- 战斗动画、角色立绘、伤害飘字、音效和播放速度设置；
- 多怪物、目标选择或怪物行动队列；
- 独立战斗奖励数据模型或实际的胜利掉落；
- 在 UI 中重算伤害、护甲、卡牌规则或惩罚。

## 现有数据与边界

`CombatResult` 已提供：

- `outcome`：`VICTORY`、`RETREAT`、`DEFEAT`；
- `steps`：完整的 `CombatStep` 序列；
- `player_stats_after`、`monster_stats_after`：最终状态；
- `penalties`：战斗结算要执行的惩罚。

`CombatStep` 已保存：

- 行动类别：根牌、玩家卡牌或怪物行动；
- 行动来源名称；
- 每一步产生的 `CombatEffect`；
- 双方行动前、后的 `CombatStats` 快照。

因此 UI 只读取战斗结果快照，不修改 `CombatService`、卡牌规则和惩罚规则。最终业务写入仍由 `GameManager` 的既有战斗结果应用逻辑负责。

## 场景与接口

新增场景与脚本：

- `res://scenes/game/event_combat.tscn`
- `res://scripts/game/event/encounter/combat_event_view.gd`
- `res://tests/combat_event_ui_scene_test.gd`

场景挂载到既有弹窗层：

```text
GameManager
└── EventModalLayer
    ├── ShopEventView
    ├── TreasureEventView
    └── CombatEventView
```

`CombatEventView` 的职责：

1. 接收已计算的遭遇、怪物与 `CombatResult`；
2. 自动回放日志；
3. 展示结算页；
4. 在确认按钮被点击时发出信号。

推荐公开接口：

```gdscript
signal settlement_confirmed()

func show_combat(instance: EventInstance, monster: MobInstance, result: CombatResult) -> void
func hide_combat() -> void
```

内部使用 `Timer` 或等价流程，以 **0.7 秒每步**自动追加日志。点击日志区域或“加速”按钮会立即展示下一步；首版不要求暂停、倒退或重播。

UI 不直接调用事件 Resolver、不写入玩家生命、不删除卡牌、不标记事件完成。

## 界面状态

`CombatEventView` 有两个内部展示阶段：

1. **日志回放阶段**
2. **结算阶段**

### 日志回放阶段

界面包含：

- 标题：`遭遇战斗`；
- 进度：`当前步数 / 总步数`；
- 玩家状态栏：当前 HP 与护甲；
- 怪物状态栏：当前 HP 与护甲；
- 可滚动日志列表；
- 底部“加速”按钮。

每个 `CombatStep` 只追加一次，并使用其 `player_after` 和 `monster_after` 快照更新状态栏。日志文本按类别表达：

- `ROOT_CARD`：`根牌效果：<source_name>`；
- `PLAYER_CARD`：`玩家结算：<source_name>`；
- `MONSTER_ACTION`：`<source_name> 行动`。

如果步骤带有效果，则在该条日志中以简短摘要列出效果描述；如果没有可用描述，仍保留行动来源和双方属性变化，避免丢失步骤。

播放完最后一个步骤后，底部按钮改为 `查看结算`。在这之前不可确认事件结果。

### 结算阶段

日志保留可回看，状态栏显示最终快照，主内容切换为结果信息。

#### 胜利（`VICTORY`）

- 标题：`遭遇胜利`；
- 内容：`已击败 <怪物名>`；
- 奖励区域：`本次遭遇已解决`；
- 按钮：`确认继续`。

当前战斗模型没有独立奖励字段，因此首版只提供明确的胜利确认反馈，不虚构或提前发放奖励。

#### 撤退（`RETREAT`）

- 标题：`撤离`；
- 内容：`牌链已结算完毕，但未能击败 <怪物名>`；
- 惩罚区域：逐项展示 `CombatResult.penalties` 的 `description`；
- 按钮：`接受惩罚并继续`。

撤退的玩家生命回滚、临时护甲清除、怪物伤势保留和牌链惩罚，仍由既有结算逻辑在确认后执行。

#### 战败（`DEFEAT`）

- 标题：`远征失败`；
- 内容：`生命降至 0，探索结束。`；
- 惩罚区域：如存在则展示惩罚描述；
- 按钮：`确认`。

确认后游戏保持探索失败锁定状态；不会重新开放拖拽和棋盘交互。

## GameManager 接入

遭遇触发后，流程改为：

```text
触发 MONSTER/BOSS 事件
→ GameManager 锁定棋盘交互
→ EncounterCombatFlowCoordinator 同步计算 CombatResult
→ CombatEventView 自动播放 CombatStep 日志
→ 玩家在结算页确认
→ GameManager 应用 CombatResult
→ 关闭 UI，并依结果恢复或保持探索锁定
```

`GameManager` 保存待确认的 `EventInstance` 和 `CombatResult`。`_begin_encounter()` 不得在调用 `show_combat()` 后立即应用结果。

`combat_resolved` 表示“最终结果已应用”，故应在结算确认后发出，而不是在 UI 开始播放时发出。`combat_started` 仍在开始播放前发出。

如果战斗计算返回 `null`，或初始化怪物失败，继续使用现有的安全清理流程，不打开战斗 UI。

## 交互锁定规则

- 从遭遇触发到结算确认之间：牌桌拖拽和事件重复触发保持锁定；
- 胜利、撤退确认完成：由原流程按现有规则恢复交互；
- 战败确认完成：保持锁定，并通过既有 `exploration_failed` 流程结束探索；
- 其他事件 UI 不应与战斗 UI 同时打开，继续由 `_active_event` 约束。

## 测试与验收

遵循测试驱动开发：先新增失败测试，确认失败原因是 UI 和接入尚不存在，再实现最小功能。

至少覆盖：

1. 战斗场景可加载和实例化，拥有稳定的日志、状态、结算和确认节点；
2. 输入多个 `CombatStep` 时，日志按数组顺序出现，双方状态使用每步的 after 快照；
3. 最后一步之前不显示结算；完成后按三种 `Outcome` 显示正确标题、正文、按钮文案；
4. 撤退和战败会显示所有惩罚描述；
5. 点击确认只发出 `settlement_confirmed`，视图不修改业务数据；
6. `GameManager` 在确认前不应用 `CombatResult`，确认后才应用并发出 `combat_resolved`；
7. 回归现有战斗路由测试、商店/宝藏 UI 场景测试、Godot 场景解析和 diff 格式检查。

## 后续扩展点

- 使用步骤的前后状态快照驱动角色动画、伤害飘字和护甲特效；
- 增加自动播放速度、暂停、重播与逐步回看；
- 在 `CombatResult` 引入奖励条目后，替换胜利页的占位奖励区域；
- 支持不同根牌或不同 `CombatService` 的专属战斗演出，但保持 UI 只消费标准 `CombatResult`。
