# 事件分类目录与运行时状态重构 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将事件脚本按核心、商店、宝藏和遭遇四个职责域重组，并以类型化运行时状态替代 `EventInstance` 中不断增长的事件专属字段。

**Architecture:** `EventData` 持有只读的 `EventContent` 配置，并在创建 `EventInstance` 时创建对应的 `EventRuntimeState`。事件实例只保存位置和通用生命周期；商店、宝藏和遭遇分别通过专属 Resolver 读取匹配的 Content + RuntimeState。Boss 继承遭遇配置与运行时流程，不复制普通怪物战斗基础。

**Tech Stack:** Godot 4.7、GDScript、Godot `.tres` Resource、headless SceneTree 测试、Git。

## Global Constraints

- 在执行前使用隔离 worktree 创建 `codex/event-type-directory-runtime-state` 分支；不得在当前 `master` 工作树直接迁移脚本。
- 不覆盖、回退、暂存或提交当前主工作树已有的未提交事件脚本和 `.uid` 修改。
- 事件触发仍限定为新卡牌合法落位并重叠唯一未解决事件；本重构不得改变该规则。
- `EventData.EventType` 的枚举顺序必须保持 `SHOP, TREASURE, MONSTER, BOSS`，以兼容序列化整数值。
- `EventInstance.resolve()` 必须同时设置 `is_revealed = true` 和 `is_resolved = true`。
- 最终状态中，运行时状态只保存单次事件的可变数据；静态配置只保存于 `EventContent` 及其子类。Task 1 的过渡提交可暂留旧字段，以确保每个提交可运行；Task 2–3 必须将其移除。
- Boss 首版只复用遭遇战流程与怪物创建，不实现阶段、多怪物或特殊胜负条件。
- 文件移动必须使用 `git mv`；随后更新所有 `res://scripts/game/event/...` 的 preload 和 `data/event/**/*.tres` 外部脚本路径。
- 不手工复制现有 `.uid` 文件。由 Godot 重新扫描生成，并在最终 Git 状态中只保留与实际移动/新建脚本对应的 UID 变更。
- 每个任务只提交该任务的脚本、资源和测试；提交前执行 `git diff --check`。

---

## 文件结构与职责

```text
scripts/game/event/
├── core/
│   ├── event_content.gd                 # 全部事件静态内容的基类
│   ├── event_runtime_state.gd           # 全部事件单次运行时状态的基类
│   ├── event_data.gd                    # 事件模板与实例工厂
│   ├── event_instance.gd                # 通用位置与生命周期状态
│   ├── event_entry.gd                   # 事件库生成条目
│   ├── event_lib.gd                     # 事件实例与棋盘节点工厂
│   ├── event_placement_service.gd       # 初始事件位置生成
│   └── event_resolution_result.gd       # 各类事件共享的结算结果
├── shop/
│   ├── shop_event_content.gd            # 商品静态配置
│   ├── shop_runtime_state.gd            # 售罄标记
│   ├── shop_item_data.gd                # 单个商品配置
│   └── shop_event_resolver.gd           # 购买校验和状态写入
├── treasure/
│   ├── treasure_event_content.gd        # 卡池和金币范围
│   ├── treasure_runtime_state.gd        # 奖励选项缓存和领取索引
│   ├── treasure_reward_option.gd        # 单个卡牌或金币奖励
│   └── treasure_event_resolver.gd       # 选项生成与领取
└── encounter/
    ├── encounter_event_content.gd       # 普通怪物与 Boss 的共享怪物配置
    ├── monster_event_content.gd         # 普通遭遇内容类型
    ├── boss_event_content.gd            # Boss 内容类型与未来扩展点
    ├── encounter_runtime_state.gd       # 当前怪物与遭遇生命周期
    ├── encounter_event_resolver.gd      # 创建并缓存当前怪物的桥接层
    ├── mob_data.gd                      # 怪物静态数据
    ├── mob_instance.gd                  # 单次怪物运行时数据
    └── mob_action.gd                    # 怪物行动配置
```

