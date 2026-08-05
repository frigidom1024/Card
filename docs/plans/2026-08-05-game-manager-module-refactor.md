# GameManager 按功能模块拆分实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将 `GameManager` 收缩为运行局场景组合根；按业务功能把初始化、市场、事件弹窗与遭遇结算迁移为独立模块，同时保持现有事件触发、GUIDE、信仰、Boss 追击与卡牌生命周期行为不变。

**Architecture:** `GameManager` 仅持有场景节点、静态关卡资源和各模块实例，负责构造依赖、连接模块间信号、对外转发既有信号。每个协调器按完整玩家流程划分：`RunSetupCoordinator` 创建本局运行时玩家与卡牌数据，`PersistentMarketCoordinator` 处理常驻市场，`EventModalCoordinator` 管理普通事件的弹窗与奖励输入，`EncounterResolutionCoordinator` 落地战斗结果。所有模块只依赖自身需要的资源与节点，不反向依赖 `GameManager`。

**Tech Stack:** Godot 4.7 / GDScript / SceneTree 测试 / Git worktree。

## Global Constraints

- 本轮只重构职责归属；不改变卡牌、探索、战斗、市场价格、事件奖励或 UI 文案的游戏规则。
- Boss 仍是普通 `EventInstance`：只能通过玩家放置卡牌接触事件格触发；追击服务只移动其事件格。
- GUIDE 可揭雾、可触发事件、自动回手；不推进 Boss、不扣信仰，且满手时不能因回手丢失。
- 信仰只在玩家确认成功拆链后扣除；`FaithService` 不依赖棋盘、探索或 `EventLib`。
- `cards_inst` 与 `card_entities` 继续作为 `RunCardService` 数组的兼容引用，直到 GUIDE 分支合并后另行清理。
- 继续使用现有 `GameManager` 对外信号：`combat_started`、`combat_resolved`、`exploration_failed`、`run_initialization_failed`、`run_finished`、`faith_changed`。
- 新增 GDScript 及测试的 `.gd.uid` 必须随提交纳入版本控制。
- 不修改主工作树；所有开发在 `codex/game-manager-module-refactor` 工作树完成。
- 文档仅写入 `docs/plans/`，不创建或修改 `superpower` / `superpowers` 目录内容。

---

## 目标文件结构与职责

```text
scripts/game/
├─ run/
│  ├─ run_card_service.gd                    # 已有：本局卡牌实例与实体生命周期
│  └─ run_setup_coordinator.gd                # 新增：本局玩家、信仰、初始卡牌、战斗入口初始化
├─ market/
│  ├─ persistent_market_resolver.gd           # 已有：纯交易规则
│  └─ persistent_market_coordinator.gd        # 新增：常驻市场 UI 与交易流程
└─ event/
   ├─ event_interaction_controller.gd         # 已有：事件激活与结算生命周期
   ├─ event_modal_coordinator.gd              # 新增：商店/宝藏/战斗弹窗及奖励领取
   └─ encounter/
      ├─ encounter_combat_flow_coordinator.gd # 已有：战斗计算流程
      └─ encounter_resolution_coordinator.gd  # 新增：胜利、RETREAT、失败结果落地

scripts/game_manager.gd                       # 修改：仅场景组合、服务接线和对外信号转发
tests/run_setup_coordinator_test.gd            # 新增
tests/persistent_market_coordinator_test.gd    # 新增
tests/event_modal_coordinator_test.gd          # 新增
tests/encounter_resolution_coordinator_test.gd # 新增
tests/game_manager_architecture_test.gd        # 修改：约束组合根边界
```

### 模块边界

| 模块 | 拥有的业务流程 | 不应依赖 |
|---|---|---|
| `RunSetupCoordinator` | 复制 `PlayerData`、设置初始信仰、创建 `CombatStats`、配置 `RunCardService`、发放初始牌、创建事件交互控制器 | `BoardEvent`、探索配置、市场 UI、事件弹窗 |
| `PersistentMarketCoordinator` | 常驻市场初始化、购买、回收、刷新、市场提示、市场徽记同步请求 | `EventInteractionController`、宝藏/商店事件视图、Boss/探索服务 |
| `EventModalCoordinator` | 事件开始/结束锁定、打开商店/宝藏/战斗弹窗、商店购买、宝藏领奖、确认战斗结算 | 常驻市场状态、棋盘放牌、信仰服务、Boss 压力服务 |
| `EncounterResolutionCoordinator` | 战斗状态写回、普通事件刷新、Boss 移除、RETREAT 尾牌回手和强化、失败标记 | 事件视图、市场、`FaithService` |
| `GameManager` | 场景装配、服务构造、依赖注入、模块信号转发、探索协调器接线、布局 | 交易规则、奖励规则、残响状态细节、手牌实体创建细节 |

