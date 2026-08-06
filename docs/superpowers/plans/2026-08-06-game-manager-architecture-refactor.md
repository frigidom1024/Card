# GameManager 核心架构渐进式重构实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将 `GameManager` 重构为只负责场景组合的根节点，把牌链结算、探索放牌流水线、事件交互、战斗结算、运行状态和表现层同步拆分为可独立测试的协调器，同时保持现有卡牌、战斗、Boss 接触事件、Faith、RETREAT、商店、宝藏和 Ribwood 数据行为不变。

**Architecture:** 新增 `RunContext` 作为本局可变数据图的唯一入口；新增 `PlacementPipelineCoordinator` 明确执行“牌链规则 → 探索响应 → 事件交互”的顺序；新增 `RunFlowCoordinator` 统一管理探索/交互/失败/通关状态。`GameManager` 只创建对象、连接场景节点和转发公开兼容信号，不再直接执行领域规则或控制战斗结算。

**Tech Stack:** Godot 4.7 GDScript、`RefCounted` 协调器、Godot signals、现有 `tests/*.gd` headless 测试脚本、PowerShell。

## Global Constraints

- 不修改卡牌数值、CardRule 效果、战斗点数/护甲规则、Ribwood 事件资源、Boss 阈值、掉落规则或 UI 视觉布局。
- Boss 必须继续使用普通 `BOSS` 事件：放置卡牌接触事件 → 普通事件交互 → 战斗 → 结算；追击服务只允许修改事件坐标。
- Boss 追击开关继续由 `ExplorationConfig.boss_pursuit_enabled` 控制。
- `CardRule` 只能由牌链域协调器/规则服务执行，`ExplorationCoordinator` 不得执行 CardRule。
- Faith 收回牌链、Faith ≤ 0 时生成残响、RETREAT 收回末尾卡牌和怪物强化必须保持现有行为。
- 不恢复或修改用户已有的 `addons/godot-git-plugin/windows/~libgit_plugin.windows.editor.x86_64.dll` 删除状态。
- 保留 `scripts/game_manager.gd` 中 `_center_layout()` 的提前 `return`，本轮不恢复布局代码。
- 所有新增/修改 GDScript 必须通过 Godot 编辑器扫描和目标测试；完成前运行完整 `tests/*.gd` 扫描。

## 文件清单与边界

### 新增文件

- `scripts/game/run/run_context.gd`：持有一次运行的玩家数据、战斗属性、卡牌服务、事件控制器和随机服务。
- `scripts/game/run/run_random_service.gd`：提供市场、宝藏、遭遇掉落三个独立随机流。
- `scripts/game/placement/placement_pipeline_coordinator.gd`：唯一接收 `Board.placement_committed` 的运行流水线。
- `scripts/game/run/run_flow_coordinator.gd`：运行状态机和跨域流程编排。
- `scripts/game/run/run_presentation_coordinator.gd`：手牌、玩家 HUD、交互锁的表现层适配。
- `tests/run_context_test.gd`：运行时状态图和随机流测试。
- `tests/placement_pipeline_coordinator_test.gd`：放牌阶段顺序和单次事件触发测试。
- `tests/run_flow_coordinator_test.gd`：运行状态和结算生命周期测试。
- `tests/run_presentation_coordinator_test.gd`：表现层信号同步测试。

### 修改文件

- `scripts/game/run/run_setup_coordinator.gd`：初始化并返回 `RunContext`，保留旧 getter 作为迁移兼容接口。
- `scripts/card/card_chain_coordinator.gd`：取消对 `Board.placement_committed` 的信号订阅，只保留显式 `resolve_placement(result)`。
- `scripts/game/exploration/exploration_coordinator.gd`：保留探索事件响应与 Boss 位置移动，确保由流水线显式调用。
- `scripts/game/event/event_modal_coordinator.gd`：战斗确认时不提前隐藏窗口，只有结算成功后才完成 modal 生命周期。
- `scripts/game/event/encounter/encounter_resolution_coordinator.gd`：去掉对完整 `ExplorationCoordinator` 的依赖，改为 Boss 移除和事件刷新回调端口。
- `scripts/game_manager.gd`：删除直接的放牌回调、跨域结算和 HUD 同步逻辑，改为组合新协调器并保留公开兼容信号/只读兼容引用。
- `tests/card_chain_coordinator_test.gd`：改为验证显式调用，不再要求 CardChainCoordinator 自己订阅 Board。
- `tests/run_setup_coordinator_test.gd`：验证 RunContext 及其稳定引用图。
- `tests/game_manager_run_setup_test.gd`：验证新组合关系，并删除对已移除 `_on_board_placement_committed` 的旧断言。
- `tests/game_manager_architecture_test.gd`：增加架构边界断言。
- `tests/game_manager_combat_routing_test.gd`：验证普通怪物和 Boss 的接触式事件路径。
- `tests/event_modal_coordinator_test.gd`：验证失败结算时 modal 保持可恢复。
- `tests/encounter_resolution_coordinator_test.gd`：验证 Boss 通过回调端口移除。

