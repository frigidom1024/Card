# 落牌后随机事件生成机制实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans (or superpowers:subagent-driven-development) to implement this plan task-by-task.

**Goal:** 移除迷雾驱动的探索事件生成，改为关卡初始化随机生成事件，并在 ROOT/普通牌成功放置后按关卡配置随机生成 0～2 个事件，同时保留普通事件接触、Boss 追击和现有信仰值流程。

**Architecture:** `EventLib` 继续只提供本关事件模板；新增 `EventSpawnCandidate` 与 `ExplorationSpawnConfig` 描述初始事件池、动态事件池、数量权重、上限和 Boss 出现阈值。`ExplorationEventService` 负责抽样和请求 `EventPlacementService` 在全棋盘合法空位随机放置，`ExplorationCoordinator` 只协调事务，`GameManager` 在探索配置完成后触发一次初始化事件生成。GUIDE 不触发动态生成，Boss 仍是普通 `EventInstance`。

**Tech Stack:** Godot 4.x、GDScript、Resource 配置、`RandomNumberGenerator`、SceneTree headless tests。

## Global Constraints

- 不修改主工作区 `D:/project/MonoCard/mono-card` 中已有的未提交改动。
- 所有实现只能发生在 `D:/project/MonoCard/mono-card/.worktrees/codex-placement-event-spawn`。
- 不使用迷雾格子作为事件生成条件。
- GUIDE 放置不生成动态事件，也不推进 Boss 出现进度或 Boss 追击计数。
- Boss 必须继续使用普通 `EventInstance` 和普通落牌接触流程。
- 所有新 `.gd` 文件必须生成并提交对应 `.gd.uid`。
- 新随机逻辑必须使用可注入的 `RandomNumberGenerator`，测试使用固定 seed。
- 不改变信仰值、RETREAT、回潮强化、战斗数值和事件 UI 的已有行为。

---

## 变更文件总览

### 新建

- `scripts/game/exploration/event_spawn_candidate.gd`：单个事件模板候选及其权重、去重策略。
- `scripts/game/exploration/exploration_spawn_config.gd`：每关的初始/动态生成策略与校验。
- `data/levels/ribwood/exploration_spawn_config.tres`：肋骨林地的生成配置。
- `tests/event_spawn_candidate_test.gd`：候选资源默认值和校验测试。
- `tests/exploration_spawn_config_test.gd`：生成配置校验与 Ribwood 资源测试。
- `tests/exploration_event_spawn_test.gd`：初始化、落牌后抽样、上限和 Boss 待生成测试。

### 修改

- `scripts/game/exploration/exploration_config.gd`：引用 `ExplorationSpawnConfig`，移除迷雾阈值字段，保留 Boss 追击字段。
- `data/levels/ribwood/exploration_config.tres`：引用 Ribwood 的生成配置，删除迷雾阈值配置。
- `scripts/game/exploration/exploration_event_service.gd`：从揭开格子调度改为初始化和落牌事务调度。
- `scripts/game/exploration/exploration_coordinator.gd`：移除 `FogService`，新增初始化事件和落牌后生成入口。
- `scripts/game_manager.gd`：探索配置完成后初始化初始事件；保留事件接触和普通 Boss 交互路径。
- `tests/exploration_coordinator_test.gd`：改写迷雾相关断言，增加 GUIDE、ROOT/普通牌和初始化入口断言。
- `tests/exploration_config_test.gd`：改为校验新的 Ribwood 生成配置。
- `tests/ribwood_event_lib_test.gd`：保留事件目录测试，并校验 Boss 不属于普通动态池的配置约束。
- `scripts/game/exploration/fog_service.gd` 及 UID：确认无引用后删除。
- `tests/fog_service_test.gd`：删除或迁移为新探索生成测试，不能保留迷雾行为作为验收要求。

---

## Task 1: 新增候选资源和探索生成配置

**Files:**
- Create: `scripts/game/exploration/event_spawn_candidate.gd`
- Create: `scripts/game/exploration/exploration_spawn_config.gd`
- Create: `tests/event_spawn_candidate_test.gd`
- Create: `tests/exploration_spawn_config_test.gd`
- Modify: `scripts/game/exploration/exploration_config.gd`
- Modify: `tests/exploration_config_test.gd`