## 迁移顺序

先迁移没有 UI 输入的运行局初始化与遭遇结果，随后迁移市场和事件弹窗。每个模块迁移后，`GameManager` 都保持可运行并通过完整测试；不进行跨模块的行为改写。

---

### Task 1: 建立运行局初始化模块

**Files:**
- Create: `scripts/game/run/run_setup_coordinator.gd`
- Create: `tests/run_setup_coordinator_test.gd`
- Modify: `scripts/game_manager.gd:36-185`
- Modify: `tests/game_manager_architecture_test.gd`

**Interfaces:**
- Produces `class_name RunSetupCoordinator`.
- Produces `configure(source_player: PlayerData, deck: StartingDeckData, card_manager: Node2D, hand_area: HandArea, drag_layer: Node2D) -> bool`.
- Produces `initialize() -> bool`.
- Produces `get_player_data() -> PlayerData`, `get_player_stats() -> CombatStats`, `get_card_service() -> RunCardService`, `get_event_controller() -> EventInteractionController`.
- Emits `initialization_failed(reason: String)` rather than calling `GameManager` directly.
- `GameManager` forwards `initialization_failed` through its existing `run_initialization_failed` signal.

- [ ] **Step 1: Write the failing coordinator tests.**

```gdscript
func _test_initialize_creates_isolated_runtime_player_and_resets_faith() -> void:
    var coordinator := RunSetupCoordinator.new()
    _expect(coordinator.configure(_player_with_faith(0), _valid_deck(), _card_manager(), _hand_area(), _drag_layer()), "setup accepts valid dependencies")
    _expect(coordinator.initialize(), "setup initializes a playable runtime state")
    _expect(coordinator.get_player_data() != _source_player, "setup duplicates static player data")
    _expect(coordinator.get_player_data().faith == PlayerData.INITIAL_FAITH, "setup resets run faith")
    _expect(coordinator.get_player_stats() != null, "setup creates runtime combat stats")

func _test_initialize_exposes_card_service_arrays_for_game_manager_compatibility() -> void:
    var coordinator := _initialized_coordinator()
    _expect(coordinator.get_card_service().get_instances().size() == _valid_deck().starting_cards.size(), "setup creates starter instances")
    _expect(coordinator.get_card_service().get_entities().size() == coordinator.get_card_service().get_instances().size(), "setup tracks matching card entities")
```

- [ ] **Step 2: Run the new test to verify RED.**

Run:

```powershell
& 'D:\InstallPath\godot\Godot_v4.7-stable_win64_console.exe' --headless --path . --user-data-dir $env:TEMP\monocard-run-setup-red --script res://tests/run_setup_coordinator_test.gd
```

Expected: test fails because `res://scripts/game/run/run_setup_coordinator.gd` does not exist.

- [ ] **Step 3: Implement the smallest setup coordinator.**

Implement all current `_initialize_run_state()`, `init_player_cards()` and `_create_combat_service_for_root()` behavior inside `RunSetupCoordinator`. It must duplicate `PlayerData` before mutation, set its initial faith value, configure `RunCardService`, initialize the deck, and configure `EventInteractionController` with `EncounterCombatFlowCoordinator`. `GameManager` continues to configure its own `FaithService` after receiving the runtime player.

```gdscript
func initialize() -> bool:
    _runtime_player = _source_player.duplicate(true) as PlayerData
    if _runtime_player == null or _runtime_player.base_stats == null:
        initialization_failed.emit("Run setup could not duplicate PlayerData")
        return false
    _runtime_player.faith = PlayerData.INITIAL_FAITH
    _player_stats = CombatStats.from_data(_runtime_player.base_stats)
    # Configure RunCardService, initialize the deck, then configure encounter flow/controller.
    return true
```