测试保留为两个可执行脚本：

- `tests/event_runtime_test.gd`：核心创建、商店、宝藏、遭遇和资源路径的运行时单元测试；
- `tests/event_trigger_test.gd`：棋盘落牌触发、事件间隔和交互锁的回归测试。

---

### Task 1: 建立核心抽象并迁移公共事件脚本

**Files:**
- Create: `scripts/game/event/core/event_content.gd`
- Create: `scripts/game/event/core/event_runtime_state.gd`
- Move: `scripts/game/event/event_data.gd` → `scripts/game/event/core/event_data.gd`
- Move: `scripts/game/event/event_zone.gd` → `scripts/game/event/core/event_instance.gd`
- Move: `scripts/game/event/event_entry.gd` → `scripts/game/event/core/event_entry.gd`
- Move: `scripts/game/event/event_lib.gd` → `scripts/game/event/core/event_lib.gd`
- Move: `scripts/game/event/event_placement_service.gd` → `scripts/game/event/core/event_placement_service.gd`
- Move: `scripts/game/event/event_resolution_result.gd` → `scripts/game/event/core/event_resolution_result.gd`
- Modify: `scripts/game/board.gd`
- Modify: `scripts/game/event.gd`
- Modify: `tests/event_runtime_test.gd`
- Modify: `tests/event_trigger_test.gd`

**Interfaces:**
- Consumes: existing `EventData.EventType`, `BoardEvent`, `Board`, `EventLib` and event trigger signal semantics.
- Produces:
  ```gdscript
  class_name EventRuntimeState
  extends RefCounted

  class_name EventContent
  extends Resource
  func create_runtime_state() -> EventRuntimeState

  class_name EventInstance
  extends RefCounted
  var template: EventData
  var origin: Vector2i
  var is_revealed := false
  var is_resolved := false
  var runtime_state: EventRuntimeState
  func resolve() -> void
  ```
  Later tasks rely on `EventData.create_instance()` always assigning a non-null `runtime_state`.

- [ ] **Step 1: Add failing core lifecycle tests**

  In `tests/event_runtime_test.gd`, replace old core preload paths with the target `core/` paths and add these calls to `_init()`:

  ```gdscript
  _test_event_instance_creates_base_runtime_state_for_missing_content()
  _test_resolve_marks_event_revealed_and_resolved()
  ```

  Add tests:

  ```gdscript
  func _test_event_instance_creates_base_runtime_state_for_missing_content() -> void:
      var template := EventDataScript.new()
      var instance := template.create_instance()
      _expect(instance.runtime_state != null, "event instance always owns runtime state")
      _expect(not instance.is_revealed and not instance.is_resolved, "new event begins unresolved")

  func _test_resolve_marks_event_revealed_and_resolved() -> void:
      var instance := EventInstanceScript.new()
      instance.resolve()
      _expect(instance.is_revealed, "resolve reveals the event")
      _expect(instance.is_resolved, "resolve marks the event resolved")
  ```

  Update `tests/event_trigger_test.gd` preloads for `EventData` and `EventInstance` to the new `core/` paths.

- [ ] **Step 2: Run the core test and verify it fails**

  Run:

  ```powershell
  & 'D:\InstallPath\godot\Godot_v4.7-stable_win64_console.exe' --headless --path . --script tests/event_runtime_test.gd
  ```

  Expected: non-zero exit because `res://scripts/game/event/core/event_data.gd` and `event_instance.gd` do not exist yet.