**Interfaces:**
- `EventSpawnCandidate` 提供 `event_data: EventData`、`weight: int`、`allow_duplicate: bool`。
- `EventSpawnCandidate.validate(event_lib: EventLib) -> String` 检查候选模板、权重和模板是否属于当前关卡 EventLib。
- `ExplorationSpawnConfig.validate(event_lib: EventLib) -> String` 检查数量范围、数量权重、候选池和 Boss 模板约束。
- `ExplorationSpawnConfig.get_spawn_count(rng: RandomNumberGenerator) -> int` 返回配置权重抽中的 0、1 或 2。
- `ExplorationConfig` 新增 `spawn_config: ExplorationSpawnConfig`，`validate()` 委托生成配置校验并删除 `scheduled_event_reveal_thresholds` 与 `boss_reveal_threshold`。

- [ ] **Step 1: 写候选资源失败测试。**

在 `tests/event_spawn_candidate_test.gd` 覆盖：

```gdscript
func _test_default_candidate_is_invalid() -> void:
    var candidate := EventSpawnCandidate.new()
    _expect(candidate.validate(null) != "", "empty candidate fails validation")

func _test_positive_weight_and_template_are_valid() -> void:
    var lib := _make_event_lib_with_template("ribwood_rat", EventData.EventType.MONSTER)
    var candidate := EventSpawnCandidate.new()
    candidate.event_data = lib.entries[0].event_data
    candidate.weight = 10
    _expect(candidate.validate(lib).is_empty(), "candidate with an EventData in the current lib is valid")
```

- [ ] **Step 2: 运行测试确认失败。**

运行：

```powershell
& 'D:\InstallPath\godot\Godot_v4.7-stable_win64_console.exe' --headless --path . --user-data-dir $env:TEMP\monocard-spawn-candidate-red --script res://tests/event_spawn_candidate_test.gd
```

预期：因 `EventSpawnCandidate` 尚不存在而失败。

- [ ] **Step 3: 实现候选资源。**

使用 `class_name EventSpawnCandidate extends Resource`，实现 `validate()`：

```gdscript
func validate(event_lib: EventLib) -> String:
    if event_data == null:
        return "Event spawn candidate is missing event_data"
    if weight <= 0:
        return "Event spawn candidate weight must be positive"
    if event_lib == null or event_data not in event_lib.get_all_templates():
        return "Event spawn candidate must belong to the current EventLib"
    return ""
```

如果 `EventLib` 没有 `get_all_templates()`，同步新增该只读方法，返回去重后的 `EventData` 列表，不改变现有 `entries` 和 `generate_event_datas()` 的兼容行为。

- [ ] **Step 4: 写生成配置失败测试。**

覆盖以下配置错误：

```gdscript
func _test_initial_range_rejects_min_above_max() -> void:
    var config := ExplorationSpawnConfig.new()
    config.initial_event_count_min = 4
    config.initial_event_count_max = 2
    _expect(config.validate(_make_event_lib()) != "", "invalid initial range is rejected")

func _test_spawn_count_weights_require_only_zero_to_two_and_positive_total() -> void:
    var config := ExplorationSpawnConfig.new()
    config.placement_spawn_count_weights = {3: 1}
    _expect(config.validate(_make_event_lib()) != "", "unsupported spawn count is rejected")
    config.placement_spawn_count_weights = {0: 0, 1: 0, 2: 0}
    _expect(config.validate(_make_event_lib()) != "", "zero total spawn weight is rejected")

func _test_get_spawn_count_is_seeded() -> void:
    var config := _make_valid_spawn_config()
    var first_rng := RandomNumberGenerator.new()
    var second_rng := RandomNumberGenerator.new()
    first_rng.seed = 12345
    second_rng.seed = 12345
    _expect(config.get_spawn_count(first_rng) == config.get_spawn_count(second_rng), "spawn count is reproducible with the same seed")
```

- [ ] **Step 5: 实现 `ExplorationSpawnConfig`。**

实现：