---

### Task 1: 建立稳定的 RunContext 与独立随机流

**Files:**
- Create: `scripts/game/run/run_context.gd`
- Create: `scripts/game/run/run_random_service.gd`
- Create: `tests/run_context_test.gd`
- Modify: `scripts/game/run/run_setup_coordinator.gd`
- Modify: `tests/run_setup_coordinator_test.gd`

**Interfaces:**
- `RunRandomService.configure(seed_value: int = -1) -> void`
- `RunRandomService.market_rng() -> RandomNumberGenerator`
- `RunRandomService.treasure_rng() -> RandomNumberGenerator`
- `RunRandomService.encounter_reward_rng() -> RandomNumberGenerator`
- `RunContext.configure(player_data: PlayerData, player_stats: CombatStats, card_service: RunCardService, combat_flow: EncounterCombatFlowCoordinator, event_interaction_controller: EventInteractionController, random: RunRandomService) -> bool`
- `RunContext.is_valid() -> bool`
- `RunSetupCoordinator.get_context() -> RunContext`

- [ ] **Step 1: Write the failing tests**

在 `tests/run_context_test.gd` 添加以下断言：

```gdscript
func _test_context_owns_one_runtime_graph() -> void:
    var context := RunContext.new()
    var player := PlayerData.new()
    var stats := CombatStats.new()
    var cards := RunCardService.new()
    var flow := EncounterCombatFlowCoordinator.new(CombatService2.new())
    var interactions := EventInteractionController.new()
    var random := RunRandomService.new()
    _expect(context.configure(player, stats, cards, flow, interactions, random))
    _expect(context.is_valid())
    _expect(context.player_data == player)
    _expect(context.player_stats == stats)
    _expect(context.card_service == cards)
    _expect(context.event_interaction_controller == interactions)
    _expect(context.random == random)

func _test_seeded_random_streams_are_replayable() -> void:
    var first := RunRandomService.new()
    var second := RunRandomService.new()
    first.configure(12345)
    second.configure(12345)
    _expect(first.market_rng().randi() == second.market_rng().randi())
    _expect(first.treasure_rng().randi() == second.treasure_rng().randi())
    _expect(first.encounter_reward_rng().randi() == second.encounter_reward_rng().randi())
```

更新 `tests/run_setup_coordinator_test.gd`，要求成功初始化后 `get_context()` 非空，且 Context 内引用与旧 getter 返回对象相同。

- [ ] **Step 2: 运行测试确认失败**

```powershell
& 'D:\InstallPath\godot\Godot_v4.7-stable_win64_console.exe' --editor --headless --path . --quit
& 'D:\InstallPath\godot\Godot_v4.7-stable_win64_console.exe' --headless --path . --script res://tests/run_context_test.gd
```

预期：因 `RunContext`、`RunRandomService` 或 `RunSetupCoordinator.get_context()` 尚不存在而失败。

- [ ] **Step 3: 实现最小运行时上下文**

`RunContext` 使用公开只读语义字段（GDScript 中通过不提供替换入口约束）保存上述六个对象；`configure()` 拒绝任一 null；`is_valid()` 检查所有引用非空。

`RunRandomService.configure()` 在传入非负 seed 时使用该 seed 派生三个流的固定种子；传入 `-1` 时随机化主种子后派生三个流。不要让市场、宝藏和掉落共享同一个 RNG 对象。

`RunSetupCoordinator.initialize()` 创建随机服务并在所有运行对象创建完成后创建 `_context`；初始化失败时将 `_context` 置空；新增 `get_context()`。

- [ ] **Step 4: 运行测试确认通过**

```powershell
& 'D:\InstallPath\godot\Godot_v4.7-stable_win64_console.exe' --headless --path . --script res://tests/run_context_test.gd
& 'D:\InstallPath\godot\Godot_v4.7-stable_win64_console.exe' --headless --path . --script res://tests/run_setup_coordinator_test.gd
```

预期：两个测试均 PASS，且原有 RunSetup 测试保持通过。

- [ ] **Step 5: 提交**

```powershell
git add -- scripts/game/run/run_context.gd scripts/game/run/run_random_service.gd scripts/game/run/run_setup_coordinator.gd tests/run_context_test.gd tests/run_setup_coordinator_test.gd
git commit -m "refactor(run): centralize runtime context and random streams"
```

---

### Task 2: 让放牌流程由单一 PlacementPipelineCoordinator 编排

**Files:**
- Create: `scripts/game/placement/placement_pipeline_coordinator.gd`
- Create: `tests/placement_pipeline_coordinator_test.gd`
- Modify: `scripts/card/card_chain_coordinator.gd`
- Modify: `scripts/game/exploration/exploration_coordinator.gd`
- Modify: `tests/card_chain_coordinator_test.gd`

