# 探索架构与引导牌整合实施计划

> **实施方式：** 每个任务必须先写 SceneTree 回归测试，确认失败后再写最小实现；每个任务完成后独立提交。计划文件按项目约定存放在 `docs/plans/`，**不写入任何 `superpower` / `superpowers` 目录**。

**目标：** 将探索、事件、Boss 追击、引导牌与信仰值的流程从 `GameManager` 中拆出稳定边界，使关卡配置独立、卡牌放置具有单一提交语义，并能安全整合 `codex/guide-card` 分支。

**架构：** `Board` 只维护棋盘空间与卡牌链变换，提交一次结构变化后给出 `BoardPlacementResult`。`ExplorationCoordinator` 处理“揭雾 → 生成事件 → 推进 Boss → 请求事件交互”的固定顺序；`EventInteractionController` 处理商店、宝藏、战斗和结算。`GameManager` 仅组装场景、运行时数据和视图层信号。

**技术栈：** Godot 4.7、GDScript、现有 SceneTree headless 测试、Git worktree。

## 当前分支与约束

- 当前开发工作树：`D:\project\MonoCard\mono-card\.worktrees\codex-fog-boss-exploration`。
- 当前工作分支：`codex/fog-boss-exploration`。
- 主分支 `master` 当前位于提交 `3ab1ee9`；它包含市场 / HUD 更新，不能被覆盖或重置。
- `codex/guide-card` 位于提交 `6e29c65`，从 `b6b683f` 分出，包含两项代码提交：
  - `f7255e2 feat: add guide card type`
  - `6e29c65 feat: add guide card board behavior`
- `codex/guide-card` 与当前探索工作树共同修改 `scripts/game/board.gd` 和 `scripts/game_manager.gd`，不能直接在当前脏工作树中合并。
- 当前探索工作树已有未提交的迷雾 / Boss / 事件架构 WIP；其中 `tests/boss_pressure_board_test.gd` 已新增“放牌提交必须先于事件交互”的失败用例，当前应保持 RED，直到任务 2 实现。
- 不修改主分支；不使用 `git reset --hard`、`git clean` 或任何会清除用户未提交文件的操作。
- 第一关《肋骨林地》的事件、怪物、商店、宝藏与探索参数必须是关卡独立数据。
- GUIDE 不直接依赖 `HandArea`；Board 只能发出请求，回手由上层服务负责。
- **Boss 是普通事件：** Boss 必须始终以 `EventInstance` / `BoardEvent` 的既有事件链路处理。`BossPressureService` 只允许通过 `Board.move_event()` 修改 Boss 的 `origin`；不得创建专属触发入口、专属交互状态、专属清理路径或改变事件重叠判定。

---

## 强制执行顺序与工作树切换

当前 `codex/fog-boss-exploration` 工作树含有未提交 WIP，且 `tests/boss_pressure_board_test.gd` 中存在刻意保留的 RED 用例。因此任务编号不代表可以任意重排，必须按下面的门槛执行：

1. **在当前探索工作树执行任务 1、任务 2**：先把关卡配置和原子放牌事务做成 GREEN；此阶段不合并 GUIDE 分支，也不修改 `master`。
2. **Gate A**：任务 1、2 的相关测试全部通过，创建只包含探索基础改动的可回滚提交。
3. **在新工作树执行任务 0**：从最新 `master` 创建 `codex/exploration-architecture`，应用 Gate A 的探索提交，再整合 `codex/guide-card`；手动解决 `board.gd` 与 `game_manager.gd` 的冲突。
4. **Gate B**：集成分支的原子放牌与 GUIDE 基础测试通过。此后只在新的集成工作树继续执行任务 3、4、5、6、7。
5. **Gate C**：全部 headless 回归测试和 `git diff --check master...HEAD` 通过后，才允许发起合并审查；绝不在此流程中重置或清理主工作树。

---

## 目标目录与职责