- [ ] **Step 3: Move common files and add the two base classes**

  Run `git mv` for the seven public scripts listed in **Files**. Create the base scripts:

  ```gdscript
  # scripts/game/event/core/event_runtime_state.gd
  class_name EventRuntimeState
  extends RefCounted
  ```

  ```gdscript
  # scripts/game/event/core/event_content.gd
  class_name EventContent
  extends Resource

  const EventRuntimeStateScript = preload("res://scripts/game/event/core/event_runtime_state.gd")

  func create_runtime_state() -> EventRuntimeStateScript:
      return EventRuntimeStateScript.new()
  ```

  In `core/event_data.gd`, retain the current enum order and replace the untyped content field and factory with:

  ```gdscript
  const EventContentScript = preload("res://scripts/game/event/core/event_content.gd")
  const EventInstanceScript = preload("res://scripts/game/event/core/event_instance.gd")
  const EventRuntimeStateScript = preload("res://scripts/game/event/core/event_runtime_state.gd")

  @export var content: EventContentScript

  func create_instance() -> EventInstanceScript:
      var instance := EventInstanceScript.new()
      instance.template = self
      instance.origin = Vector2i(-1, -1)
      instance.runtime_state = content.create_runtime_state() if content else EventRuntimeStateScript.new()
      return instance
  ```

  In `core/event_instance.gd`, add `runtime_state` and implement the lifecycle method below. Keep `shop_sold_flags`, `treasure_options`, and `selected_treasure_option` only for this transitional commit because the existing shared resolver still reads them. Task 2 removes the shop field; Task 3 removes both treasure fields and the treasure-option preload:

  ```gdscript
  func resolve() -> void:
      is_revealed = true
      is_resolved = true
  ```

  Update `core/event_lib.gd`, `core/event_placement_service.gd`, `scripts/game/board.gd`, `scripts/game/event.gd`, and `scripts/game/event/event_reward_resolver.gd` to load the new core paths. Change the three still-flat content resources (`event_shop_content.gd`, `event_treasure_content.gd`, `event_monster_content.gd`) to `extends EventContent` so `EventData.content` accepts them during the migration. Keep the existing `class_name` values (`EventData`, `EventInstance`, `EventEntry`, `EventLib`, `EventPlacementService`, `EventResolutionResult`) so scene and resource class identities remain stable.

- [ ] **Step 4: Run core and trigger tests**

  Run:

  ```powershell
  & 'D:\InstallPath\godot\Godot_v4.7-stable_win64_console.exe' --headless --editor --path . --quit
  & 'D:\InstallPath\godot\Godot_v4.7-stable_win64_console.exe' --headless --path . --script tests/event_runtime_test.gd
  & 'D:\InstallPath\godot\Godot_v4.7-stable_win64_console.exe' --headless --path . --script tests/event_trigger_test.gd
  ```

  Expected: both processes exit `0`. This confirms the additive core migration preserves existing shop and treasure behavior before their dedicated refactors.

- [ ] **Step 5: Commit the core migration**

  ```powershell
  git add scripts/game/event/core scripts/game/board.gd scripts/game/event.gd scripts/game/event/event_shop_content.gd scripts/game/event/event_treasure_content.gd scripts/game/event/event_monster_content.gd scripts/game/event/event_reward_resolver.gd tests/event_runtime_test.gd tests/event_trigger_test.gd
  git diff --cached --check
  git commit -m "refactor: extract core event runtime state"
  ```

### Task 2: 将商店状态和购买逻辑收敛到商店域

**Files:**
- Move: `scripts/game/event/event_shop_content.gd` → `scripts/game/event/shop/shop_event_content.gd`
- Move: `scripts/game/event/shop_item_data.gd` → `scripts/game/event/shop/shop_item_data.gd`
- Create: `scripts/game/event/shop/shop_runtime_state.gd`
- Create: `scripts/game/event/shop/shop_event_resolver.gd`
- Modify: `tests/event_runtime_test.gd`

**Interfaces:**
- Consumes: `EventContent.create_runtime_state()`, `EventInstance.runtime_state`, `EventResolutionResult`, `PlayerData.gold`.
- Produces:
  ```gdscript
  class_name ShopRuntimeState
  extends EventRuntimeState
  var sold_flags: Array[bool] = []

  class_name ShopEventContent
  extends EventContent
  var items: Array[ShopItemData]
  func create_runtime_state() -> ShopRuntimeState

  class_name ShopEventResolver
  extends RefCounted
  func purchase_item(instance: EventInstance, item_index: int, player: PlayerData, hand_has_capacity: bool) -> EventResolutionResult
  ```