**Interfaces:**
- `PlacementPipelineCoordinator.configure(board: Board, card_chain: CardChainCoordinator, exploration: ExplorationCoordinator) -> bool`
- `PlacementPipelineCoordinator.connect_board() -> bool`
- `PlacementPipelineCoordinator.resolve_placement(result: BoardPlacementResult) -> void`
- signal `event_interaction_requested(instance: EventInstance)`
- signal `placement_resolved(result: BoardPlacementResult, card_rules_applied: int)`

- [ ] **Step 1: Write the failing tests**

使用测试替身记录顺序：

```gdscript
func _test_card_rules_run_before_exploration() -> void:
    var order: Array[String] = []
    var pipeline := PlacementPipelineCoordinator.new()
    var card_chain := _make_recording_card_chain(order)
    var exploration := _make_recording_exploration(order)
    var board := _make_board()
    _expect(pipeline.configure(board, card_chain, exploration))
    _expect(pipeline.connect_board())
    board.placement_committed.emit(_make_chain_extended_result())
    _expect(order == ["card_chain", "exploration"])

func _test_pipeline_emits_contact_once() -> void:
    var received: Array[EventInstance] = []
    var pipeline := _configured_pipeline()
    pipeline.event_interaction_requested.connect(func(instance): received.append(instance))
    pipeline.resolve_placement(_make_result_with_contact())
    _expect(received.size() == 1)
```

`tests/card_chain_coordinator_test.gd` 增加：配置后 `board.placement_committed.get_connections()` 不包含 CardChainCoordinator；显式调用 `resolve_placement()` 仍会应用规则。

- [ ] **Step 2: 运行测试确认失败**

```powershell
& 'D:\InstallPath\godot\Godot_v4.7-stable_win64_console.exe' --headless --path . --script res://tests/placement_pipeline_coordinator_test.gd
```

预期：找不到新类型，或现有 CardChain 仍是 Board 的订阅者导致顺序断言失败。

- [ ] **Step 3: 实现显式流水线**

`CardChainCoordinator.configure(board)` 只保存 Board，不再连接/断开 `placement_committed`；删除 `_on_placement_committed()`。`resolve_placement()` 保持现有 `CHAIN_EXTENDED` 检查和 CardRule 逻辑。

`PlacementPipelineCoordinator.configure()` 保存三个对象；`connect_board()` 只连接一次 `Board.placement_committed` 到自身 `_on_placement_committed()`。回调调用 `resolve_placement()`，先调用 `card_chain.resolve_placement(result)`，再调用 `exploration.resolve_placement(result)`；Exploration 的 `event_interaction_requested` 在配置时转发到流水线信号。

流水线不直接执行 CardRule，不直接创建事件；它只按固定顺序调用两个域协调器。

- [ ] **Step 4: 运行测试确认通过**

```powershell
& 'D:\InstallPath\godot\Godot_v4.7-stable_win64_console.exe' --editor --headless --path . --quit
& 'D:\InstallPath\godot\Godot_v4.7-stable_win64_console.exe' --headless --path . --script res://tests/placement_pipeline_coordinator_test.gd
& 'D:\InstallPath\godot\Godot_v4.7-stable_win64_console.exe' --headless --path . --script res://tests/card_chain_coordinator_test.gd
```

预期：牌链规则先于探索响应，事件接触只发出一次。

- [ ] **Step 5: 提交**

```powershell
git add -- scripts/game/placement/placement_pipeline_coordinator.gd scripts/card/card_chain_coordinator.gd scripts/game/exploration/exploration_coordinator.gd tests/placement_pipeline_coordinator_test.gd tests/card_chain_coordinator_test.gd
git commit -m "refactor(placement): centralize card and exploration ordering"
```

---

### Task 3: 建立 RunFlowCoordinator 运行状态机

**Files:**
- Create: `scripts/game/run/run_flow_coordinator.gd`
- Create: `tests/run_flow_coordinator_test.gd`
- Modify: `scripts/game/event/event_modal_coordinator.gd`
- Modify: `scripts/game/event/encounter/encounter_resolution_coordinator.gd`

**Interfaces:**
- enum `State { UNINITIALIZED, EXPLORING, INTERACTING, FAILED, FINISHED }`
- `RunFlowCoordinator.configure(context: RunContext, pipeline: PlacementPipelineCoordinator, modal: EventModalCoordinator, resolution: EncounterResolutionCoordinator, faith: FaithService, board: Board) -> bool`
- `RunFlowCoordinator.start() -> bool`
- `RunFlowCoordinator.get_state() -> State`
- `RunFlowCoordinator.accepts_placement() -> bool`
- `RunFlowCoordinator.handle_combat_settlement_request(instance: EventInstance, result: CombatResult) -> bool`
- `RunFlowCoordinator.handle_card_return_requested(card: CardEntity) -> bool`
- signals `combat_started(instance, monster)`, `combat_resolved(instance, result)`, `exploration_failed(result)`, `run_finished`, `faith_changed(current_faith)`