```text
scripts/game/
├── board.gd                               # 网格占用、卡牌链空间变换、事件格占用
├── board_placement_result.gd              # 一次放牌提交的不可变结果
├── exploration/
│   ├── exploration_config.gd              # 关卡探索节奏 Resource
│   ├── exploration_coordinator.gd         # 揭雾、动态事件、Boss 追击 / 拦截的事务编排
│   ├── fog_service.gd                     # 已揭开格子状态
│   ├── exploration_event_service.gd       # 根据关卡 EventLib 生成事件
│   └── boss_pressure_service.gd           # Boss 阶段与占格移动
├── event/
│   └── event_interaction_controller.gd    # 商店、宝藏、遭遇的交互状态与结束事件
└── player/
    └── faith_service.gd                   # 信仰值与确认后的拆链惩罚

data/levels/ribwood/
├── event_lib.tres
└── exploration_config.tres

tests/
├── board_placement_transaction_test.gd
├── guide_card_test.gd
├── exploration_coordinator_test.gd
├── boss_pressure_board_test.gd
├── event_interaction_controller_test.gd
└── game_manager_faith_test.gd
```

---

## 核心接口约定

### `BoardPlacementResult`

```gdscript
class_name BoardPlacementResult
extends RefCounted

enum Kind {
    CHAIN_EXTENDED,
    GUIDE_RESOLVED,
}

var kind: Kind
var source_card: CardEntity
var chain_tail: CardEntity
var affected_cards: Array[CardEntity]
var newly_occupied_cells: Array[Vector2i]
var overlapped_event: EventInstance
```

- `CHAIN_EXTENDED`：ROOT 或普通卡牌进入 `Board.cards` 后产生；会推进 Boss 计数。
- `GUIDE_RESOLVED`：引导牌推动现有链后产生；引导牌不进入 `Board.cards`。
- `overlapped_event` 只记录空间重叠，不在 `Board.add_card()` 内立即开始事件。
- `newly_occupied_cells` 仅包含提交前未被牌链占用、提交后由牌链占用的格子；它使揭雾服务无需反推变换。

### Boss 的普通事件不变量

```text
BossPressureService 只移动 BoardEvent
→ Board 以既有事件格重叠逻辑写入 BoardPlacementResult.overlapped_event
→ ExplorationCoordinator 发出既有 event_interaction_requested
→ EventInteractionController.begin() 按 EventData.EventType.BOSS 进入既有遭遇流程
→ 胜利后走既有事件完成 / 移除接口；RETREAT 走既有残响强化与事件保留接口
```

禁止为 Boss 增加 `event_selected`、点击入口、独立战斗入口或独立事件移除 API。`INTERCEPTING` 是 `BossPressureService` 的位置阶段，**不是**事件处理阶段。

### `ExplorationCoordinator`

```gdscript
signal event_interaction_requested(instance: EventInstance)
signal event_spawned(event_node: BoardEvent)

func configure(event_lib: EventLib, board: Board, config: ExplorationConfig) -> bool
func resolve_placement(result: BoardPlacementResult) -> void
func dismiss_defeated_boss(instance: EventInstance) -> bool
```

处理顺序必须固定：

```text
Board.add_card 成功
→ Board.placement_committed(result)
→ ExplorationCoordinator.resolve_placement(result)
→ FogService 揭雾
→ ExplorationEventService 动态生成事件
→ 若本次接触的是已存在的 Boss：跳过 Boss 推进，保留其位置
→ 否则仅推进本次放牌前已登记的 Boss（新生成 Boss 不吃到本次计数）
→ 若 result.overlapped_event 未结算，发出 event_interaction_requested
```

### Guide 的探索语义（本计划的默认决策）

- GUIDE 是一次**空间重排**，不是牌链延长；不增加 `BossPressureService` 的“放牌次数”。
- GUIDE 会用 `newly_occupied_cells` 揭开被牌链首次推入的新格，以避免玩家借位移绕过迷雾。
- GUIDE 若让牌链移入未结算事件格，仍会在该次事务末尾发起该事件。
- GUIDE 完成后通过 `Board.card_return_requested(card)` 请求上层回手；回手失败必须保留恢复路径，不能丢卡。

---

## 任务 0：建立安全集成基线（仅在 Gate A 后的新集成工作树执行）

**文件：** 不直接修改游戏代码。

- [ ] 记录当前工作树状态、任务 2 的刻意 RED 用例以及已通过的迷雾 / 事件生成测试；不得把已知 RED 用例误判为集成失败。
- [ ] 在探索 WIP 可通过其已有测试后，创建一个仅含探索工作提交的分支提交；不要提交主分支的 HUD 文件。
- [ ] 从最新 `master` 创建新的集成工作树，例如 `codex/exploration-architecture`。
- [ ] 在新集成工作树依次整合：探索提交 → `codex/guide-card` 的两项代码提交；只把其历史计划文档排除在外。
- [ ] 手动处理 `board.gd`、`game_manager.gd` 的冲突，禁止“选择 ours/theirs”整文件覆盖。