- [ ] **Step 4: Make `GameManager` consume the coordinator without changing its public contract.**

Replace direct runtime state creation with one coordinator call. Assign:

```gdscript
player_data = _run_setup.get_player_data()
player_stats = _run_setup.get_player_stats()
_run_card_service = _run_setup.get_card_service()
_event_interaction_controller = _run_setup.get_event_controller()
cards_inst = _run_card_service.get_instances()
card_entities = _run_card_service.get_entities()
```

Keep `configure_run()` validation and `run_initialization_failed` signal in `GameManager`.

- [ ] **Step 5: Run focused tests and verify GREEN.**

Run:

```powershell
& 'D:\InstallPath\godot\Godot_v4.7-stable_win64_console.exe' --headless --path . --user-data-dir $env:TEMP\monocard-run-setup-green --script res://tests/run_setup_coordinator_test.gd
& 'D:\InstallPath\godot\Godot_v4.7-stable_win64_console.exe' --headless --path . --user-data-dir $env:TEMP\monocard-game-manager-setup --script res://tests/game_manager_run_setup_test.gd
```

Expected: both exit `0`.

- [ ] **Step 6: Commit Task 1.**

```powershell
git add scripts/game/run/run_setup_coordinator.gd scripts/game/run/run_setup_coordinator.gd.uid tests/run_setup_coordinator_test.gd tests/run_setup_coordinator_test.gd.uid scripts/game_manager.gd tests/game_manager_architecture_test.gd
git commit -m "refactor(game): extract run setup coordinator"
```

---

### Task 2: 建立遭遇结算模块

**Files:**
- Create: `scripts/game/event/encounter/encounter_resolution_coordinator.gd`
- Create: `tests/encounter_resolution_coordinator_test.gd`
- Modify: `scripts/game_manager.gd:365-603`
- Modify: `tests/game_manager_combat_routing_test.gd`
- Modify: `tests/game_manager_architecture_test.gd`

**Interfaces:**
- Produces `class_name EncounterResolutionCoordinator`.
- Produces `configure(board: Board, player_stats: CombatStats, card_service: RunCardService, exploration: ExplorationCoordinator, on_player_state_changed: Callable) -> bool`.
- Produces `apply(instance: EventInstance, result: CombatResult) -> bool`.
- Emits `exploration_failed(result: CombatResult)` on defeat.
- `apply()` owns all mutation currently in `_apply_combat_result`, `_apply_player_combat_state`, `_apply_monster_combat_state`, `_clear_monster_transient_state`, `_strengthen_encounter_monster`, `_return_tail_card_to_hand`, and `_refresh_event_display`.
- Player HUD refresh remains outside the module via the injected `on_player_state_changed` callback; the coordinator does not know HUD node types.

- [ ] **Step 1: Write failing result-application tests.**

```gdscript
func _test_victory_resolves_normal_event_and_preserves_monster_hp_snapshot() -> void:
    var fixture := _combat_fixture(EventData.EventType.MONSTER)
    _expect(fixture.coordinator.apply(fixture.instance, _victory_result(8, 0)), "victory applies")
    _expect(fixture.instance.is_resolved, "victory resolves an ordinary encounter")
    _expect(fixture.monster.stats.hp == 0, "victory writes monster hp")
    _expect(fixture.player_stats.defense == 0, "victory clears transient player defense")

func _test_retreat_returns_tail_temporarily_and_strengthens_same_monster() -> void:
    var fixture := _combat_fixture(EventData.EventType.MONSTER)
    var tail := _place_tail_card(fixture.board, fixture.card_service)
    _expect(fixture.coordinator.apply(fixture.instance, _retreat_result(7, 16, 1)), "retreat applies")
    _expect(tail in fixture.hand_area.cards, "retreat returns the last non-root card")
    _expect(fixture.monster.enhancement_stacks == 1, "retreat strengthens the surviving encounter")
    _expect(fixture.monster.action_index == 1, "retreat preserves the next monster action")

func _test_boss_victory_delegates_removal_to_exploration_coordinator() -> void:
    var fixture := _combat_fixture(EventData.EventType.BOSS)
    _expect(fixture.coordinator.apply(fixture.instance, _victory_result(10, 0)), "boss victory applies")
    _expect(fixture.exploration.dismissed_instance == fixture.instance, "boss removal uses exploration facade")
```

