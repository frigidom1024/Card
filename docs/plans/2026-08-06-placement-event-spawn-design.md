# 探索事件生成机制设计：初始事件与落牌后随机生成

- 日期：2026-08-06
- 分支：`codex/placement-event-spawn`
- 状态：设计已确认，待实现

## 1. 背景与目标

当前探索事件服务依赖 `FogService`，通过揭开迷雾格子触发事件生成。新玩法取消迷雾机制，改为：

1. 棋盘创建时直接随机放置一批本关事件；
2. 每次成功放置 ROOT 或普通牌后，探索系统尝试随机生成 0～2 个事件；
3. GUIDE 卡不触发动态事件生成；
4. 新事件从整个棋盘的合法空位中随机生成，不优先靠近本次落牌位置；
5. Boss 仍是普通 `EventInstance`，仍通过卡牌放置接触事件触发，不增加独立点击入口；
6. Boss 追击服务只修改 Boss 事件的位置，不承担事件交互或战斗逻辑。

## 2. 非目标

本次不修改：

- 卡牌数值、怪物数值和战斗结算；
- 信仰值、RETREAT、回潮强化和 FaithService 的规则；
- 事件内容、商店购买、宝藏奖励和战斗 UI；
- Boss 追击的阶段规则，只迁移 Boss 出现条件的输入来源；
- 棋盘空间规则、事件缓冲格规则和普通事件接触规则。

## 3. 核心架构

### 3.1 职责边界

```text
EventLib
└── 维护本关可用的 EventData 模板与事件场景

ExplorationSpawnConfig
└── 维护本关的事件生成节奏、候选池、权重、数量和上限

EventPlacementService
└── 查找合法原点，并把 EventInstance 随机附着到 Board

ExplorationEventService
└── 执行初始生成、落牌后抽样、模板选择和生成结果汇报

ExplorationCoordinator
└── 协调初始化、落牌事务、动态生成和 Boss 追击

BossPressureService
└── 注册普通 Boss 事件并移动其位置，不改变事件交互语义
```

### 3.2 配置资源

新增 `EventSpawnCandidate` Resource：

```gdscript
class_name EventSpawnCandidate
extends Resource

@export var event_data: EventData
@export_range(1, 999, 1) var weight := 1
@export var allow_duplicate := true
```

新增 `ExplorationSpawnConfig` Resource：

```gdscript
class_name ExplorationSpawnConfig
extends Resource

@export_range(0, 20, 1) var initial_event_count_min := 3
@export_range(0, 20, 1) var initial_event_count_max := 5
@export var initial_event_pool: Array[EventSpawnCandidate] = []

# key 为生成数量，value 为权重；允许 0、1、2。
@export var placement_spawn_count_weights: Dictionary = {
    0: 60,
    1: 30,
    2: 10,
}
@export var placement_event_pool: Array[EventSpawnCandidate] = []

@export_range(1, 30, 1) var max_unresolved_events := 8
@export_range(1, 99, 1) var boss_spawn_after_placements := 8
```

`EventLib` 继续作为事件模板目录，不承担初始/动态生成策略。候选池通过资源引用 `EventData`，每个关卡可独立配置自己的 `EventLib` 与 `ExplorationSpawnConfig`。

## 4. 初始事件生成

探索初始化完成后调用 `spawn_initial_events()`：

1. 在 `initial_event_count_min` 与 `initial_event_count_max` 之间随机决定目标数量；
2. 从 `initial_event_pool` 按权重抽取候选模板；
3. 根据 `allow_duplicate` 过滤已使用模板；
4. 为每个候选创建新的 `EventInstance`；
5. 调用 `EventPlacementService.place_event_instance()`，从全棋盘合法位置中随机选点；
6. 没有合法位置时停止该次生成并记录警告，不破坏游戏初始化。

第一关配置建议为 3～5 个初始事件，初始池包含普通残响、宝藏和商店，不包含 Boss。

## 5. 落牌后动态生成

`Board.placement_committed` 是唯一的探索生成入口。

触发条件：

| 放置结果 | 动态生成 | Boss 探索计数 | Boss 追击计数 |
|---|---:|---:|---:|
| ROOT | 是 | +1 | 按现有规则处理 |
| 普通牌 | 是 | +1 | 按现有规则处理 |
| GUIDE | 否 | +0 | 不推进 |
| 非法放置 | 不会产生提交事件 | +0 | +0 |
| 手动拆牌 | 否 | +0 | 不推进 |

一次符合条件的落牌执行：

1. 按 `placement_spawn_count_weights` 抽取 0、1 或 2；
2. 检查未解决事件数量上限；
3. 对每个要生成的事件，从 `placement_event_pool` 按权重抽取模板；
4. 创建 `EventInstance`；
5. 使用 `EventPlacementService` 在全棋盘随机合法位置放置；
6. 空间不足时允许实际生成数量低于抽取数量；
7. 通过 `event_spawned` 汇报生成结果。