```gdscript
@export_range(0, 20, 1) var initial_event_count_min := 3
@export_range(0, 20, 1) var initial_event_count_max := 5
@export var initial_event_pool: Array[EventSpawnCandidate] = []
@export var placement_spawn_count_weights: Dictionary = {0: 60, 1: 30, 2: 10}
@export var placement_event_pool: Array[EventSpawnCandidate] = []
@export_range(1, 30, 1) var max_unresolved_events := 8
@export_range(1, 99, 1) var boss_spawn_after_placements := 8
```

`get_spawn_count()` 使用固定 key 顺序 `[0, 1, 2]` 和权重累计抽样，避免 Dictionary 遍历顺序影响测试。

`validate()` 检查：

- min/max 非负且 min <= max；
- 数量权重 key 仅为 0、1、2；
- 数量权重非负且总权重大于 0；
- 两个候选池都不含 null，且候选验证通过；
- 动态池不允许包含 Boss；
- `max_unresolved_events` 与 Boss 阈值为正数；
- 初始池至少有一个候选（除非初始数量上限为 0）。

- [ ] **Step 6: 修改 `ExplorationConfig` 并更新配置测试。**

保留现有 Boss 追击字段，新增：

```gdscript
@export var spawn_config: ExplorationSpawnConfig
```

`validate()` 必须先验证 Boss 追击阈值，再验证 `spawn_config`；错误信息包含所属配置字段，便于定位资源错误。更新 `tests/exploration_config_test.gd`，删除迷雾字段断言，改为验证 Ribwood 的新生成资源与 Boss 追击开关。

- [ ] **Step 7: 生成 UID，运行本任务测试并提交。**

运行：

```powershell
& 'D:\InstallPath\godot\Godot_v4.7-stable_win64_console.exe' --headless --path . --editor --quit --user-data-dir $env:TEMP\monocard-spawn-uid
& 'D:\InstallPath\godot\Godot_v4.7-stable_win64_console.exe' --headless --path . --user-data-dir $env:TEMP\monocard-spawn-config --script res://tests/event_spawn_candidate_test.gd
& 'D:\InstallPath\godot\Godot_v4.7-stable_win64_console.exe' --headless --path . --user-data-dir $env:TEMP\monocard-spawn-config-2 --script res://tests/exploration_spawn_config_test.gd
& 'D:\InstallPath\godot\Godot_v4.7-stable_win64_console.exe' --headless --path . --user-data-dir $env:TEMP\monocard-exploration-config --script res://tests/exploration_config_test.gd
```

预期：新增测试全部通过，提交资源、脚本、UID 和测试：

```powershell
git add scripts/game/exploration/event_spawn_candidate.gd scripts/game/exploration/event_spawn_candidate.gd.uid scripts/game/exploration/exploration_spawn_config.gd scripts/game/exploration/exploration_spawn_config.gd.uid scripts/game/exploration/exploration_config.gd tests/event_spawn_candidate_test.gd tests/event_spawn_candidate_test.gd.uid tests/exploration_spawn_config_test.gd tests/exploration_spawn_config_test.gd.uid tests/exploration_config_test.gd
git commit -m "feat(exploration): add configurable event spawn profiles"
```

---

## Task 2: 重构探索事件服务为可测试的随机生成服务

**Files:**
- Modify: `scripts/game/exploration/exploration_event_service.gd`
- Create: `tests/exploration_event_spawn_test.gd`

**Interfaces:**
- `configure(event_lib: EventLib, board: Board, spawn_config: ExplorationSpawnConfig, rng: RandomNumberGenerator = null) -> bool`
- `spawn_initial_events() -> int`
- `try_spawn_after_placement(result: BoardPlacementResult) -> int`
- `request_faith_echo() -> bool`
- `is_boss_spawned() -> bool`
- `get_exploration_placement_count() -> int`
- `get_pending_boss() -> bool`

- [ ] **Step 1: 写初始化生成失败测试。**

构造一个 4×4 Board、包含两个 1×1 EventData 的 EventLib 和固定 `ExplorationSpawnConfig`，验证：

```gdscript
var service := ExplorationEventService.new()
_expect(service.configure(lib, board, spawn_config, _seeded_rng()), "service configures")
_expect(service.spawn_initial_events() == 2, "initial spawn uses configured count")
_expect(board.events.size() == 2, "initial events are attached to the board")
```

并验证每个事件：