- [ ] **Step 2: Run the new test to verify RED.**

Run:

```powershell
& 'D:\InstallPath\godot\Godot_v4.7-stable_win64_console.exe' --headless --path . --user-data-dir $env:TEMP\monocard-encounter-resolution-red --script res://tests/encounter_resolution_coordinator_test.gd
```

Expected: fails because the coordinator class is missing.

- [ ] **Step 3: Implement the smallest encounter-resolution coordinator.**

Do not change `CombatResult` or combat calculation. Use the existing `EncounterRuntimeState` and `MobInstance` objects. On `RETREAT`, remove only `board.cards.back()` when more than the root exists, then call `RunCardService.return_existing_to_hand_temporarily(tail)` so full hand capacity never deletes the returned card.

- [ ] **Step 4: Route combat settlement through the module.**

`GameManager._on_combat_settlement_confirmed()` becomes orchestration only:

```gdscript
combat_event_view.hide_combat()
_encounter_resolution.apply(instance, result)
_event_interaction_controller.confirm_combat_settlement()
combat_resolved.emit(instance, result)
```

Forward `EncounterResolutionCoordinator.exploration_failed` through the existing `GameManager.exploration_failed` signal and mirror its failure flag only if needed to suppress future interaction.

- [ ] **Step 5: Run focused tests and verify GREEN.**

Run:

```powershell
& 'D:\InstallPath\godot\Godot_v4.7-stable_win64_console.exe' --headless --path . --user-data-dir $env:TEMP\monocard-encounter-resolution-green --script res://tests/encounter_resolution_coordinator_test.gd
& 'D:\InstallPath\godot\Godot_v4.7-stable_win64_console.exe' --headless --path . --user-data-dir $env:TEMP\monocard-combat-routing --script res://tests/game_manager_combat_routing_test.gd
```

Expected: both exit `0`, including existing victory, retreat, defeat and boss interaction cases.

- [ ] **Step 6: Commit Task 2.**

```powershell
git add scripts/game/event/encounter/encounter_resolution_coordinator.gd scripts/game/event/encounter/encounter_resolution_coordinator.gd.uid tests/encounter_resolution_coordinator_test.gd tests/encounter_resolution_coordinator_test.gd.uid scripts/game_manager.gd tests/game_manager_combat_routing_test.gd tests/game_manager_architecture_test.gd
git commit -m "refactor(events): extract encounter resolution coordinator"
```

---

### Task 3: 建立常驻市场模块

**Files:**
- Create: `scripts/game/market/persistent_market_coordinator.gd`
- Create: `tests/persistent_market_coordinator_test.gd`
- Modify: `scripts/game_manager.gd:41-45, 87-96, 194-267`
- Modify: `tests/game_manager_persistent_market_test.gd`
- Modify: `tests/game_manager_architecture_test.gd`

**Interfaces:**
- Produces `class_name PersistentMarketCoordinator`.
- Produces `configure(market: PersistentMarket, card_library: CardLib, player: PlayerData, hand_area: HandArea, card_service: RunCardService, pricing: MarketPricingService, rng: RandomNumberGenerator) -> bool`.
- Produces `connect_drag_layer(drag_layer: DragLayer, hand_tray: HandTray) -> void`.
- Owns `PersistentMarketState`, `PersistentMarketResolver`, and `MarketPriceContext` creation.
- Emits `player_state_changed`, `market_message_changed(text: String, is_error: bool)`, and `market_ready_changed(is_ready: bool)`.
- The coordinator never owns or frees drag cards; it only asks `RunCardService.forget_card(card)` after a successful reclaim transaction.

- [ ] **Step 1: Write failing market-flow tests.**