**验证：**

```powershell
# 确认集成分支包含两个功能提交且基于 master
 git log --oneline master..HEAD
 git diff --check master...HEAD
```

**提交建议：** 不在这一任务单独产生游戏功能提交；集成前必须保证每个来源分支有可回滚提交。

---

## 任务 1：关卡探索配置资源化

**文件：**
- Create: `scripts/game/exploration/exploration_config.gd`
- Create: `data/levels/ribwood/exploration_config.tres`
- Modify: `scenes/game/game_manager.tscn`
- Modify: `scripts/game_manager.gd`
- Test: `tests/exploration_config_test.gd`
- Test: `tests/boss_pressure_config_test.gd`

**接口：**

```gdscript
class_name ExplorationConfig
extends Resource

@export var scheduled_event_reveal_thresholds: Array[int]
@export var boss_reveal_threshold: int
@export var boss_pursuit_enabled: bool
@export var cards_to_boss_surround: int
@export var cards_to_boss_intercept: int
func validate() -> String
```

**追击开关语义：**

- `boss_pursuit_enabled = false`：Boss 仍在 `boss_reveal_threshold` 达成后按当前关卡规则生成，保持普通事件占格；不会因后续放牌移动。玩家的卡牌与 Boss 格重叠时自动进入 Boss 战。
- `boss_pursuit_enabled = true`：Boss 生成后，普通牌链成功延长 `cards_to_boss_surround` 次进入 `SURROUNDING`；再成功延长 `cards_to_boss_intercept` 次进入 `INTERCEPTING`，移动到牌头连接格。
- `INTERCEPTING` 只表示“下一张牌链必经此处并接触 Boss”，不是禁止放牌。Boss 事件不能写入 Board 的禁止放牌占格表。
- GUIDE 的空间重排不计入上述计数；ROOT 与普通卡牌的成功链延长才计入。

- [x] 写失败测试：`RibwoodExplorationConfig` 的阈值必须等于 `[4, 8, 14, 20, 22]`、`24`、追击开关 `true`、`2`、`2`。
- [x] 写失败测试 `test_disabled_pursuit_keeps_boss_stationary`：服务配置为关闭追击时，即使连续记录普通牌链延长，Boss 仍保持 `ACTIVE` 且事件 `origin` 不变。
- [x] 运行：

```powershell
& $godot --headless --path $project --user-data-dir $user --script res://tests/exploration_config_test.gd
```

预期：资源或类不存在导致失败。

- [x] 实现 Resource 与 `.tres`，并在 `GameManager` 导出 `exploration_config`；禁止在 `init_events()` 保留 `[4, 8, 14, 20, 22]` 与 `24` 的硬编码。
- [x] 将 `BossPressureService.Phase.BLOCKING` 更名为 `INTERCEPTING`，实现 `configure(enabled, surround_threshold, intercept_threshold)`；关闭追击时 Boss 保持 `ACTIVE` 且绝不移动。
- [x] 重跑配置、追击配置和 `GameManager` 运行初始化测试，确认通过。
- [ ] 在任务 2 完成后，作为 Gate A 探索基础提交的一部分提交：`refactor(exploration): move Ribwood pacing into level config`。

---

## 任务 2：把放牌变成单一事务并修正信号顺序

**文件：**
- Create: `scripts/game/board_placement_result.gd`
- Modify: `scripts/game/board.gd`
- Test: `tests/board_placement_transaction_test.gd`
- Test: `tests/boss_pressure_board_test.gd`

**接口：**

```gdscript
signal placement_committed(result: BoardPlacementResult)
signal event_interaction_requested(instance: EventInstance)
signal card_return_requested(card: CardEntity)

func add_card(card: CardEntity) -> bool
```

- [ ] 先写失败测试 `test_chain_placement_emits_commit_before_event_request`：在普通残响格上成功放 ROOT，断言信号顺序为：

```gdscript
["placement_committed", "event_interaction_requested"]
```