```gdscript
_expect(board.can_attach_event(event_node.event_instance) == false, "attached event origin is occupied")
_expect(event_node.event_instance.origin.x >= 0, "event has a board origin")
```

- [ ] **Step 2: 写动态数量与池选择失败测试。**

为测试注入 `{0: 0, 1: 0, 2: 1}`，调用：

```gdscript
var result := _make_normal_placement_result()
_expect(service.try_spawn_after_placement(result) == 2, "placement can spawn two events")
_expect(board.events.size() == 2, "two dynamic events are attached")
```

使用 `{0: 1, 1: 0, 2: 0}` 验证实际生成 0 个。使用 GUIDE 结果验证实际生成 0 个且计数不增加。

- [ ] **Step 3: 写事件数量上限和合法空间失败测试。**

验证 `max_unresolved_events` 达到时不生成；将 Board 填满到没有合法事件原点时，验证服务返回实际成功数量，不抛异常，也不会把未附着实例留在 `board.events` 中。

- [ ] **Step 4: 写 Boss 阈值和待生成失败测试。**

配置 Boss 阈值为 2，连续提交 ROOT/普通牌结果，验证第二次后生成一个 Boss；提交 GUIDE 结果不推进计数。使用已被卡牌占满的 Board 验证 `get_pending_boss() == true`，释放空间后下一次普通牌放置可以生成 Boss。

- [ ] **Step 5: 实现候选抽样与事件放置。**

实现私有方法：

```gdscript
func _choose_candidate(pool: Array[EventSpawnCandidate], used_templates: Array[EventData] = []) -> EventSpawnCandidate
func _weighted_choice(weights: Dictionary) -> int
func _spawn_from_pool(count: int, pool: Array[EventSpawnCandidate]) -> int
func _count_unresolved_events() -> int
func _create_and_place(candidate: EventSpawnCandidate) -> bool
```

使用 `EventPlacementService.place_event_instance()`，不要复制合法原点计算。每次成功附着后通过 `event_spawned.emit(_find_event_node(instance))` 汇报；没有合法位置时返回 false 并恢复候选实例原点。

- [ ] **Step 6: 实现初始化与落牌后入口。**

`spawn_initial_events()`：

1. 从 RNG 抽取初始数量；
2. 使用初始候选池；
3. 遵守 `allow_duplicate`；
4. 返回实际附着数量。

`try_spawn_after_placement(result)`：

1. null 结果直接返回 0；
2. `result.source_card` 为 GUIDE 时返回 0；
3. ROOT/普通牌将探索放置计数加一；
4. 先按数量权重生成普通事件；
5. 再检查 Boss 阈值并尝试生成 Boss；
6. Boss 达阈值但无空间时设置 pending 标记；
7. 返回本次普通动态事件的实际生成数。

`request_faith_echo()` 继续只从普通 MONSTER 模板抽取并使用全棋盘随机放置，不经过动态事件数量上限，避免改变已有信仰值惩罚语义。

- [ ] **Step 7: 运行服务测试并提交。**

运行：

```powershell
& 'D:\InstallPath\godot\Godot_v4.7-stable_win64_console.exe' --headless --path . --user-data-dir $env:TEMP\monocard-event-spawn --script res://tests/exploration_event_spawn_test.gd
```

预期：初始化、动态数量、GUIDE 跳过、事件上限、Boss pending 测试通过。提交：

```powershell
git add scripts/game/exploration/exploration_event_service.gd tests/exploration_event_spawn_test.gd tests/exploration_event_spawn_test.gd.uid
git commit -m "feat(exploration): add seeded placement event spawning"
```

---

## Task 3: 移除迷雾依赖并接入探索协调器

**Files:**
- Modify: `scripts/game/exploration/exploration_coordinator.gd`
- Modify: `scripts/game_manager.gd`
- Modify: `tests/exploration_coordinator_test.gd`

**Interfaces:**
- `ExplorationCoordinator.initialize_events() -> int`
- `ExplorationCoordinator.resolve_placement(result: BoardPlacementResult) -> void`
- `ExplorationCoordinator.get_exploration_placement_count() -> int`
- 保留：`request_faith_echo()`, `dismiss_defeated_boss()`, `get_boss_phase()`, `get_boss_event()`。
- 删除：`fog_revealed`, `get_revealed_count()`, `FogService` 依赖。