```gdscript
func _test_purchase_restores_drag_offer_then_grants_runtime_card() -> void:
    var fixture := _market_fixture()
    var offer := fixture.market.get_offer_card(0)
    fixture.coordinator.handle_purchase_requested(offer, 0)
    _expect(fixture.card_service.get_entities().size() == fixture.initial_entity_count + 1, "purchase grants a tracked card")
    _expect(fixture.market.last_message == "CARD PURCHASED", "purchase reports success")

func _test_reclaim_forgets_runtime_tracking_only_after_transaction_succeeds() -> void:
    var fixture := _market_fixture()
    var owned_card := _grant_owned_card(fixture)
    fixture.coordinator.handle_reclaim_requested(owned_card)
    _expect(owned_card not in fixture.card_service.get_entities(), "successful reclaim removes runtime tracking")
    _expect(is_instance_valid(owned_card), "coordinator leaves DragLayer ownership of freeing the visual card")
```

- [ ] **Step 2: Run the new test to verify RED.**

Run:

```powershell
& 'D:\InstallPath\godot\Godot_v4.7-stable_win64_console.exe' --headless --path . --user-data-dir $env:TEMP\monocard-market-coordinator-red --script res://tests/persistent_market_coordinator_test.gd
```

Expected: fails because the coordinator class is missing.

- [ ] **Step 3: Implement the smallest market coordinator.**

Migrate `_setup_persistent_market`, `_market_context`, `_on_market_purchase_requested`, `_on_market_reclaim_requested`, `_on_market_refresh_requested`, and `_market_failure_message` without changing resolver calls, price context or text.

- [ ] **Step 4: Replace GameManager market handlers with signal forwarding.**

`GameManager` constructs the module after runtime setup and connects `DragLayer.market_purchase_requested`, `DragLayer.market_reclaim_requested` and `PersistentMarket.refresh_requested` to the coordinator. It forwards `player_state_changed` to `_sync_pilgrim_crest()`.

- [ ] **Step 5: Run focused tests and verify GREEN.**

Run:

```powershell
& 'D:\InstallPath\godot\Godot_v4.7-stable_win64_console.exe' --headless --path . --user-data-dir $env:TEMP\monocard-market-coordinator-green --script res://tests/persistent_market_coordinator_test.gd
& 'D:\InstallPath\godot\Godot_v4.7-stable_win64_console.exe' --headless --path . --user-data-dir $env:TEMP\monocard-game-manager-market --script res://tests/game_manager_persistent_market_test.gd
& 'D:\InstallPath\godot\Godot_v4.7-stable_win64_console.exe' --headless --path . --user-data-dir $env:TEMP\monocard-market-drag --script res://tests/persistent_market_drag_test.gd
```

Expected: all exit `0`.

- [ ] **Step 6: Commit Task 3.**

```powershell
git add scripts/game/market/persistent_market_coordinator.gd scripts/game/market/persistent_market_coordinator.gd.uid tests/persistent_market_coordinator_test.gd tests/persistent_market_coordinator_test.gd.uid scripts/game_manager.gd tests/game_manager_persistent_market_test.gd tests/game_manager_architecture_test.gd
git commit -m "refactor(market): extract persistent market coordinator"
```

---

### Task 4: 建立事件弹窗与奖励模块

**Files:**
- Create: `scripts/game/event/event_modal_coordinator.gd`
- Create: `tests/event_modal_coordinator_test.gd`
- Modify: `scripts/game_manager.gd:27-30, 99-118, 338-480`
- Modify: `tests/event_trigger_test.gd`
- Modify: `tests/game_manager_combat_routing_test.gd`
- Modify: `tests/game_manager_architecture_test.gd`

**Interfaces:**
- Produces `class_name EventModalCoordinator`.
- Produces `configure(controller: EventInteractionController, drag_layer: DragLayer, hand_area: HandArea, card_service: RunCardService, player: PlayerData, shop_view: ShopEventView, treasure_view: TreasureEventView, combat_view: CombatEventView, pricing: MarketPricingService) -> bool`.
- Produces `begin(instance: EventInstance, player_stats: CombatStats, chain: Array[CardInstance]) -> void`.
- Produces `confirm_combat_settlement() -> void` after hiding the combat modal and requesting the currently pending tuple.
- Emits `combat_started(instance: EventInstance, monster: MobInstance)`, `combat_settlement_confirmed(instance: EventInstance, result: CombatResult)`, `interaction_lock_changed(locked: bool)`, and `unsupported_event(instance: EventInstance)`.
- Owns `ShopEventResolver`, `TreasureEventResolver`, both RNGs, modal display calls and validation/error copy.
- Does **not** apply combat result; that stays in `EncounterResolutionCoordinator`.