- [ ] 运行单测，预期现有实现失败（当前 `event_triggered` 早于 `card_placed`）。
- [ ] 实现 `BoardPlacementResult`，由 `Board.add_card()` 在所有网格 / 卡牌链变更完成后创建结果。
- [ ] 改为只发出 `placement_committed(result)`；由一个延后到同一事务末尾的 `request_event_interaction(result.overlapped_event)` 发出交互请求。删除“先 `event_triggered`、后 `card_placed`”的流程。
- [ ] 不为 Boss 增加点击入口：所有事件（含 Boss）只通过 `result.overlapped_event` 发起交互。Boss 位于牌头连接格时，该格仍必须允许放牌重叠。
- [ ] 运行该测试和现有 Boss 测试；两者必须通过。
- [ ] 提交：`refactor(board): publish atomic placement transactions`。

---

## 任务 3：整合 GUIDE 卡牌到放牌事务

**文件：**
- Modify: `scripts/card/card_data.gd`
- Modify: `scripts/card/card_detail_format.gd`
- Modify: `scripts/game/board.gd`
- Modify: `scripts/game_manager.gd`
- Create: `tests/guide_card_test.gd`
- Modify: `tests/game_manager_run_setup_test.gd`

**接口：**

```gdscript
# CardData
 enum CardType { ROOT, NORMAL, GUIDE }

# Board
signal card_return_requested(card: CardEntity)
# GUIDE 成功时发出 placement_committed(result.kind == GUIDE_RESOLVED)
```

- [ ] 先从 `codex/guide-card` 迁入其原有的 GUIDE 类型与基础迁移测试；确认 `GUIDE` 是独立枚举值。
- [ ] 写失败测试 `test_guide_result_keeps_chain_order_and_reports_new_cells`：放置 GUIDE 后，原牌链顺序不变、引导牌不在 `Board.cards`、最后一张牌占据引导牌原位置，且 `BoardPlacementResult.kind == GUIDE_RESOLVED`。
- [ ] 写失败测试 `test_guide_does_not_increment_boss_pressure`：将 Boss 压力服务配置为 `1/1`，仅提交 GUIDE 后 Boss 阶段保持 `ACTIVE`。
- [ ] 实现 GUIDE 的链快照迁移和 `_rebuild_grid_owner()`；禁止 GUIDE 直接调用 `event_triggered`。
- [ ] 由 `GameManager` / 卡牌区域服务接收 `card_return_requested` 并执行安全回手；手牌满时临时扩容一格以保证“玩家已有的 Guide 卡”不丢失。
- [ ] 更新 `CardDetailFormat`，将 GUIDE 显示为 `GUIDE` 而不是普通 `CARD`。
- [ ] 运行：

```powershell
& $godot --headless --path $project --user-data-dir $user --script res://tests/guide_card_test.gd
& $godot --headless --path $project --user-data-dir $user --script res://tests/game_manager_run_setup_test.gd
```

- [ ] 提交：`feat(cards): integrate guide card placement transaction`。

---

## 任务 4：收敛迷雾、动态事件与 Boss 追击到协调器

**文件：**
- Modify: `scripts/game/exploration/exploration_coordinator.gd`
- Modify: `scripts/game/exploration/fog_service.gd`
- Modify: `scripts/game/exploration/exploration_event_service.gd`
- Modify: `scripts/game/exploration/boss_pressure_service.gd`
- Modify: `scripts/game_manager.gd`
- Create: `tests/exploration_coordinator_test.gd`

**接口：**

```gdscript
func resolve_placement(result: BoardPlacementResult) -> void
func dismiss_defeated_boss(instance: EventInstance) -> bool
```