- [ ] **Step 1: Write the failing state tests**

在 `tests/run_flow_coordinator_test.gd` 覆盖：

```gdscript
func _test_start_enters_exploring() -> void:
    var flow := _make_flow()
    _expect(flow.start())
    _expect(flow.get_state() == RunFlowCoordinator.State.EXPLORING)

func _test_contact_enters_interacting() -> void:
    var flow := _make_started_flow()
    flow.pipeline.event_interaction_requested.emit(_monster_event())
    _expect(flow.get_state() == RunFlowCoordinator.State.INTERACTING)

func _test_failed_settlement_keeps_modal_recoverable() -> void:
    var flow := _make_started_flow()
    flow.pipeline.event_interaction_requested.emit(_monster_event())
    _expect(not flow.handle_combat_settlement_request(null, null))
    _expect(flow.get_state() == RunFlowCoordinator.State.INTERACTING)

func _test_defeat_enters_failed_and_boss_victory_enters_finished() -> void:
    var flow := _make_started_flow()
    flow.resolution.exploration_failed.emit(_make_defeat_result())
    _expect(flow.get_state() == RunFlowCoordinator.State.FAILED)
    var boss_flow := _make_started_flow()
    boss_flow.pipeline.event_interaction_requested.emit(_boss_event())
    boss_flow.resolution.apply(_boss_event(), _make_victory_result())
    _expect(boss_flow.get_state() == RunFlowCoordinator.State.FINISHED)
```

- [ ] **Step 2: 运行测试确认失败**

```powershell
& 'D:\InstallPath\godot\Godot_v4.7-stable_win64_console.exe' --headless --path . --script res://tests/run_flow_coordinator_test.gd
```

预期：新协调器不存在，或状态尚未由统一对象维护。

- [ ] **Step 3: 实现状态机和事件路由**

`RunFlowCoordinator.start()` 只允许从 `UNINITIALIZED` 进入 `EXPLORING`；放牌流水线事件只在 `EXPLORING` 时接受，接触事件后进入 `INTERACTING` 并调用 `modal.begin(instance, context.player_stats, board.get_combat_card_chain())`。

战斗结算请求流程必须是：

```gdscript
func handle_combat_settlement_request(instance: EventInstance, result: CombatResult) -> bool:
    if _state != State.INTERACTING or instance == null or result == null:
        return false
    if not _resolution.apply(instance, result):
        return false
    _modal.complete_combat_settlement()
    combat_resolved.emit(instance, result)
    if result.outcome == CombatResult.Outcome.DEFEAT:
        _state = State.FAILED
        exploration_failed.emit(result)
    elif instance.get_event_type() == EventData.EventType.BOSS and result.outcome == CombatResult.Outcome.VICTORY:
        _state = State.FINISHED
        run_finished.emit()
    else:
        _state = State.EXPLORING
    return true
```

实际实现中不得重复发出 `EncounterResolutionCoordinator.exploration_failed`；由 Flow 统一消费该信号并完成一次状态转换。失败状态保持 DragLayer 锁定。

Faith 的 `faith_changed` 转发到公开兼容信号；`echo_spawn_requested` 调用 `ExplorationCoordinator.request_faith_echo()`。卡牌返回请求调用 `context.card_service.return_existing_to_hand(card, true)`，不得在 GameManager 中直接修改手牌数组。

- [ ] **Step 4: 运行测试确认通过**

```powershell
& 'D:\InstallPath\godot\Godot_v4.7-stable_win64_console.exe' --editor --headless --path . --quit
& 'D:\InstallPath\godot\Godot_v4.7-stable_win64_console.exe' --headless --path . --script res://tests/run_flow_coordinator_test.gd
& 'D:\InstallPath\godot\Godot_v4.7-stable_win64_console.exe' --headless --path . --script res://tests/event_modal_coordinator_test.gd
```

预期：探索、交互、失败、Boss 通关状态均可重复验证；失败结算不会隐藏并锁死 modal。

- [ ] **Step 5: 提交**

```powershell
git add -- scripts/game/run/run_flow_coordinator.gd scripts/game/event/event_modal_coordinator.gd scripts/game/event/encounter/encounter_resolution_coordinator.gd tests/run_flow_coordinator_test.gd tests/event_modal_coordinator_test.gd
git commit -m "refactor(run): centralize interaction and settlement lifecycle"
```

---

### Task 4: 将 EncounterResolutionCoordinator 改成窄端口

**Files:**
- Modify: `scripts/game/event/encounter/encounter_resolution_coordinator.gd`
- Modify: `tests/encounter_resolution_coordinator_test.gd`
- Modify: `tests/game_manager_combat_routing_test.gd`

**Interfaces:**