- [ ] **Step 1: Write failing event-modal tests.**

```gdscript
func _test_shop_purchase_uses_active_event_and_grants_card_to_run_service() -> void:
    var fixture := _modal_fixture()
    fixture.coordinator.begin(fixture.shop_instance, fixture.player_stats, [])
    fixture.shop_view.purchase_requested.emit(0)
    _expect(fixture.card_service.get_entities().size() == fixture.initial_cards + 1, "shop reward enters runtime hand")
    _expect(fixture.shop_view.last_message == "购买成功。", "shop reports completed purchase")

func _test_treasure_card_reward_respects_hand_capacity_without_resolving_event() -> void:
    var fixture := _full_hand_treasure_fixture()
    fixture.coordinator.begin(fixture.instance, fixture.player_stats, [])
    fixture.treasure_view.reward_requested.emit(0)
    _expect(not fixture.instance.is_resolved, "full hand does not consume treasure")
    _expect(fixture.treasure_view.last_message == "手牌已满，无法领取这张卡牌。", "treasure explains capacity failure")

func _test_combat_confirmation_emits_pending_result_without_mutating_encounter() -> void:
    var fixture := _combat_modal_fixture()
    fixture.coordinator.begin(fixture.instance, fixture.player_stats, fixture.chain)
    fixture.combat_view.settlement_confirmed.emit()
    _expect(fixture.emitted_instance == fixture.instance, "modal exposes pending encounter")
    _expect(fixture.monster.stats.hp == fixture.hp_before, "modal does not apply combat mutation")
```

- [ ] **Step 2: Run the new test to verify RED.**

Run:

```powershell
& 'D:\InstallPath\godot\Godot_v4.7-stable_win64_console.exe' --headless --path . --user-data-dir $env:TEMP\monocard-event-modal-red --script res://tests/event_modal_coordinator_test.gd
```

Expected: fails because `EventModalCoordinator` is missing.

- [ ] **Step 3: Implement the smallest event-modal coordinator.**

Migrate `_on_board_event_triggered`, interaction start/finish behavior, `_open_shop_event`, `_open_treasure_event`, shop purchase/close, treasure claim/close, `_grant_card_to_hand`, `_resolution_failure_message`, combat-result view display, and settlement-confirmation tuple retrieval. Preserve existing Chinese UI messages exactly.

- [ ] **Step 4: Wire modal confirmation to encounter resolution.**

`GameManager` listens to `combat_settlement_confirmed`, calls `_encounter_resolution.apply(instance, result)`, then invokes `EventInteractionController.confirm_combat_settlement()` through the modal coordinator (or an explicit coordinator method), and finally emits the unchanged `combat_resolved` signal.

- [ ] **Step 5: Run focused tests and verify GREEN.**

Run:

```powershell
& 'D:\InstallPath\godot\Godot_v4.7-stable_win64_console.exe' --headless --path . --user-data-dir $env:TEMP\monocard-event-modal-green --script res://tests/event_modal_coordinator_test.gd
& 'D:\InstallPath\godot\Godot_v4.7-stable_win64_console.exe' --headless --path . --user-data-dir $env:TEMP\monocard-event-trigger --script res://tests/event_trigger_test.gd
& 'D:\InstallPath\godot\Godot_v4.7-stable_win64_console.exe' --headless --path . --user-data-dir $env:TEMP\monocard-combat-routing-modal --script res://tests/game_manager_combat_routing_test.gd
```

Expected: all exit `0`; Boss interactions remain board-contact driven rather than click driven.

- [ ] **Step 6: Commit Task 4.**

```powershell
git add scripts/game/event/event_modal_coordinator.gd scripts/game/event/event_modal_coordinator.gd.uid tests/event_modal_coordinator_test.gd tests/event_modal_coordinator_test.gd.uid scripts/game_manager.gd tests/event_trigger_test.gd tests/game_manager_combat_routing_test.gd tests/game_manager_architecture_test.gd
git commit -m "refactor(events): extract event modal coordinator"
```

---

### Task 5: 收紧组合根与回归验证

**Files:**
- Modify: `scripts/game_manager.gd`
- Modify: `tests/game_manager_architecture_test.gd`
- Modify: any new `.gd.uid` created in Tasks 1–4