- [ ] **Step 1: Write failing shop-runtime tests**

  In `tests/event_runtime_test.gd`, replace old shop content and shared resolver preloads with `ShopEventContent`, `ShopRuntimeState`, and `ShopEventResolver`. Change shop assertions to inspect typed state:

  ```gdscript
  var state := instance.runtime_state as ShopRuntimeStateScript
  _expect(state != null, "shop instance creates shop runtime state")
  _expect(state.sold_flags == [true], "marks item sold in shop runtime state")
  ```

  Add mismatch coverage:

  ```gdscript
  func _test_shop_rejects_mismatched_runtime_state() -> void:
      var player := PlayerDataScript.new()
      player.gold = 10
      var instance := _make_shop_instance([_offer("Twig Blade", 6)])
      instance.runtime_state = EventRuntimeStateScript.new()
      var result := shop_resolver.purchase_item(instance, 0, player, true)
      _expect(result.failure == EventResolutionResultScript.Failure.INVALID_EVENT, "shop rejects wrong runtime state")
      _expect(player.gold == 10 and not instance.is_resolved, "wrong shop state does not mutate event")
  ```

  Update `_snapshot_runtime_state()` to derive `sold_flags` only when `instance.runtime_state is ShopRuntimeStateScript`; do not restore a generic field on `EventInstance`.

- [ ] **Step 2: Run the runtime test and verify shop failures**

  Run the runtime test command from Task 1.

  Expected: non-zero exit because `ShopRuntimeState` and `ShopEventResolver` do not exist yet, or because old shared resolver calls are no longer valid.

- [ ] **Step 3: Implement the shop domain**

  Move the two existing scripts. Rename their classes to `ShopEventContent` and `ShopItemData`, and update their internal preload. Implement:

  ```gdscript
  # shop_runtime_state.gd
  class_name ShopRuntimeState
  extends EventRuntimeState

  var sold_flags: Array[bool] = []
  ```

  ```gdscript
  # shop_event_content.gd
  class_name ShopEventContent
  extends EventContent

  const ShopRuntimeStateScript = preload("res://scripts/game/event/shop/shop_runtime_state.gd")
  @export var items: Array[ShopItemData] = []

  func create_runtime_state() -> ShopRuntimeStateScript:
      return ShopRuntimeStateScript.new()
  ```

  Transfer only `purchase_shop_item`, `_is_shop_item_sold`, and `_ensure_shop_sold_flags` from the old shared resolver. Rename the public method to `purchase_item`. Remove `shop_sold_flags` from `core/event_instance.gd` in this task, then delete `purchase_shop_item`, `_is_shop_item_sold`, and `_ensure_shop_sold_flags` from the remaining old shared resolver so no production code reads the removed field. Validate in this order: instance/player → shop content + `ShopRuntimeState` → index → unresolved → sold state → hand capacity → item non-null → gold. On every rejected result, preserve player gold, `sold_flags`, and lifecycle flags. On success, deduct price, mark `sold_flags[item_index] = true`, return `granted_card`, and leave the shop unresolved.

- [ ] **Step 4: Run the shop subset and full runtime test**

  Run:

  ```powershell
  & 'D:\InstallPath\godot\Godot_v4.7-stable_win64_console.exe' --headless --path . --script tests/event_runtime_test.gd
  ```

  Expected: all shop assertions pass; treasure failures may remain until Task 3 only if the test is intentionally split during this task.

- [ ] **Step 5: Commit the shop domain**

  ```powershell
  git add scripts/game/event/shop tests/event_runtime_test.gd
  git diff --cached --check
  git commit -m "refactor: isolate shop event runtime"
  ```

### Task 3: 将宝藏状态、缓存与领取逻辑收敛到宝藏域

**Files:**
- Move: `scripts/game/event/event_treasure_content.gd` → `scripts/game/event/treasure/treasure_event_content.gd`
- Move: `scripts/game/event/treasure_reward_option.gd` → `scripts/game/event/treasure/treasure_reward_option.gd`
- Create: `scripts/game/event/treasure/treasure_runtime_state.gd`
- Create: `scripts/game/event/treasure/treasure_event_resolver.gd`
- Delete: `scripts/game/event/event_reward_resolver.gd`
- Modify: `tests/event_runtime_test.gd`