```gdscript
func configure(
    board: Board,
    player_stats: CombatStats,
    player_data: PlayerData,
    card_service: RunCardService,
    on_boss_dismissed: Callable,
    on_player_state_changed: Callable,
    on_event_display_refresh: Callable,
    reward_rng: RandomNumberGenerator
) -> bool
```

- [ ] **Step 1: 写失败测试**

在 `tests/encounter_resolution_coordinator_test.gd` 中传入三个记录 Callable，验证：

```gdscript
func test_boss_victory_uses_dismiss_callback() -> void:
    var dismissed := 0
    var refreshed := 0
    var resolver := EncounterResolutionCoordinator.new()
    _expect(resolver.configure(
        board,
        player_stats,
        player_data,
        card_service,
        func(_instance): dismissed += 1,
        func(): pass,
        func(_instance): refreshed += 1,
        rng
    ))
    _expect(resolver.apply(boss_instance, victory_result))
    _expect(dismissed == 1)
    _expect(refreshed == 0)
```

增加普通怪物胜利断言：Boss 回调不调用、刷新回调调用一次；RETREAT 仍然收回末尾卡牌并调用强化逻辑。

- [ ] **Step 2: 运行测试确认失败**

```powershell
& 'D:\InstallPath\godot\Godot_v4.7-stable_win64_console.exe' --headless --path . --script res://tests/encounter_resolution_coordinator_test.gd
```

预期：当前 `configure()` 需要 `ExplorationCoordinator` 实例，回调断言失败。

- [ ] **Step 3: 移除探索层硬依赖**

删除 `_exploration: ExplorationCoordinator` 字段；保存 `on_boss_dismissed`、`on_event_display_refresh` 两个 Callable。Boss 胜利调用 `on_boss_dismissed.call(instance)`；普通事件调用 `on_event_display_refresh.call(instance)`。如果回调无效，`configure()` 返回 false；不允许静默访问探索协调器。

保留 `_board` 仅用于牌桌末尾卡牌处理和兼容的事件牌桌访问；不把 Boss 追击或事件生成逻辑搬进结算器。

- [ ] **Step 4: 运行测试确认通过**

```powershell
& 'D:\InstallPath\godot\Godot_v4.7-stable_win64_console.exe' --headless --path . --script res://tests/encounter_resolution_coordinator_test.gd
& 'D:\InstallPath\godot\Godot_v4.7-stable_win64_console.exe' --headless --path . --script res://tests/game_manager_combat_routing_test.gd
```

预期：Boss 仍按普通接触式事件进入战斗，战胜后只通过端口移除事件；普通怪物不触发 Boss 回调。

- [ ] **Step 5: 提交**

```powershell
git add -- scripts/game/event/encounter/encounter_resolution_coordinator.gd tests/encounter_resolution_coordinator_test.gd tests/game_manager_combat_routing_test.gd
git commit -m "refactor(encounter): replace exploration dependency with ports"
```

---

### Task 5: 拆分 RunPresentationCoordinator

**Files:**
- Create: `scripts/game/run/run_presentation_coordinator.gd`
- Create: `tests/run_presentation_coordinator_test.gd`
- Modify: `scripts/game/event/event_modal_coordinator.gd`

**Interfaces:**
- `RunPresentationCoordinator.configure(hand_area: HandArea, hand_tray: HandTray, crest: PilgrimCrestHud, drag_layer: DragLayer, player_data: PlayerData, player_stats: CombatStats, faith: FaithService) -> bool`
- `RunPresentationCoordinator.bind(flow: RunFlowCoordinator, modal: EventModalCoordinator, market: PersistentMarketCoordinator) -> bool`
- `RunPresentationCoordinator.sync_all() -> void`
- `RunPresentationCoordinator.apply_lock_request(locked: bool) -> void`
- `RunPresentationCoordinator.is_input_locked() -> bool`
- `RunPresentationCoordinator.apply_flow_state(state: RunFlowCoordinator.State) -> void`

- [ ] **Step 1: 写失败测试**

```gdscript
func _test_hand_count_updates_tray() -> void:
    var presentation := _make_presentation()
    presentation.sync_all()
    _expect(hand_tray.last_count == hand_area.get_card_count())

func _test_failed_flow_cannot_unlock_input() -> void:
    var presentation := _make_presentation()
    presentation.apply_flow_state(RunFlowCoordinator.State.FAILED)
    presentation.apply_lock_request(false)
    _expect(presentation.is_input_locked())
```

- [ ] **Step 2: 运行测试确认失败**

```powershell
& 'D:\InstallPath\godot\Godot_v4.7-stable_win64_console.exe' --headless --path . --script res://tests/run_presentation_coordinator_test.gd
```

预期：新类型或其接口不存在。

- [ ] **Step 3: 实现表现层适配**