达到 `max_unresolved_events` 后，本次直接不生成普通动态事件。Boss 不占用普通动态事件额度。

## 6. Boss 出现迁移

取消迷雾后，Boss 不再使用揭开格子数量作为出现条件。改为统计成功探索牌放置次数：

```text
boss_spawn_after_placements
```

计数只由 ROOT 和普通牌推进，GUIDE 不推进。

达到阈值后：

1. 从 `EventLib` 获取 Boss 模板；
2. 创建普通 `EventInstance`；
3. 在全棋盘合法位置随机放置；
4. 通过现有事件生成信号注册 Boss；
5. 后续由 `BossPressureService` 继续按现有配置移动 Boss。

如果达到阈值时没有合法位置，则保持 Boss 待生成状态，在后续符合条件的落牌后继续尝试。

Boss 事件必须继续满足以下不变量：

- 是普通 `BoardEvent` / `EventInstance`；
- 通过卡牌放置接触触发；
- 不开放独立点击挑战入口；
- Boss 追击服务不能直接启动战斗；
- Boss 移动后仍遵循棋盘事件占用和缓冲格规则。

## 7. 迷雾移除

迁移完成后：

- `ExplorationCoordinator` 不再持有或调用 `FogService`；
- 删除基于 `cells_revealed` 的事件调度；
- 删除 `fog_revealed` 对外信号和揭开格子计数；
- 从 `ExplorationConfig` 移除 `scheduled_event_reveal_thresholds`；
- 从 Boss 生成逻辑移除 `boss_reveal_threshold`；
- 无其它引用后删除 `fog_service.gd` 及对应 UID 与测试。

## 8. 随机与可测试性

所有生成服务共享一个可注入的 `RandomNumberGenerator`：

- 运行时随机初始化；
- 单元测试使用固定 seed；
- 数量抽样、候选抽样和合法位置抽样都可重复；
- 不直接使用全局 `randi()` 参与新机制。

生成服务对无效配置执行校验：

- 初始数量范围合法且 min 不大于 max；
- 数量权重 key 只允许 0、1、2；
- 权重非负且总权重大于 0；
- 候选模板非空且属于当前 `EventLib`；
- 候选权重合法；
- 未解决事件上限为正数；
- Boss 生成阈值为正数。

## 9. 测试计划

新增或调整：

- `exploration_spawn_config_test.gd`
- `event_spawn_candidate_test.gd`
- `exploration_event_service_test.gd`
- `initial_event_spawn_test.gd`
- `placement_event_spawn_test.gd`
- `boss_spawn_progress_test.gd`
- `guide_placement_spawn_test.gd`

必须覆盖：

1. 初始事件数量处于配置范围；
2. 初始池和动态池互不串用；
3. 动态结果可以是 0、1、2 个；
4. 所有事件均随机放在合法空位；
5. GUIDE 不触发动态生成；
6. ROOT 和普通牌触发动态生成；
7. 未解决事件上限生效；
8. Boss 按成功探索牌次数出现；
9. Boss 无合法位置时可以延迟生成；
10. Boss 仍通过普通接触流程触发；
11. Boss 追击开关和现有阶段配置保持有效；
12. 信仰值、RETREAT、回潮强化和 GUIDE 既有测试通过。

## 10. 迁移顺序

1. 新增配置 Resource 与候选 Resource；
2. 为 Ribwood 创建独立 `exploration_spawn_config.tres`；
3. 为 `EventPlacementService` 增加可测试的随机候选放置接口（如有必要）；
4. 重构 `ExplorationEventService`，先支持初始事件，再支持落牌后抽样；
5. 修改 `ExplorationCoordinator`，移除 FogService 调用；
6. 调整 GameManager / 初始化流程，在地图创建后调用初始事件生成；
7. 将 Boss 出现条件迁移为成功探索牌放置次数；
8. 删除无引用的迷雾代码和旧配置字段；
9. 补充测试并运行全量 Godot 测试；
10. 检查资源 UID、`git diff --check` 和工作树状态。

## 11. 验收标准

- 游戏开始时棋盘已有配置数量的事件；
- 玩家放置 ROOT 或普通牌后可能生成 0～2 个事件；
- GUIDE 放置不会触发动态事件，也不会推进 Boss 出现进度；
- 事件生成位置完全来自全棋盘合法随机位置；
- 每关可通过独立配置控制事件池、数量、权重和上限；
- Boss 仍以普通事件形式出现并由落牌接触触发；
- 取消迷雾后不存在未使用的迷雾驱动路径；
- 现有战斗、信仰值、Boss 追击和卡牌相关测试不回归。