**Interfaces:**
- Consumes: core contracts from Task 1 and the `EventResolutionResult` failure enum.
- Produces:
  ```gdscript
  class_name TreasureRuntimeState
  extends EventRuntimeState
  var options: Array[TreasureRewardOption] = []
  var selected_option_index := -1

  class_name TreasureEventResolver
  extends RefCounted
  func ensure_options(instance: EventInstance, rng: RandomNumberGenerator) -> Array[TreasureRewardOption]
  func claim_reward(instance: EventInstance, option_index: int, player: PlayerData, hand_has_capacity: bool, rng: RandomNumberGenerator) -> EventResolutionResult
  ```

- [ ] **Step 1: Write failing treasure-runtime tests**

  Update `tests/event_runtime_test.gd` to use `TreasureEventContent`, `TreasureRuntimeState`, `TreasureRewardOption`, and `TreasureEventResolver`. Replace every direct access to `instance.treasure_options` and `instance.selected_treasure_option` with:

  ```gdscript
  var state := instance.runtime_state as TreasureRuntimeStateScript
  ```

  Add this explicit lifecycle test after a successful claim:

  ```gdscript
  _expect(instance.is_revealed and instance.is_resolved, "treasure claim resolves the event")
  _expect(state.selected_option_index == option_index, "treasure records the chosen option in runtime state")
  ```

  Add a mismatched-state test analogous to the shop test, expecting `INVALID_EVENT` and no mutation.

- [ ] **Step 2: Run the runtime test and verify treasure failures**

  Run the runtime test command from Task 1.

  Expected: non-zero exit because treasure-domain files and `claim_reward` do not exist yet.

- [ ] **Step 3: Implement the treasure domain**

  Move existing content and option scripts, changing class names to `TreasureEventContent` and `TreasureRewardOption`. Remove `treasure_options`, `selected_treasure_option`, and the treasure-option preload from `core/event_instance.gd` in this task. Implement:

  ```gdscript
  # treasure_runtime_state.gd
  class_name TreasureRuntimeState
  extends EventRuntimeState

  var options: Array[TreasureRewardOption] = []
  var selected_option_index := -1
  ```

  ```gdscript
  # treasure_event_content.gd
  class_name TreasureEventContent
  extends EventContent

  const TreasureRuntimeStateScript = preload("res://scripts/game/event/treasure/treasure_runtime_state.gd")

  func create_runtime_state() -> TreasureRuntimeStateScript:
      return TreasureRuntimeStateScript.new()
  ```

  Transfer `ensure_treasure_options` and `claim_treasure_reward` to `TreasureEventResolver` under the new method names. Preserve the existing reward invariant: with at least two unique card resources, first generation produces exactly two distinct card options and one gold option. Cache options in `TreasureRuntimeState.options`; do not reroll after a failed claim or a reopened unresolved event. A card choice checks hand capacity; a gold choice does not. A successful claim writes `selected_option_index`, applies reward, and calls `instance.resolve()`.

  Delete `event_reward_resolver.gd` only after all shop and treasure calls in tests use their new resolvers.

- [ ] **Step 4: Run the complete event runtime suite**

  Run:

  ```powershell
  & 'D:\InstallPath\godot\Godot_v4.7-stable_win64_console.exe' --headless --editor --path . --quit
  & 'D:\InstallPath\godot\Godot_v4.7-stable_win64_console.exe' --headless --path . --script tests/event_runtime_test.gd
  ```

  Expected: exit code `0`; all existing shop and treasure assertions plus new runtime-state and lifecycle assertions pass.

- [ ] **Step 5: Commit the treasure domain**

  ```powershell
  git add scripts/game/event/treasure scripts/game/event/event_reward_resolver.gd tests/event_runtime_test.gd
  git diff --cached --check
  git commit -m "refactor: isolate treasure event runtime"
  ```