- [ ] **Step 1: 更新协调器测试以描述新流程。**

删除揭开格子数量、`fog_revealed` 和 reveal threshold 断言，新增：

```gdscript
_expect(coordinator.initialize_events() == 2, "coordinator initializes configured events")
_expect(board.events.size() == 2, "initial events are visible immediately")
```

增加 ROOT/普通牌和 GUIDE 的 `resolve_placement()` 测试，断言动态事件生成数量与 Boss 探索计数符合配置。

- [ ] **Step 2: 运行测试确认迁移前失败。**

运行：

```powershell
& 'D:\InstallPath\godot\Godot_v4.7-stable_win64_console.exe' --headless --path . --user-data-dir $env:TEMP\monocard-coordinator-red --script res://tests/exploration_coordinator_test.gd
```

预期：旧协调器仍依赖 FogService 或缺少新初始化接口，测试失败。

- [ ] **Step 3: 修改 `ExplorationCoordinator.configure()`。**

保留 EventLib、Board、ExplorationConfig 校验和 Boss 追击配置，改为把 `config.spawn_config` 传给事件服务。连接 `event_spawned` 和 Boss 注册信号，删除 FogService 初始化及连接。

- [ ] **Step 4: 修改 `initialize_events()` 和 `resolve_placement()`。**

实现：

```gdscript
func initialize_events() -> int:
    if _event_service == null:
        return 0
    return _event_service.spawn_initial_events()

func resolve_placement(result: BoardPlacementResult) -> void:
    if result == null or _board == null:
        return
    var boss_before := _boss_pressure_service.get_registered_boss()
    _event_service.try_spawn_after_placement(result)
    if boss_before != null and result.overlapped_event != boss_before.event_instance:
        _boss_pressure_service.record_placement(_board, result)
    if result.overlapped_event != null and not result.overlapped_event.is_resolved:
        event_interaction_requested.emit(result.overlapped_event)
```

事件接触仍由协调器发出原有 `event_interaction_requested`，不改变普通事件和 Boss 的入口。

- [ ] **Step 5: 修改 GameManager 初始化顺序。**

在 `_configure_exploration()` 中：

1. 配置协调器；
2. 连接 `board.placement_committed`；
3. 连接 `event_interaction_requested`；
4. 调用 `_exploration_coordinator.initialize_events()`。

必须在连接 `event_spawned` 相关信号后再初始化，避免初始 Boss（虽然 Ribwood 不配置初始 Boss）或其它事件生成信号丢失。

- [ ] **Step 6: 运行协调器与 GameManager 相关测试并提交。**

运行：

```powershell
& 'D:\InstallPath\godot\Godot_v4.7-stable_win64_console.exe' --headless --path . --user-data-dir $env:TEMP\monocard-coordinator-green --script res://tests/exploration_coordinator_test.gd
& 'D:\InstallPath\godot\Godot_v4.7-stable_win64_console.exe' --headless --path . --user-data-dir $env:TEMP\monocard-manager-exploration --script res://tests/game_manager_architecture_test.gd
& 'D:\InstallPath\godot\Godot_v4.7-stable_win64_console.exe' --headless --path . --user-data-dir $env:TEMP\monocard-manager-routing --script res://tests/game_manager_combat_routing_test.gd
```

提交：

```powershell
git add scripts/game/exploration/exploration_coordinator.gd scripts/game_manager.gd tests/exploration_coordinator_test.gd
git commit -m "refactor(exploration): replace fog resolution with placement spawning"
```

---

## Task 4: 配置 Ribwood 的初始池和动态池

**Files:**
- Create: `data/levels/ribwood/exploration_spawn_config.tres`
- Modify: `data/levels/ribwood/exploration_config.tres`
- Modify: `tests/exploration_spawn_config_test.gd`
- Modify: `tests/ribwood_event_lib_test.gd`

**Interfaces:**
- Ribwood `ExplorationConfig.spawn_config` 引用新资源。
- 初始池引用 Ribwood 的宝藏、商店和普通残响 `EventData`。
- 动态池引用 Ribwood 的普通残响、宝藏和商店，不引用 Boss。