- [ ] 写失败测试 `test_chain_extension_reveals_then_spawns_then_requests_event`，通过记录三个信号断言顺序：`fog_revealed`、`event_spawned`、`event_interaction_requested`。
- [ ] 写失败测试 `test_guide_reveals_new_cells_without_advancing_boss_pressure`。
- [ ] 写失败测试 `test_disabled_boss_pursuit_keeps_revealed_boss_stationary`：`boss_pursuit_enabled = false` 时，在 Boss 生成后连续提交普通牌链，Boss 原点和阶段必须保持 `ACTIVE`。
- [ ] 写失败测试 `test_intercepting_boss_allows_next_card_to_overlap`：Boss 位于牌头连接格时，`Board.can_place_card()` 返回 true；提交结果的 `overlapped_event` 必须是该 Boss。
- [ ] 写失败测试 `test_contacted_boss_does_not_move_before_interaction`：处于 `SURROUNDING` 或 `INTERCEPTING` 的 Boss 被本次卡牌接触时，协调器不得调用其推进 / 移动；事件请求时 Boss 仍在被接触格。
- [ ] 写失败测试 `test_newly_revealed_boss_does_not_consume_its_first_pressure_count`：本次揭雾刚生成 Boss 时，Boss 阶段为 `ACTIVE`，计数为零；必须等待下一张成功延长的普通牌链。
- [ ] 写失败测试 `test_defeated_intercepting_boss_is_removed_from_event_grid`：Boss 位于最后一张牌的头部连接格，调用 `dismiss_defeated_boss()` 后，事件占格查询不再返回该 Boss，且 `Board.events` 不再包含 Boss；该格从来不能进入禁止放牌的阻塞表。
- [ ] 将 `FogService`、`ExplorationEventService`、`BossPressureService` 的创建与连接移入 `ExplorationCoordinator`。
- [ ] 写失败测试 `test_boss_contact_uses_the_same_event_request_path_as_monster`：普通残响与 Boss 分别被卡牌接触时，协调器均只发出 `event_interaction_requested(instance)`；除事件模板类型外，不得存在 Boss 专用的 Board / 交互控制器入口。
- [ ] `resolve_placement()` 在揭雾前记录“本次放牌前是否已有已登记 Boss”；只对这个既有 Boss 推进。若 `result.overlapped_event` 是该 Boss，则跳过推进，避免 Boss 在开始战斗前移走。
- [ ] `GameManager._on_board_placement_committed()` 只能调用：

```gdscript
_exploration_coordinator.resolve_placement(result)
```

- [ ] Boss 出现时由协调器登记；Boss 完成战斗时由协调器清理，不允许 `GameManager` 直接操作 Board 的事件占格或 Boss 状态。
- [ ] 运行协调器、迷雾、事件生成、Boss 测试。
- [ ] 提交：`refactor(exploration): coordinate fog events and boss pressure`。

---

## 任务 5：拆出仅由卡牌接触触发的事件交互

**文件：**
- Create: `scripts/game/event/event_interaction_controller.gd`
- Modify: `scripts/game/event.gd`
- Modify: `scripts/game_manager.gd`
- Test: `tests/event_interaction_controller_test.gd`
- Test: `tests/boss_pressure_board_test.gd`

**接口：**

```gdscript
signal interaction_started(instance: EventInstance)
signal interaction_finished(instance: EventInstance)
signal combat_result_ready(instance: EventInstance, result: CombatResult)

func begin(instance: EventInstance, player_stats: CombatStats, chain: Array[CardInstance]) -> void
func confirm_combat_settlement() -> void
func close_shop() -> void
func claim_treasure(option_index: int) -> void
```

- [ ] 写失败测试 `test_intercepting_boss_starts_encounter_when_next_card_contacts_it`：Boss 位于牌头连接格时，下一张合法卡牌可完成提交，并在协调器完成揭雾 / 动态生成 / 追击更新后产生一次 `interaction_started(BOSS)`；不得依赖 `SelectButton`。
- [ ] 写失败测试 `test_boss_victory_removes_intercepting_event`：Boss 胜利后由协调器移除事件节点和事件占格，再发出 `interaction_finished`。
- [ ] 删除 `BoardEvent.set_interactable()`、`event_selected` 和 Boss 点击入口；`BoardEvent` 仅负责显示，普通事件和 Boss 都只能由卡牌接触触发。
- [ ] 将 `GameManager` 中 `_active_event`、`_pending_combat_instance`、`_pending_combat_result` 的状态迁移到控制器；`GameManager` 仅负责转给模态视图和更新 HUD。
- [ ] 运行 Boss、交互控制器与 Combat 相关回归测试。
- [ ] 提交：`refactor(events): isolate event interaction lifecycle`。

---

## 任务 6：把手动拆链改为确认后的信仰事务

**文件：**
- Create: `scripts/game/chain_retraction_transaction.gd`
- Modify: `scripts/game/drag_layer.gd`
- Modify: `scripts/player/faith_service.gd`
- Modify: `scripts/game_manager.gd`
- Test: `tests/game_manager_faith_test.gd`
- Create: `tests/drag_layer_retraction_test.gd`