把当前 `GameManager._sync_hand_tray()`、`_sync_pilgrim_crest()`、`_on_faith_changed()`、`_on_modal_interaction_lock_changed()` 的具体 HUD/DragLayer 操作搬入该类。监听 `HandArea.hand_count_changed`、FaithService、PersistentMarketCoordinator 的 `player_state_changed`；监听 Flow 的失败状态并设置永久失败锁。

`apply_lock_request(false)` 在 Flow 状态为 `FAILED` 或 `FINISHED` 时不得解锁；不要把任何战斗奖励、事件 resolve 或卡牌规则写入表现层。

- [ ] **Step 4: 运行测试确认通过**

```powershell
& 'D:\InstallPath\godot\Godot_v4.7-stable_win64_console.exe' --headless --path . --script res://tests/run_presentation_coordinator_test.gd
```

预期：手牌数量、生命、金币、Faith 同步；失败状态维持输入锁定。若命令中的 Godot 可执行文件实际名称为 `Godot_v4.7-stable_win64_console.exe`，以该名称执行。

- [ ] **Step 5: 提交**

```powershell
git add -- scripts/game/run/run_presentation_coordinator.gd tests/run_presentation_coordinator_test.gd
 git commit -m "refactor(presentation): isolate run HUD and input synchronization"
```

---

### Task 6: 把 GameManager 收缩为场景组合根

**Files:**
- Modify: `scripts/game_manager.gd`
- Modify: `tests/game_manager_run_setup_test.gd`
- Modify: `tests/game_manager_architecture_test.gd`
- Modify: `tests/game_manager_combat_routing_test.gd`

**Interfaces:**

```gdscript
func configure_run(preset: StartingDeckData) -> bool
func get_run_context() -> RunContext
func get_run_flow() -> RunFlowCoordinator
```

兼容保留：

```gdscript
signal combat_started(instance: EventInstance, monster: MobInstance)
signal combat_resolved(instance: EventInstance, result: CombatResult)
signal exploration_failed(result: CombatResult)
signal run_initialization_failed(reason: String)
signal run_finished
signal faith_changed(current_faith: int)
```

- [ ] **Step 1: 写失败架构测试**

在 `tests/game_manager_architecture_test.gd` 增加源码/运行时断言：

```gdscript
_expect(not manager.has_method("_on_board_placement_committed"))
_expect(manager.board.placement_committed.get_connections().size() == 1)
_expect(manager.get_run_context() != null)
_expect(manager.get_run_flow() != null)
```

检查该唯一连接的目标是 `PlacementPipelineCoordinator`，不是 GameManager 或 CardChainCoordinator；检查 `CardChainCoordinator` 不再直接连接 Board。

- [ ] **Step 2: 运行测试确认失败**

```powershell
& 'D:\InstallPath\godot\Godot_v4.7-stable_win64_console.exe' --headless --path . --script res://tests/game_manager_architecture_test.gd
```

预期：当前 GameManager 仍连接不存在的 `_on_board_placement_committed`，且不存在新 getter。

- [ ] **Step 3: 重写 GameManager 的 `_ready()` 组合流程**

使用下面的固定顺序：

```gdscript
func _ready() -> void:
    if not _initialize_run_state():
        return
    _configure_persistent_market()
    _configure_event_modal()
    _configure_card_chain()
    _configure_exploration()
    _configure_encounter_resolution()
    _configure_placement_pipeline()
    _configure_run_flow()
    _configure_presentation()
    _configure_card_return_routing()
    _center_layout()
```

`_initialize_run_state()` 从 `RunSetupCoordinator.get_context()` 获取所有运行时引用；不再创建独立 `_market_rng`、`_encounter_reward_rng`、Faith runtime reference，改用 `context.random` 和 `context.player_data`。所有配置失败必须调用 `_fail_run_initialization(reason)`，不进入可探索状态。

`_configure_placement_pipeline()` 是唯一调用 `connect_board()` 的位置。`_configure_run_flow()` 连接新协调器信号到 GameManager 的兼容信号；GameManager 只转发，不处理结果。

保留 `_on_board_card_return_requested()` 作为兼容入口时，它只能调用 `_run_flow.handle_card_return_requested(card)`；不要直接操作 `hand_area.cards` 或 PlayerData。保留 `_center_layout()` 原样提前返回。

- [ ] **Step 4: 更新集成断言并运行测试**

删除旧断言：要求 GameManager 存在 `_on_board_placement_committed`。改为验证：

```gdscript
_expect(manager.board.placement_committed.get_connections().size() == 1)
_expect(manager.board.placement_committed.get_connections()[0].callable.get_object() is PlacementPipelineCoordinator)
_expect(manager.get_run_flow().get_state() == RunFlowCoordinator.State.EXPLORING)
```

运行：