- [ ] **Step 1: 为 Ribwood 资源写失败断言。**

在配置测试中加载：

```gdscript
const RibwoodSpawnConfig := preload("res://data/levels/ribwood/exploration_spawn_config.tres")
const RibwoodExplorationConfig := preload("res://data/levels/ribwood/exploration_config.tres")
```

断言：

```gdscript
_expect(RibwoodSpawnConfig.initial_event_count_min == 3, "Ribwood starts with three or more visible events")
_expect(RibwoodSpawnConfig.initial_event_count_max == 5, "Ribwood initial event count is capped at five")
_expect(RibwoodSpawnConfig.placement_spawn_count_weights == {0: 60, 1: 30, 2: 10}, "Ribwood uses configured dynamic spawn weights")
_expect(RibwoodSpawnConfig.max_unresolved_events == 8, "Ribwood caps unresolved events")
_expect(RibwoodExplorationConfig.spawn_config == RibwoodSpawnConfig, "Ribwood exploration config references its spawn profile")
```

- [ ] **Step 2: 运行测试确认资源尚未存在时失败。**

运行：

```powershell
& 'D:\InstallPath\godot\Godot_v4.7-stable_win64_console.exe' --headless --path . --user-data-dir $env:TEMP\monocard-ribwood-spawn-red --script res://tests/exploration_spawn_config_test.gd
```

预期：资源路径或新字段缺失导致失败。

- [ ] **Step 3: 创建 Ribwood 生成资源。**

初始池建议：

| 事件 | 权重 | 重复 |
|---|---:|---:|
| 啮髓鼠群 | 45 | 是 |
| 熄灭的骨髓灯 | 25 | 否 |
| 断旗巡礼营 | 15 | 否 |
| 腐肋巨狼 | 15 | 是 |

动态池建议：

| 事件 | 权重 | 重复 |
|---|---:|---:|
| 啮髓鼠群 | 50 | 是 |
| 腐肋巨狼 | 25 | 是 |
| 熄灭的骨髓灯 | 15 | 否 |
| 断旗巡礼营 | 10 | 否 |

Boss 白角守墓鹿只由 Boss 阈值生成，不放入上述两个池。配置 `boss_spawn_after_placements = 8`，追击开关及阶段阈值沿用当前 Ribwood 数值。

- [ ] **Step 4: 生成 UID 并验证资源。**

运行：

```powershell
& 'D:\InstallPath\godot\Godot_v4.7-stable_win64_console.exe' --headless --path . --editor --quit --user-data-dir $env:TEMP\monocard-ribwood-spawn-uid
& 'D:\InstallPath\godot\Godot_v4.7-stable_win64_console.exe' --headless --path . --user-data-dir $env:TEMP\monocard-ribwood-spawn-green --script res://tests/exploration_spawn_config_test.gd
& 'D:\InstallPath\godot\Godot_v4.7-stable_win64_console.exe' --headless --path . --user-data-dir $env:TEMP\monocard-ribwood-lib-green --script res://tests/ribwood_event_lib_test.gd
```

提交：

```powershell
git add data/levels/ribwood/exploration_spawn_config.tres data/levels/ribwood/exploration_config.tres tests/exploration_spawn_config_test.gd tests/ribwood_event_lib_test.gd
git commit -m "data(ribwood): configure visible and placement event pools"
```

---

## Task 5: 删除迷雾代码和旧测试路径

**Files:**
- Delete: `scripts/game/exploration/fog_service.gd`
- Delete: `scripts/game/exploration/fog_service.gd.uid`
- Delete: `tests/fog_service_test.gd`
- Delete: `tests/fog_service_test.gd.uid`
- Modify: `tests/exploration_coordinator_test.gd`
- Modify: `docs/plans/2026-08-06-placement-event-spawn-design.md`（仅在实际迁移差异需要记录时）

**Interfaces:**
- 项目中不再有任何 `FogService`、`fog_revealed`、`reveal_for_placement`、`on_cells_revealed` 或 `get_revealed_count` 的运行时引用。

- [ ] **Step 1: 搜索所有迷雾引用。**

运行：

```powershell
rg -n "FogService|fog_revealed|reveal_for_placement|on_cells_revealed|get_revealed_count|scheduled_event_reveal_thresholds|boss_reveal_threshold" scripts tests data --glob '!*.uid'
```