**接口：**

```gdscript
signal chain_retraction_confirmed(transaction: ChainRetractionTransaction)

class_name ChainRetractionTransaction
extends RefCounted
var removed_card: CardEntity
var returned_followers: Array[CardEntity]
var original_chain_size: int
```

- [ ] 写失败测试 `test_cancelled_board_drag_does_not_spend_faith`：拖起棋盘牌后因事件锁取消并恢复原链，`PlayerData.faith` 不变且无 `echo_spawn_requested`。
- [ ] 写失败测试 `test_confirmed_retraction_at_non_positive_faith_requests_echo`：完成拆链回手时，信仰不高于零则请求残响生成一次。
- [ ] 写失败测试 `test_guide_return_does_not_spend_faith`：GUIDE 的自动回手不是拆牌，不发出确认拆链信号。
- [ ] DragLayer 在拖拽开始时只创建并保留事务快照；只有最终回手 / 确认拆除后才发出 `chain_retraction_confirmed`。
- [ ] FaithService 只监听确认信号，继续通过 `PlayerData.faith` 统一存储并对外暴露当前值。
- [ ] 残响生成请求只送入探索协调器，由当前关卡 `EventLib` 的 MONSTER 模板放置，避免 GameManager 同时持有两套事件生成路径。
- [ ] 提交：`refactor(faith): charge only confirmed chain retractions`。

---

## 任务 7：瘦身 `GameManager` 并完成回归门槛

**文件：**
- Modify: `scripts/game_manager.gd`
- Modify: `scenes/game/game_manager.tscn`
- Modify: 对应测试中直接依赖旧私有字段的夹具
- Modify: `docs/design/2026-08-04-fog-exploration-boss-pressure-design.md`

**验收边界：**

`GameManager` 仅保留：

1. 运行时 `PlayerData` / 起始牌组初始化；
2. 场景节点与 HUD / 模态视图装配；
3. `ExplorationCoordinator`、`EventInteractionController`、`FaithService` 的连接；
4. 运行结束和视图层信号转发。

`GameManager` 不再直接持有 `FogService`、`ExplorationEventService`、`BossPressureService`，不再负责事件放置顺序，也不直接修改 Boss 事件占格。

- [ ] 写静态结构测试：`scripts/game_manager.gd` 不包含 `FogService.new()`、`ExplorationEventService.new()`、`BossPressureService.new()` 和事件阈值数组字面量。
- [ ] 运行完整 headless 关键回归：

```powershell
$tests = @(
  'tests/board_placement_transaction_test.gd',
  'tests/guide_card_test.gd',
  'tests/exploration_config_test.gd',
  'tests/exploration_coordinator_test.gd',
  'tests/fog_service_test.gd',
  'tests/exploration_event_service_test.gd',
  'tests/boss_pressure_board_test.gd',
  'tests/event_interaction_controller_test.gd',
  'tests/drag_layer_retraction_test.gd',
  'tests/game_manager_faith_test.gd'
)
foreach ($test in $tests) {
  & $godot --headless --path $project --user-data-dir $user --script ("res://" + $test)
  if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}
```

- [ ] 执行 `git diff --check master...HEAD`，确认无空白错误。
- [ ] 更新设计文档：记录 `GUIDE_RESOLVED` 不推进 Boss 计数、Boss 拦截状态通过下一张卡牌接触开战、信仰只在确认拆链时扣除。
- [ ] 提交：`refactor(game): reduce game manager to composition root`。

---

## 计划审查

- **迷雾 / 动态事件 / Boss 追击：** 任务 1、2、4、5 覆盖；并明确修复现有“事件先于探索更新”和“Boss 占格无法挑战 / 胜利不释放”问题。
- **Guide Card 未合并：** 任务 0 处理安全整合，任务 3 在统一放牌事务中实现，避免其旧 `event_triggered` 时序重新引入架构问题。
- **信仰值：** 任务 6 覆盖取消拖拽误扣、低信仰生成残响和 GUIDE 不误扣。
- **关卡独立内容：** 任务 1 用 `data/levels/ribwood/exploration_config.tres` 固化第一关节奏；后续关卡只需新增自己的 `EventLib + ExplorationConfig`。
- **不覆盖主分支：** 任务 0 明确要求所有整合在独立工作树进行，禁止使用破坏性 Git 命令。