### Task 4: 建立遭遇与 Boss 的共享内容、状态和怪物创建边界

**Files:**
- Create: `scripts/game/event/encounter/encounter_event_content.gd`
- Move: `scripts/game/event/event_monster_content.gd` → `scripts/game/event/encounter/monster_event_content.gd`
- Create: `scripts/game/event/encounter/boss_event_content.gd`
- Create: `scripts/game/event/encounter/encounter_runtime_state.gd`
- Create: `scripts/game/event/encounter/encounter_event_resolver.gd`
- Move: `scripts/game/event/mob_data.gd` → `scripts/game/event/encounter/mob_data.gd`
- Move: `scripts/game/event/mob_instance.gd` → `scripts/game/event/encounter/mob_instance.gd`
- Move: `scripts/game/event/mob_action.gd` → `scripts/game/event/encounter/mob_action.gd`
- Modify: `tests/event_runtime_test.gd`
- Modify: `tests/combatv2_service_test.gd`
- Modify: `tests/combat_service_test.gd`
- Modify: `tests/combat_model_test.gd`

**Interfaces:**
- Consumes: `EventContent`, `EventRuntimeState`, `EventInstance`, existing `MobData.create_instance()` and combat-v2 tests.
- Produces:
  ```gdscript
  class_name EncounterEventContent
  extends EventContent
  @export var mob: MobData
  @export_range(1, 99, 1) var count := 1
  func create_runtime_state() -> EncounterRuntimeState

  class_name MonsterEventContent
  extends EncounterEventContent

  class_name BossEventContent
  extends EncounterEventContent

  class_name EncounterRuntimeState
  extends EventRuntimeState
  var mob_instance: MobInstance
  var has_started := false

  class_name EncounterEventResolver
  extends RefCounted
  func begin(instance: EventInstance) -> MobInstance
  ```

- [ ] **Step 1: Write failing encounter tests**

  In `tests/event_runtime_test.gd`, add target preloads for `MonsterEventContentScript`, `BossEventContentScript`, `EncounterRuntimeStateScript`, `EncounterEventResolverScript`, and `MobDataScript`, then add these calls to `_init():`

  ```gdscript
  _test_monster_and_boss_create_encounter_runtime_state()
  _test_encounter_begin_caches_a_single_mob_instance()
  _test_encounter_rejects_non_encounter_content()
  ```

  Use these test bodies:

  ```gdscript
  func _mob(mob_name: String) -> MobDataScript:
      var mob := MobDataScript.new()
      mob.mob_name = mob_name
      return mob
  func _make_monster_content() -> MonsterEventContentScript:
      var content := MonsterEventContentScript.new()
      content.mob = _mob("Plan Test Monster")
      return content

  func _make_boss_content() -> BossEventContentScript:
      var content := BossEventContentScript.new()
      content.mob = _mob("Plan Test Boss")
      return content

  func _test_monster_and_boss_create_encounter_runtime_state() -> void:
      var monster_instance := _make_instance(EventDataScript.EventType.MONSTER, _make_monster_content())
      var boss_instance := _make_instance(EventDataScript.EventType.BOSS, _make_boss_content())
      _expect(monster_instance.runtime_state is EncounterRuntimeStateScript, "monster creates encounter state")
      _expect(boss_instance.runtime_state is EncounterRuntimeStateScript, "boss creates encounter state")

  func _test_encounter_begin_caches_a_single_mob_instance() -> void:
      var instance := _make_instance(EventDataScript.EventType.MONSTER, _make_monster_content())
      var first := encounter_resolver.begin(instance)
      var second := encounter_resolver.begin(instance)
      _expect(first != null and first == second, "encounter reuses its single mob instance")
      _expect((instance.runtime_state as EncounterRuntimeStateScript).has_started, "encounter state records start")

  func _test_encounter_rejects_non_encounter_content() -> void:
      var instance := _make_shop_instance([])
      _expect(encounter_resolver.begin(instance) == null, "encounter resolver rejects shop event")
  ```