```powershell
& 'D:\InstallPath\godot\Godot_v4.7-stable_win64_console.exe' --editor --headless --path . --quit
& 'D:\InstallPath\godot\Godot_v4.7-stable_win64_console.exe' --headless --path . --script res://tests/game_manager_run_setup_test.gd
& 'D:\InstallPath\godot\Godot_v4.7-stable_win64_console.exe' --headless --path . --script res://tests/game_manager_architecture_test.gd
& 'D:\InstallPath\godot\Godot_v4.7-stable_win64_console.exe' --headless --path . --script res://tests/game_manager_combat_routing_test.gd
```

预期：编辑器扫描无解析错误；普通怪物和 Boss 均通过放牌接触进入相同 EventModal/EncounterResolution 路径。

- [ ] **Step 5: 提交**

```powershell
git add -- scripts/game_manager.gd tests/game_manager_run_setup_test.gd tests/game_manager_architecture_test.gd tests/game_manager_combat_routing_test.gd
git commit -m "refactor(game-manager): reduce root to scene composition"
```

---

### Task 7: 完善生命周期、兼容信号和回归测试

**Files:**
- Modify: `scripts/game/run/run_flow_coordinator.gd`
- Modify: `scripts/game/run/run_presentation_coordinator.gd`
- Modify: `scripts/game_manager.gd`
- Modify: `tests/game_manager_combat_routing_test.gd`
- Modify: `tests/event_modal_coordinator_test.gd`
- Modify: `tests/guide_card_test.gd`

**Interfaces:**
- 失败后禁止任何新的放牌流水线调用。
- Boss 胜利只发出一次 `run_finished`，并且先完成普通事件结算/移除，再进入 `FINISHED`。
- 普通战斗胜利后回到 `EXPLORING`，事件交互控制器结束当前交互。
- RETREAT 后回到 `EXPLORING`，末尾卡牌返回手牌，残响获得一次强化。
- Faith 收回牌链事件仍委托 `FaithService`，Faith ≤ 0 时仍委托 `ExplorationCoordinator.request_faith_echo()`。

- [ ] **Step 1: 写回归测试**

增加如下行为断言：

```gdscript
func _test_failed_run_rejects_follow_up_placement() -> void:
    flow.resolution.exploration_failed.emit(_make_defeat_result())
    _expect(not flow.accepts_placement())

func _test_boss_finish_is_emitted_once() -> void:
    var count := 0
    flow.run_finished.connect(func(): count += 1)
    _resolve_boss_victory()
    _resolve_boss_victory_again()
    _expect(count == 1)
```

Guide Card 测试验证 Board 的 `card_return_requested` 经过 Flow/RunCardService 返回手牌，不绕过拥有权服务；事件 modal 测试验证结算失败后可以再次确认，不会出现隐藏视图但仍锁定交互的状态。

- [ ] **Step 2: 运行测试确认失败**

```powershell
& 'D:\InstallPath\godot\Godot_v4.7-stable_win64_console.exe' --headless --path . --script res://tests/game_manager_combat_routing_test.gd
& 'D:\InstallPath\godot\Godot_v4.7-stable_win64_console.exe' --headless --path . --script res://tests/guide_card_test.gd
```

预期：旧路由允许失败后继续调用放牌，或 Boss 结束信号重复发出。

- [ ] **Step 3: 实现终态防护和兼容转发**

Flow 的 `resolve_placement(result)` 只在 `EXPLORING` 状态执行；`FAILED` 和 `FINISHED` 直接忽略。Boss 终态通过 `_finished_event` 或已解决事件判重，保证 `run_finished` 单次发出。任何 modal unlock 请求先交给 Presentation Coordinator，由其依据 Flow 状态决定是否实际解锁。

GameManager 只把 Flow 信号转发到原有公开信号，继续为场景和测试提供兼容观察点。

- [ ] **Step 4: 运行回归测试**

```powershell
& 'D:\InstallPath\godot\Godot_v4.7-stable_win64_console.exe' --editor --headless --path . --quit
& 'D:\InstallPath\godot\Godot_v4.7-stable_win64_console.exe' --headless --path . --script res://tests/game_manager_combat_routing_test.gd
& 'D:\InstallPath\godot\Godot_v4.7-stable_win64_console.exe' --headless --path . --script res://tests/event_modal_coordinator_test.gd
& 'D:\InstallPath\godot\Godot_v4.7-stable_win64_console.exe' --headless --path . --script res://tests/guide_card_test.gd
```

预期：终态、RETREAT、Guide Card、失败恢复和 Boss 结束行为都通过。

- [ ] **Step 5: 提交**

```powershell
git add -- scripts/game/run/run_flow_coordinator.gd scripts/game/run/run_presentation_coordinator.gd scripts/game_manager.gd tests/game_manager_combat_routing_test.gd tests/event_modal_coordinator_test.gd tests/guide_card_test.gd
git commit -m "test(run): lock terminal lifecycle and preserve compatibility"
```

---

### Task 8: 全量验证、格式化和最终架构检查