**Interfaces:**
- `GameManager` still exposes the same scene-level signals and compatibility card arrays.
- `GameManager` may create module facades, `ExplorationCoordinator`, `FaithService` and layout wiring, but must not construct `ShopEventResolver`, `TreasureEventResolver`, `PersistentMarketResolver`, `EncounterCombatFlowCoordinator`, or mutate `MobInstance` combat state directly.

- [ ] **Step 1: Add structural regression assertions.**

```gdscript
_expect(source.contains("var _run_setup: RunSetupCoordinator"), "GameManager composes the run setup module")
_expect(source.contains("var _persistent_market_coordinator: PersistentMarketCoordinator"), "GameManager composes the market module")
_expect(source.contains("var _event_modal_coordinator: EventModalCoordinator"), "GameManager composes the event modal module")
_expect(source.contains("var _encounter_resolution: EncounterResolutionCoordinator"), "GameManager composes the encounter-resolution module")
_expect(not source.contains("ShopEventResolver.new("), "GameManager does not construct shop resolver")
_expect(not source.contains("TreasureEventResolver.new("), "GameManager does not construct treasure resolver")
_expect(not source.contains("PersistentMarketResolver.new("), "GameManager does not construct market resolver")
_expect(not source.contains("monster.gain_enhancement()"), "GameManager does not mutate encounter enhancement")
```

- [ ] **Step 2: Run the architecture test to verify RED before the final cleanup.**

Run:

```powershell
& 'D:\InstallPath\godot\Godot_v4.7-stable_win64_console.exe' --headless --path . --user-data-dir $env:TEMP\monocard-game-manager-architecture-red --script res://tests/game_manager_architecture_test.gd
```

Expected: fails until `GameManager` delegates all listed responsibilities.

- [ ] **Step 3: Remove dead handlers and narrow GameManager.**

Delete only logic superseded by coordinator calls. Keep scene-specific layout (`_center_layout`), exploration configuration/placement forwarding, FaithService signal attachment, GUIDE board-return handling, and top-level external signal forwarding. Do not remove compatibility arrays.

- [ ] **Step 4: Run focused architecture tests.**

Run:

```powershell
& 'D:\InstallPath\godot\Godot_v4.7-stable_win64_console.exe' --headless --path . --user-data-dir $env:TEMP\monocard-game-manager-architecture-green --script res://tests/game_manager_architecture_test.gd
& 'D:\InstallPath\godot\Godot_v4.7-stable_win64_console.exe' --headless --path . --user-data-dir $env:TEMP\monocard-guide-card --script res://tests/guide_card_test.gd
& 'D:\InstallPath\godot\Godot_v4.7-stable_win64_console.exe' --headless --path . --user-data-dir $env:TEMP\monocard-faith --script res://tests/game_manager_faith_test.gd
```

Expected: all exit `0`.

- [ ] **Step 5: Run complete regression and repository checks.**

Run every `tests/*_test.gd` script in its own `--user-data-dir`; use direct process output rather than redirecting all Godot output. Then run:

```powershell
git diff --check
git status --short --branch
```

Expected: all tests exit `0`, no whitespace errors, and only the intended source/test/UID files are changed.

- [ ] **Step 6: Commit Task 5.**

```powershell
git add scripts/game_manager.gd tests/game_manager_architecture_test.gd
git commit -m "refactor(game): narrow manager to composition root"
```

## Acceptance Criteria

- `scripts/game_manager.gd` is a composition root of approximately 220–280 lines, excluding comments and blank lines.
- Market, event modal, encounter settlement and run initialization behavior each have a dedicated coordinator under their business module directory.
- A coordinator never fetches `GameManager` through a scene path or singleton and never calls its methods directly.
- Boss encounter triggering still uses the existing `ExplorationCoordinator -> event_interaction_requested -> EventInteractionController.begin()` flow; no click-to-challenge behavior is introduced.
- RETREAT retains monster HP/action state, enhances that same residual encounter and returns the final non-root card without losing it at full hand capacity.
- GUIDE behavior, confirmed-retraction faith behavior, player HUD updates and `cards_inst` / `card_entities` compatibility remain covered by tests.
- All Godot tests pass on the isolated branch, required `.uid` files are committed, and `git diff --check` reports no errors.