预期：只剩待删除测试或旧配置引用，不能有生产运行时调用。

- [ ] **Step 2: 删除旧服务和迷雾测试。**

删除明确不再使用的文件，确保不存在其他脚本通过 `preload()` 引用它们。不要删除与 Boss 追击、事件接触、信仰值相关的测试。

- [ ] **Step 3: 运行静态搜索和协调器测试。**

运行：

```powershell
rg -n "FogService|fog_revealed|reveal_for_placement|on_cells_revealed|get_revealed_count|scheduled_event_reveal_thresholds|boss_reveal_threshold" scripts tests data --glob '!*.uid'
& 'D:\InstallPath\godot\Godot_v4.7-stable_win64_console.exe' --headless --path . --user-data-dir $env:TEMP\monocard-no-fog --script res://tests/exploration_coordinator_test.gd
```

预期：搜索无结果，协调器测试通过。

- [ ] **Step 4: 提交迷雾移除。**

```powershell
git add -A scripts/game/exploration tests data docs/plans/2026-08-06-placement-event-spawn-design.md
git commit -m "refactor(exploration): remove fog-driven event generation"
```

---

## Task 6: 全量验证和回归检查

**Files:**
- Modify only files required to fix test failures; do not change unrelated gameplay data.

- [ ] **Step 1: 生成并检查所有 UID。**

运行：

```powershell
& 'D:\InstallPath\godot\Godot_v4.7-stable_win64_console.exe' --headless --path . --editor --quit --user-data-dir $env:TEMP\monocard-placement-event-final-uid
```

检查新建 `.gd` 文件都有对应 `.gd.uid`，并执行：

```powershell
git diff --check
```

- [ ] **Step 2: 运行探索相关测试。**

运行：

```powershell
$tests = @(
  'tests/event_spawn_candidate_test.gd',
  'tests/exploration_spawn_config_test.gd',
  'tests/exploration_event_spawn_test.gd',
  'tests/exploration_coordinator_test.gd',
  'tests/exploration_config_test.gd',
  'tests/boss_pressure_config_test.gd',
  'tests/boss_pressure_board_test.gd',
  'tests/ribwood_event_lib_test.gd',
  'tests/guide_card_test.gd',
  'tests/game_manager_faith_test.gd'
)
foreach ($test in $tests) {
  & 'D:\InstallPath\godot\Godot_v4.7-stable_win64_console.exe' --headless --path . --user-data-dir (Join-Path $env:TEMP ([IO.Path]::GetFileNameWithoutExtension($test))) --script ("res://" + $test)
  if ($LASTEXITCODE -ne 0) { throw "Test failed: $test" }
}
```

预期：所有探索、Boss、GUIDE、信仰值相关测试退出码为 0。

- [ ] **Step 3: 运行完整测试集。**

复用仓库已有的全量测试脚本列表，逐个执行全部 `tests/*.gd`，每个测试使用独立 `--user-data-dir`，记录失败脚本和 Godot 错误输出。预期：全部退出码为 0；允许既有资源泄漏或刻意失败路径日志，但不得有新增失败。

- [ ] **Step 4: 检查最终差异并提交。**

运行：

```powershell
git status --short
git diff --stat
git diff --check
git log --oneline -8
```

确认变更只覆盖本计划列出的探索、Ribwood 配置和测试文件，然后提交：

```powershell
git add -A
git commit -m "feat(exploration): replace fog with placement event spawning"
```

---

## 验收结果

实现完成后必须满足：

- 初始棋盘立即拥有配置数量的事件；
- ROOT/普通牌放置后按权重生成 0～2 个事件；
- GUIDE 放置不会触发动态事件；
- 所有新事件从全棋盘合法空位随机放置；
- 每关可独立配置事件池、权重、数量和未解决事件上限；
- Boss 按成功探索牌次数出现，且没有合法空间时可以延迟生成；
- Boss 仍是普通事件并通过落牌接触触发；
- Boss 追击开关和阶段行为保持不变；
- 迷雾驱动代码、字段和测试路径已移除；
- 信仰值、RETREAT、回潮强化、GUIDE 和战斗相关测试无回归。