**Files:**
- Modify only files already listed above if verification exposes a concrete defect.
- Do not modify `addons/godot-git-plugin/windows/~libgit_plugin.windows.editor.x86_64.dll`.

- [ ] **Step 1: 执行 Godot 编辑器扫描**

```powershell
& 'D:\InstallPath\godot\Godot_v4.7-stable_win64_console.exe' --editor --headless --path . --quit
```

预期：退出码为 0，输出中没有 `Parse Error`、`Identifier not declared` 或新产生的脚本加载错误。

- [ ] **Step 2: 执行新增和核心回归测试**

```powershell
$tests = @(
  'run_context_test.gd',
  'placement_pipeline_coordinator_test.gd',
  'run_flow_coordinator_test.gd',
  'run_presentation_coordinator_test.gd',
  'run_setup_coordinator_test.gd',
  'card_chain_coordinator_test.gd',
  'event_modal_coordinator_test.gd',
  'encounter_resolution_coordinator_test.gd',
  'game_manager_run_setup_test.gd',
  'game_manager_architecture_test.gd',
  'game_manager_combat_routing_test.gd',
  'guide_card_test.gd'
)
foreach ($test in $tests) {
  & 'D:\InstallPath\godot\Godot_v4.7-stable_win64_console.exe' --headless --path . --script ("res://tests/" + $test)
  if ($LASTEXITCODE -ne 0) { throw "Failed: $test" }
}
```

- [ ] **Step 3: 执行完整测试扫描**

```powershell
Get-ChildItem tests -Filter '*.gd' | Sort-Object Name | ForEach-Object {
  & 'D:\InstallPath\godot\Godot_v4.7-stable_win64_console.exe' --headless --path . --script ("res://tests/" + $_.Name)
  if ($LASTEXITCODE -ne 0) { throw "Failed: $($_.Name)" }
}
```

预期：所有现有测试和新增测试通过；若某个旧测试依赖旧内部字段，只更新其架构断言，不改变产品行为。

- [ ] **Step 4: 检查格式和架构边界**

```powershell
$format_files = @(
  'scripts/game_manager.gd',
  'scripts/game/run/run_context.gd',
  'scripts/game/run/run_random_service.gd',
  'scripts/game/run/run_setup_coordinator.gd',
  'scripts/game/run/run_flow_coordinator.gd',
  'scripts/game/run/run_presentation_coordinator.gd',
  'scripts/game/placement/placement_pipeline_coordinator.gd',
  'scripts/card/card_chain_coordinator.gd',
  'scripts/game/event/event_modal_coordinator.gd',
  'scripts/game/event/encounter/encounter_resolution_coordinator.gd'
)
gdformat --check $format_files
```

并用源码搜索确认：

```powershell
Select-String -Path scripts/game_manager.gd -Pattern '_on_board_placement_committed|\.apply\(|resolve_placement\(|set_vitality|set_gold|set_faith'
```

预期：GameManager 只保留组合、配置、兼容转发和 `_center_layout()`；不存在缺失回调引用；牌链执行点只在 CardChainCoordinator/PlacementPipeline 组合路径。

- [ ] **Step 5: 提交最终验证修正**

```powershell
git add -- scripts tests
git commit -m "refactor(game-manager): complete architecture verification"
```

---

## 迁移期间的提交顺序

1. `refactor(run): centralize runtime context and random streams`
2. `refactor(placement): centralize card and exploration ordering`
3. `refactor(run): centralize interaction and settlement lifecycle`
4. `refactor(encounter): replace exploration dependency with ports`
5. `refactor(presentation): isolate run HUD and input synchronization`
6. `refactor(game-manager): reduce root to scene composition`
7. `test(run): lock terminal lifecycle and preserve compatibility`
8. `refactor(game-manager): complete architecture verification`

每个提交都必须在独立工作树 `D:\project\MonoCard\mono-card\.worktrees\codex-game-manager-architecture` 中完成，不得触碰主工作树未提交的 DLL 删除改动。

## 自审结果

- **规格覆盖：** RunContext、随机流、显式放牌顺序、统一运行状态、modal 成功后关闭、Boss 回调端口、表现层隔离、GameManager 瘦身、兼容信号、失败/通关终态、Faith/RETREAT/Guide Card 兼容和全量验证均有对应任务。
- **占位符检查：** 未使用 `TBD`、`TODO` 或“自行决定”等未定义步骤；每个实现任务给出了文件、接口、测试和命令。
- **类型一致性：** 后续任务统一使用 `RunContext`、`RunRandomService`、`PlacementPipelineCoordinator`、`RunFlowCoordinator`、`RunPresentationCoordinator` 及其前述方法名；`EncounterResolutionCoordinator.configure()` 的 Callable 端口也在任务 4 明确定义。
- **已知基线问题：** 计划第一阶段必须先消除 `game_manager.gd:293-294` 对已删除 `_on_board_placement_committed` 的连接，否则 Godot 扫描和全部运行时测试无法启动。