- [ ] **Step 2: Run the runtime test and verify encounter failures**

  Run the runtime test command from Task 1.

  Expected: non-zero exit because encounter-domain classes do not exist.

- [ ] **Step 3: Implement the encounter domain without adding combat rules**

  Move the monster and mob scripts with `git mv`; update their `preload` paths and preserve `MobData`, `MobInstance`, and `MobAction` class names. Create:

  ```gdscript
  # encounter_event_content.gd
  class_name EncounterEventContent
  extends EventContent

  const EncounterRuntimeStateScript = preload("res://scripts/game/event/encounter/encounter_runtime_state.gd")

  @export var mob: MobData = null
  @export_range(1, 99, 1) var count := 1

  func create_runtime_state() -> EncounterRuntimeStateScript:
      return EncounterRuntimeStateScript.new()
  ```

  ```gdscript
  # monster_event_content.gd
  class_name MonsterEventContent
  extends EncounterEventContent
  ```

  ```gdscript
  # boss_event_content.gd
  class_name BossEventContent
  extends EncounterEventContent
  ```

  ```gdscript
  # encounter_runtime_state.gd
  class_name EncounterRuntimeState
  extends EventRuntimeState

  var mob_instance: MobInstance
  var has_started := false
  ```

  `EncounterEventResolver.begin()` must validate `EncounterEventContent` and `EncounterRuntimeState`, return `null` for invalid configuration or a missing `mob`, and otherwise create `content.mob.create_instance()` once, cache it in `state.mob_instance`, set `has_started`, and return the cached object on repeated calls. It must not call `CombatService` in this task; it creates the stable bridge point that a later combat-integration task can use.

- [ ] **Step 4: Update combat test imports and run supported combat-v2 regression**

  Replace all old `mob_data.gd` and `mob_action.gd` paths in `tests/combatv2_service_test.gd`, `tests/combat_service_test.gd`, and `tests/combat_model_test.gd` with `encounter/` paths. Do not repair the pre-existing obsolete `combat_model_test.gd` dependency on removed legacy `CombatStats` scripts.

  Run:

  ```powershell
  & 'D:\InstallPath\godot\Godot_v4.7-stable_win64_console.exe' --headless --path . --script tests/event_runtime_test.gd
  & 'D:\InstallPath\godot\Godot_v4.7-stable_win64_console.exe' --headless --path . --script tests/combatv2_service_test.gd
  ```

  Expected: both commands exit `0`.

- [ ] **Step 5: Commit the encounter domain**

  ```powershell
  git add scripts/game/event/encounter tests/event_runtime_test.gd tests/combatv2_service_test.gd tests/combat_service_test.gd tests/combat_model_test.gd
  git diff --cached --check
  git commit -m "refactor: group monster and boss encounter data"
  ```

### Task 5: 更新资源引用、清理旧路径并执行全量回归

**Files:**
- Modify: every `data/event/**/*.tres` whose external script path begins with `res://scripts/game/event/`
- Modify: all remaining GDScript/scene preloads discovered by a repository-wide search
- Delete: empty legacy directory `scripts/game/event/` files that were moved in Tasks 1–4
- Modify: `tests/event_runtime_test.gd`
- Modify: `tests/event_trigger_test.gd`

**Interfaces:**
- Consumes: the target files and class names established in Tasks 1–4.
- Produces: no loadable resource, scene, test, or production preload refers to a removed flat `scripts/game/event/*.gd` path.

- [ ] **Step 1: Add a failing resource-path assertion**

  Add this helper and test to `tests/event_runtime_test.gd`:

  ```gdscript
  func _test_event_resources_load_after_directory_migration() -> void:
      var resource_paths := [
          "res://data/event/event_lib.tres",
          "res://data/event/events/forest_wolf_event.tres",
          "res://data/event/events/miasma_grove_guardian_boss_event.tres",
          "res://data/event/content/event_shop_content.tres",
          "res://data/event/content/event_treasure_content.tres",
      ]
      for resource_path in resource_paths:
          _expect(load(resource_path) != null, "%s loads after event script migration" % resource_path)
  ```

- [ ] **Step 2: Run the resource-path test and verify it fails before references are updated**

  Run the runtime test command from Task 1.

  Expected: non-zero exit with missing-script or failed-resource errors naming an old flat event script path.

- [ ] **Step 3: Rewrite all serialized script paths and remaining code preloads**

  Update every `data/event/**/*.tres` script external resource as follows:

  ```text
  event_data.gd                 -> core/event_data.gd
  event_entry.gd                -> core/event_entry.gd
  event_lib.gd                  -> core/event_lib.gd
  event_shop_content.gd         -> shop/shop_event_content.gd
  event_treasure_content.gd     -> treasure/treasure_event_content.gd
  event_monster_content.gd      -> encounter/monster_event_content.gd
  mob_data.gd                   -> encounter/mob_data.gd
  mob_action.gd                 -> encounter/mob_action.gd
  ```

  For `data/event/content/miasma_grove_guardian_boss_content.tres`, change its script to `boss_event_content.gd`; all ordinary monster content resources use `monster_event_content.gd`. Preserve existing resource values (`mob`, `count`, card pools, item lists, and event enum values).

  Run a repository search:

  ```powershell
  Get-ChildItem -Path scripts,tests,scenes,data -Recurse -File -Include *.gd,*.tscn,*.tres |
    Select-String -Pattern 'res://scripts/game/event/(event_|mob_|shop_item_data|treasure_reward_option)'
  ```

  Update every returned reference so the search prints no result. Do not search-and-replace unrelated `scripts/game/event.gd`, which is the board event display script and intentionally remains outside the `event/` directory.

- [ ] **Step 4: Re-import and execute all supported regression tests**

  Run:

  ```powershell
  & 'D:\InstallPath\godot\Godot_v4.7-stable_win64_console.exe' --headless --editor --path . --quit
  & 'D:\InstallPath\godot\Godot_v4.7-stable_win64_console.exe' --headless --path . --script tests/event_runtime_test.gd
  & 'D:\InstallPath\godot\Godot_v4.7-stable_win64_console.exe' --headless --path . --script tests/event_trigger_test.gd
  & 'D:\InstallPath\godot\Godot_v4.7-stable_win64_console.exe' --headless --path . --script tests/combatv2_card_rule_test.gd
  & 'D:\InstallPath\godot\Godot_v4.7-stable_win64_console.exe' --headless --path . --script tests/combatv2_service_test.gd
  ```

  Expected: each process exits `0`. `event_trigger_test.gd` may print its intentional defensive `push_error` paths for multi-event overlap and drag restore recovery; these logs are expected when the process exits successfully.

- [ ] **Step 5: Inspect generated files and commit final resource migration**

  Verify no accidental editor cache files are staged:

  ```powershell
  git status --short
  git diff --check
  ```

  Stage only updated `data/event` resources, actual script `.uid` files for moved/new scripts, and modified test files:

  ```powershell
  git add data/event tests/event_runtime_test.gd tests/event_trigger_test.gd scripts/game/event
  git diff --cached --check
  git commit -m "refactor: update event resource paths"
  ```

---

## Final Review Checklist

- [ ] `EventInstance` has no shop, treasure, monster, or Boss-specific mutable fields.
- [ ] `EventData.create_instance()` always assigns a non-null `runtime_state`.
- [ ] Shop and treasure resolvers return `INVALID_EVENT` without mutation for content/state mismatch.
- [ ] `resolve()` makes `is_revealed` and `is_resolved` both true.
- [ ] Shop success leaves the shop unresolved; treasure success resolves it.
- [ ] Two unique treasure cards plus one gold option remain the invariant when the card pool contains at least two unique cards.
- [ ] Monster and Boss both produce `EncounterRuntimeState` and reuse the single-mob creation resolver.
- [ ] No script, test, scene, or event resource retains a stale flat event-script path.
- [ ] The four supported headless regression commands exit `0`.
- [ ] No pre-existing dirty changes from the main worktree are included in this branch's commits.
