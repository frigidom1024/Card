# 主菜单、牌根选择与新局流程 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在不破坏既有森林探索、事件和战斗流程的前提下，实现“主菜单 → 牌根选择 → 根据固定完整起始牌组开启一局探索”的可测试入口流程。

**Architecture:** `Main` 只负责销毁和实例化主页面；`MainMenuScreen` 与 `RootSelectionScreen` 是独立的全屏 UI，且只通过信号请求跳转。`StartingDeckData` 是只读的静态资源，`GameManager` 在加入场景前接收已选预设，并在 `_ready()` 中复制 `PlayerData`、创建新的 `CardInstance`、根据已解析的根牌注入默认或专用的 `CombatService2`。

**Tech Stack:** Godot 4.7、GDScript、`.tscn` 场景、`.tres` Resource、无外部测试框架的 `SceneTree` headless 测试。

## Global Constraints

- 基准玩法分辨率保持 1920×1080；`BackgroundLayer` 始终覆盖真实窗口，菜单 UI 不进入 `GameplayCanvas`。
- `starter_cards` 表示完整起始牌组，必须包含且只包含一张 `CardData.CardType.ROOT`；总数永远是 `starter_cards.size()`。
- `CardData`、`StartingDeckData` 和场景导出的基础 `PlayerData` 只用于定义，运行时不得写回这些 Resource。
- 菜单、选择页与探索页同一时间只保留一个；切换时销毁旧 UI，防止隐藏节点接收输入。
- `RootSelectionScreen` 不创建 `GameManager`、不创建战斗服务；`GameManager` 不读取菜单 UI 节点。
- 牌根和起始卡预览必须复用 `CardEntity`，且展示模式禁止拖拽、放大、悬浮信息、Area2D 输入和加入 `DragLayer`。
- 不恢复或新增 pass-through `CombatServiceRouter`；默认根牌直接使用 `CombatService2`。
- 每项实现先写对应失败测试，再实现最小逻辑；每项通过后单独提交。

---

## File Structure

| 路径 | 责任 |
|---|---|
| `scripts/run/starting_deck_data.gd` | 起始牌根选项的只读资源模型、根牌解析与配置校验。 |
| `data/starting_decks/revival_starting_deck.tres` | 首个可选择的“生命之根”完整起始牌组。 |
| `scripts/game/card_manager.gd` | 从 `StartingDeckData.starter_cards` 确定性创建新的 `CardInstance`。 |
| `scripts/game_manager.gd` | 接收预设、复制运行时玩家数据、初始化起始卡，并由根牌创建战斗服务。 |
| `scripts/game/event/encounter/encounter_combat_flow_coordinator.gd` | 直接持有注入的 `CombatService2`，解决遭遇。 |
| `scripts/game/event/encounter/combat_service_router.gd` | 删除；它不提供独立行为。 |
| `scripts/card/card_entity.gd` | 给真实卡面增加明确的只读展示模式。 |
| `scenes/home/main_menu_screen.tscn` / `scripts/home/main_menu_screen.gd` | 顶部 Logo、中部开始按钮、底部版本号和一次性跳转信号。 |
| `scenes/home/root_option_entry.tscn` / `scripts/home/root_option_entry.gd` | 可选择、锁定和无效根牌条目。 |
| `scenes/home/root_selection_screen.tscn` / `scripts/home/root_selection_screen.gd` | 预设校验、选择、响应式布局、真实卡面预览及探索请求。 |
| `scenes/main.tscn` / `scripts/main.gd` | 背景层、`ScreenLayer`、主菜单/选择页/探索页动态路由。 |
| `tests/starting_deck_data_test.gd` | 预设语义、坏配置和确定性起始实例测试。 |
| `tests/card_entity_display_mode_test.gd` | 只读卡面不接收玩法交互测试。 |
| `tests/home_screen_flow_test.gd` | 主菜单、根选择、重复点击、路由和两局资源隔离测试。 |

### Task 1: 起始牌组 Resource 与确定性实例工厂

**Files:**
- Create: `scripts/run/starting_deck_data.gd`
- Create: `data/starting_decks/revival_starting_deck.tres`
- Modify: `scripts/game/card_manager.gd`
- Create: `tests/starting_deck_data_test.gd`

**Interfaces:**
- Produces `StartingDeckData.validate() -> PackedStringArray`、`get_root_card() -> CardData`、`get_remaining_starter_cards() -> Array[CardData]`。
- Produces `CardManager.create_starting_instances(starting_deck: StartingDeckData) -> Array[CardInstance]`；该接口保持 `starter_cards` 的顺序并为每项创建新对象。
- Later tasks consume `deck_id`、`display_name`、`description`、`starter_cards`、`playstyle_tags`、`is_unlocked`，不再调用 `get_init_cards()` 开启正式游戏。

- [ ] **Step 1: 写失败的 Resource / 工厂测试**

```gdscript
extends SceneTree

const StartingDeckDataScript = preload("res://scripts/run/starting_deck_data.gd")
const CardManagerScript = preload("res://scripts/game/card_manager.gd")
const RevivalDeck = preload("res://data/starting_decks/revival_starting_deck.tres")

var failures := 0

func _init() -> void:
    call_deferred("_run")

func _run() -> void:
    _expect(RevivalDeck.validate().is_empty(), "revival preset is valid")
    _expect(RevivalDeck.get_root_card() != null, "preset resolves one root")
    _expect(RevivalDeck.get_remaining_starter_cards().size() == RevivalDeck.starter_cards.size() - 1, "remaining cards exclude only root")
    var manager := CardManagerScript.new()
    var first := manager.create_starting_instances(RevivalDeck)
    var second := manager.create_starting_instances(RevivalDeck)
    _expect(first.size() == RevivalDeck.starter_cards.size(), "factory creates every configured starter")
    _expect(first[0] != second[0] and first[0].card_data == second[0].card_data, "runs use new instances but shared static definitions")
    var bad := StartingDeckDataScript.new()
    bad.deck_id = "bad"; bad.display_name = "bad"; bad.starter_cards = [RevivalDeck.get_root_card(), RevivalDeck.get_root_card()]
    _expect(not bad.validate().is_empty(), "multiple roots are rejected")
    quit(1 if failures > 0 else 0)

func _expect(condition: bool, message: String) -> void:
    if not condition:
        failures += 1
        push_error(message)
```

- [ ] **Step 2: 运行失败测试，确认缺失类型/接口导致失败**

Run:
```powershell
$godot = 'D:\InstallPath\godot\Godot_v4.7-stable_win64_console.exe'
& $godot --headless --path . --script tests\starting_deck_data_test.gd
```
Expected: FAIL，提示 `starting_deck_data.gd`、`validate` 或 `create_starting_instances` 尚不存在。

- [ ] **Step 3: 实现只读预设与工厂**

在 `starting_deck_data.gd` 定义以下完整公开接口：

```gdscript
class_name StartingDeckData
extends Resource

@export var deck_id := ""
@export var display_name := ""
@export_multiline var description := ""
@export var starter_cards: Array[CardData] = []
@export var playstyle_tags: PackedStringArray = []
@export var is_unlocked := true

func validate() -> PackedStringArray:
    var errors := PackedStringArray()
    if deck_id.strip_edges().is_empty(): errors.append("deck_id is empty")
    if display_name.strip_edges().is_empty(): errors.append("display_name is empty")
    if starter_cards.is_empty(): errors.append("starter_cards is empty")
    var root_count := 0
    for card in starter_cards:
        if card == null: errors.append("starter_cards contains null"); continue
        if card.card_type == CardData.CardType.ROOT: root_count += 1
    if root_count != 1: errors.append("starter_cards must contain exactly one ROOT card")
    return errors

func get_root_card() -> CardData:
    if not validate().is_empty(): return null
    for card in starter_cards:
        if card.card_type == CardData.CardType.ROOT: return card
    return null

func get_remaining_starter_cards() -> Array[CardData]:
    var result: Array[CardData] = []
    var root := get_root_card()
    for card in starter_cards:
        if card != root: result.append(card)
    return result
```

将 `CardManager.get_init_cards()` 删除，改为：

```gdscript
func create_starting_instances(starting_deck: StartingDeckData) -> Array[CardInstance]:
    if starting_deck == null or not starting_deck.validate().is_empty():
        push_error("CardManager: invalid StartingDeckData")
        return []
    var result: Array[CardInstance] = []
    for card_data in starting_deck.starter_cards:
        result.append(CardInstance.new(card_data))
    return result
```

创建资源时引用 `PlayerRoot.tres`、`VineShortblade.tres`、`ThornBarrier.tres`、`ClearSpringWoodVial.tres`、`AllThingsRevival.tres`，设置 `deck_id = "revival"`、`display_name = "复苏之根"`、`is_unlocked = true`、`playstyle_tags = ["治疗", "延续", "武器连锁"]`。根牌只出现一次。

- [ ] **Step 4: 运行测试，确认预设和工厂行为通过**

Run: `& $godot --headless --path . --script tests\starting_deck_data_test.gd`

Expected: PASS；有效资源没有校验错误、仅解析一张根牌、两个开局数组对象不同且顺序/静态卡牌引用一致、双根配置被拒绝。

- [ ] **Step 5: 提交最小可用的起始数据边界**

```powershell
git add scripts/run/starting_deck_data.gd scripts/game/card_manager.gd data/starting_decks/revival_starting_deck.tres tests/starting_deck_data_test.gd
git commit -m "feat: add fixed starting deck presets"
```

### Task 2: 用所选预设初始化单局，并移除无行为的战斗路由

**Files:**
- Modify: `scripts/game_manager.gd`
- Modify: `scripts/game/event/encounter/encounter_combat_flow_coordinator.gd`
- Delete: `scripts/game/event/encounter/combat_service_router.gd`
- Modify: `tests/game_manager_combat_routing_test.gd`
- Create: `tests/game_manager_run_setup_test.gd`

**Interfaces:**
- Consumes `StartingDeckData.validate()`、`CardManager.create_starting_instances()`、`StartingDeckData.get_root_card()`。
- Produces `GameManager.configure_run(preset: StartingDeckData) -> bool`，必须在 `add_child()` 前调用；以及 `run_initialization_failed(reason: String)`、`run_finished` 信号。
- Produces `EncounterCombatFlowCoordinator.new(combat_service: CombatService2 = null)`，其 `resolve()` 直接调用注入服务。
- Later tasks create `GameManager` 后仅调用 `configure_run(preset)`，绝不设置菜单 UI 或直接改 `cards_inst`。

- [ ] **Step 1: 写失败的单局初始化和服务注入测试**

在 `tests/game_manager_run_setup_test.gd` 创建以下检查：

```gdscript
var manager := GameManagerScene.instantiate() as Node
_expect(manager.configure_run(RevivalDeck), "valid preset is accepted before ready")
root.add_child(manager)
await manager.ready
_expect(manager.cards_inst.size() == RevivalDeck.starter_cards.size(), "run creates exactly configured cards")
_expect(_count_roots(manager.cards_inst) == 1, "run does not add a second root")
_expect(manager.cards_inst[0] != manager.cards_inst[1], "each starter is a separate runtime instance")
_expect(manager.player_data != BasePlayerData, "run player data is a copy")
_expect(manager.player_data.base_stats != BasePlayerData.base_stats, "nested player stats are a deep copy")
_expect(manager._encounter_combat_flow != null, "run owns an encounter flow")
```

在 `tests/game_manager_combat_routing_test.gd` 新增断言：`EncounterCombatFlowCoordinator.new(CombatService2.new()).resolve(...)` 返回与既有默认服务一致的 `CombatResult`，且测试文件和项目内不存在 `CombatServiceRouter` 引用。

- [ ] **Step 2: 运行失败测试，确认旧随机开局和 router 尚未满足约束**

Run:
```powershell
& $godot --headless --path . --script tests\game_manager_run_setup_test.gd
& $godot --headless --path . --script tests\game_manager_combat_routing_test.gd
```
Expected: FAIL，原因是 `configure_run`、运行时 `PlayerData` 副本或协调器构造注入尚未实现。

- [ ] **Step 3: 实现严格的单局初始化和直接服务依赖**

在 `GameManager` 增加：

```gdscript
signal run_initialization_failed(reason: String)
signal run_finished

var starting_deck: StartingDeckData
var _base_player_data: PlayerData

func configure_run(preset: StartingDeckData) -> bool:
    if preset == null or not preset.validate().is_empty():
        return false
    starting_deck = preset
    return true

func _create_combat_service_for_root(_root_card: CardData) -> CombatService2:
    return CombatService2.new()
```

把 `_ready()` 的开局部分替换为“先校验 `starting_deck` 和导出的 `player_data`，再 `duplicate(true)` 到 `player_data`，从其 `base_stats` 创建 `player_stats`，然后调用 `init_player_cards()`”。`init_player_cards()` 改为 `-> bool`，只调用 `card_manager.create_starting_instances(starting_deck)`；如果任一 `CardEntity` 创建或加入手牌失败，释放已经添加的实体、清空 `cards_inst`/`card_entities` 并返回 `false`。成功创建后：

```gdscript
var root_card := starting_deck.get_root_card()
_encounter_combat_flow = EncounterCombatFlowCoordinator.new(_create_combat_service_for_root(root_card))
```

初始化失败时在 `_ready()` 中 `call_deferred("run_initialization_failed.emit", reason)` 并直接返回，使 `Main` 有机会移除整个半初始化节点；不要继续初始化事件、居中或连接交互。

将协调器改成：

```gdscript
var _encounter_resolver := EncounterEventResolver.new()
var _combat_service: CombatService2

func _init(combat_service: CombatService2 = null) -> void:
    _combat_service = combat_service if combat_service != null else CombatService2.new()

func resolve(player_stats: CombatStats, card_chain: Array[CardInstance], monster: MobInstance) -> CombatResult:
    if monster == null: return null
    return _combat_service.resolve_encounter(player_stats, card_chain, monster)
```

删除 `combat_service_router.gd` 与所有引用。保持原 `player_data` 属性名称，使商店和宝藏现有代码继续读取运行时副本，不改变它们的 API。

- [ ] **Step 4: 运行新旧战斗路由测试**

Run:
```powershell
& $godot --headless --path . --script tests\game_manager_run_setup_test.gd
& $godot --headless --path . --script tests\game_manager_combat_routing_test.gd
& $godot --headless --path . --script tests\combatv2_service_test.gd
```
Expected: PASS；预设固定创建卡牌、不重复根牌、基础 `PlayerData` 与嵌套战斗数据未被复用；战斗胜利、撤退、失败的现有路由测试保持通过。

- [ ] **Step 5: 提交单局初始化与 combat router 清理**

```powershell
git add scripts/game_manager.gd scripts/game/event/encounter/encounter_combat_flow_coordinator.gd tests/game_manager_run_setup_test.gd tests/game_manager_combat_routing_test.gd
git rm scripts/game/event/encounter/combat_service_router.gd
git commit -m "refactor: initialize runs from selected root deck"
```

### Task 3: 给真实 CardEntity 添加只读展示模式

**Files:**
- Modify: `scripts/card/card_entity.gd`
- Create: `tests/card_entity_display_mode_test.gd`

**Interfaces:**
- Produces `CardEntity.set_display_only(value: bool) -> void` 和 `CardEntity.is_display_only() -> bool`。
- `RootSelectionScreen` 只能在绑定临时 `CardInstance` 后调用 `set_display_only(true)`；不得设置 `drag_layer`。
- 游戏内的 `CardManager.create_card_entity()` 不调用该方法，因此默认拖拽、旋转、放大和 hover 行为不变。

- [ ] **Step 1: 写失败的展示模式测试**

```gdscript
var card := CardEntityScene.instantiate() as CardEntity
card.bind_instance(CardInstance.new(RevivalDeck.get_root_card()))
root.add_child(card)
await process_frame
card.set_display_only(true)
_expect(card.is_display_only(), "card records display-only mode")
_expect(not card.input_pickable, "preview Area2D cannot receive input")
_expect(card.state == CardEntity.State.NORMAL, "preview leaves transient interaction state")
card._on_mouse_entered()
_expect(card.state == CardEntity.State.NORMAL, "preview ignores hover")
card._on_input_event(root, InputEventMouseButton.new(), 0)
_expect(not card._dragging, "preview cannot start dragging")
card._show_zoom()
_expect(card._zoom_overlay == null, "preview cannot open zoom overlay")
```

- [ ] **Step 2: 运行失败测试**

Run: `& $godot --headless --path . --script tests\card_entity_display_mode_test.gd`

Expected: FAIL，提示 `set_display_only` / `is_display_only` 不存在或预览仍接受输入。

- [ ] **Step 3: 实现展示模式且不回归游戏内交互**

在 `CardEntity` 增加 `_display_only := false`，并实现：

```gdscript
func set_display_only(value: bool) -> void:
    _display_only = value
    input_pickable = not value
    if value:
        cancel_drag()
        _show_info(false)
        if state == State.ZOOMED: _hide_zoom()
        state = State.NORMAL

func is_display_only() -> bool:
    return _display_only
```

在 `_ready()` 中使用 `input_pickable = not _display_only`，并在 `_on_mouse_entered()`、`_on_mouse_exited()`、`_on_input_event()`、`_start_drag()`、`_rotate_card()`、`_show_zoom()` 开头对 `_display_only` 立即 `return`。不要改动 `bind_instance()` 的渲染路径，不要修改 `LayoutConfig` 的 1:2 卡面布局。

- [ ] **Step 4: 运行展示和既有卡牌交互测试**

Run:
```powershell
& $godot --headless --path . --script tests\card_entity_display_mode_test.gd
& $godot --headless --path . --script tests\card_zoom_overlay_test.gd
& $godot --headless --path . --script tests\board_direction_test.gd
```
Expected: PASS；展示卡无输入路径，正常游戏卡依旧可放大、拖拽并遵守棋盘朝向放置规则。

- [ ] **Step 5: 提交只读预览能力**

```powershell
git add scripts/card/card_entity.gd tests/card_entity_display_mode_test.gd
git commit -m "feat: add display-only card previews"
```

### Task 4: 构建标准主菜单场景

**Files:**
- Create: `scenes/home/main_menu_screen.tscn`
- Create: `scripts/home/main_menu_screen.gd`
- Extend: `tests/home_screen_flow_test.gd`

**Interfaces:**
- Produces signal `MainMenuScreen.start_game_requested`。
- 节点路径固定为 `SafeArea/Layout/LogoBlock/GameLogo`、`SafeArea/Layout/ActionBlock/StartGameButton`、`SafeArea/Layout/FooterBlock/VersionLabel`。
- Later `Main` only connects `start_game_requested` and never accesses the button as part of game setup.

- [ ] **Step 1: 写失败的主菜单结构和单次信号测试**

```gdscript
var menu := MainMenuScene.instantiate() as Control
root.add_child(menu)
await process_frame
var logo := menu.get_node_or_null("SafeArea/Layout/LogoBlock/GameLogo") as Label
var start := menu.get_node_or_null("SafeArea/Layout/ActionBlock/StartGameButton") as Button
var version := menu.get_node_or_null("SafeArea/Layout/FooterBlock/VersionLabel") as Label
_expect(logo != null and logo.text == "MONOCARD", "menu exposes top logo")
_expect(start != null and start.text == "开始游戏", "menu exposes the only action")
_expect(version != null and not version.text.is_empty(), "menu exposes version footer")
var calls := 0
menu.start_game_requested.connect(func(): calls += 1)
start.emit_signal("pressed"); start.emit_signal("pressed")
_expect(calls == 1 and start.disabled, "start request is emitted once and disables button")
```

- [ ] **Step 2: 运行失败测试**

Run: `& $godot --headless --path . --script tests\home_screen_flow_test.gd`

Expected: FAIL，菜单场景或稳定节点路径不存在。

- [ ] **Step 3: 创建菜单场景与一次性脚本**

创建全屏 `Control` 场景，以 `MarginContainer` 的 `SafeArea` 提供统一边距，在其下建立名为 `Layout` 的 `Control`；三个区块使用锚点分别定位顶端、中心和底端。只添加以下可点击节点：`StartGameButton`。脚本为：

```gdscript
class_name MainMenuScreen
extends Control

signal start_game_requested

@onready var _start_game_button: Button = $SafeArea/Layout/ActionBlock/StartGameButton
var _transition_requested := false

func _ready() -> void:
    _start_game_button.pressed.connect(_on_start_game_pressed)
    _start_game_button.grab_focus()

func _on_start_game_pressed() -> void:
    if _transition_requested: return
    _transition_requested = true
    _start_game_button.disabled = true
    start_game_requested.emit()
```

给 `GameLogo` 设置 `MONOCARD`，给按钮设置 `开始游戏`，给底部 `VersionLabel` 设置 `v0.1.0`。不要添加未实现的继续、设置、退出或图鉴入口。

- [ ] **Step 4: 运行菜单测试**

Run: `& $godot --headless --path . --script tests\home_screen_flow_test.gd`

Expected: 主菜单部分 PASS；场景可实例化、节点存在、两次按下只发一个信号。

- [ ] **Step 5: 提交主菜单**

```powershell
git add scenes/home/main_menu_screen.tscn scripts/home/main_menu_screen.gd tests/home_screen_flow_test.gd
git commit -m "feat: add main menu screen"
```

### Task 5: 构建可校验、可预览、可响应式布局的牌根选择页

**Files:**
- Create: `scenes/home/root_option_entry.tscn`
- Create: `scripts/home/root_option_entry.gd`
- Create: `scenes/home/root_selection_screen.tscn`
- Create: `scripts/home/root_selection_screen.gd`
- Modify: `tests/home_screen_flow_test.gd`

**Interfaces:**
- Produces `RootSelectionScreen.configure(presets: Array[StartingDeckData]) -> void`、`back_requested`、`exploration_requested(preset: StartingDeckData)`。
- Produces `RootOptionEntry.configure(preset, validation_error)`、`set_selected(value)`、`pressed(entry)`。
- `configure()` 在 `_ready()` 前后均可调用；预设变更后清理并重建所有临时预览节点。

- [ ] **Step 1: 扩展失败测试，覆盖选择、锁定、坏配置、重复根牌和只读预览**

```gdscript
var screen := RootSelectionScene.instantiate() as RootSelectionScreen
screen.configure([RevivalDeck, LockedDeck, DuplicateRootDeck, InvalidDeck])
root.add_child(screen)
await process_frame
_expect(screen.get_node("RootOptionList").get_child_count() == 2, "valid unlocked and locked presets are visible; invalid/duplicate entries are suppressed")
_expect(screen.selected_preset == RevivalDeck, "first valid unlocked preset is selected")
var previews := screen.get_node("RootPreviewSlot").get_children()
_expect(previews.size() == 1 and previews[0].is_display_only(), "root preview uses display-only CardEntity")
screen._on_root_option_pressed(screen._entry_for_preset(LockedDeck))
_expect(screen.selected_preset == RevivalDeck, "locked option cannot replace valid selection")
_expect(not screen.get_node("UnlockHintLabel").text.is_empty(), "locked option shows a hint")
var requests := 0
screen.exploration_requested.connect(func(_preset): requests += 1)
screen.get_node("StartExplorationButton").emit_signal("pressed")
screen.get_node("StartExplorationButton").emit_signal("pressed")
_expect(requests == 1 and screen.get_node("StartExplorationButton").disabled, "exploration request is emitted once")
```

在同一测试中把根选择场景放入 1920×1080 和 900×1200 `SubViewport`：前者断言 `MainArea.vertical == false`，后者断言 `MainArea.vertical == true` 且 `SafeArea` 可纵向滚动。

- [ ] **Step 2: 运行失败测试**

Run: `& $godot --headless --path . --script tests\home_screen_flow_test.gd`

Expected: FAIL，根选择场景、条目脚本和根牌筛选接口不存在。

- [ ] **Step 3: 实现条目、选择页及预览清理**

`RootOptionEntry` 用一个 `Button` 承载名称、标签和状态；它对无效项不发信号，对锁定项仍发 `pressed(self)` 以便父页显示提示。其核心接口：

```gdscript
signal pressed(entry: RootOptionEntry)
var preset: StartingDeckData
var is_locked := false

func configure(value: StartingDeckData, validation_error := "") -> void:
    preset = value
    is_locked = value != null and not value.is_unlocked
    $Button.text = value.get_root_card().card_name if validation_error.is_empty() else "配置无效"
    $Button.disabled = not validation_error.is_empty()

func set_selected(value: bool) -> void:
    $Button.button_pressed = value
```

`RootSelectionScreen` 使用两个 `Array[StartingDeckData]` 保存全部输入和可见项，在 `configure()` 中把输入复制到 `_configured_presets`。对每个资源调用 `validate()`；对有效且已解锁的项以 `get_root_card().card_id` 建立集合，若根牌 ID 已存在，则对重复项 `push_error("Duplicate root card_id: %s" % root.card_id)` 且不显示。锁定但资源有效的项显示且不可替换当前有效选择。公开选择状态：

```gdscript
var selected_preset: StartingDeckData

func _refresh_previews() -> void:
    for child in $RootPreviewSlot.get_children(): child.queue_free()
    for child in $RemainingStarterCardPreviewRow.get_children(): child.queue_free()
    if selected_preset == null: return
    _add_preview($RootPreviewSlot, selected_preset.get_root_card())
    for card_data in selected_preset.get_remaining_starter_cards():
        _add_preview($RemainingStarterCardPreviewRow, card_data)

func _add_preview(parent: Node, card_data: CardData) -> void:
    var card := CardEntityScene.instantiate() as CardEntity
    card.bind_instance(CardInstance.new(card_data))
    card.set_display_only(true)
    parent.add_child(card)
```

场景节点必须包含 `BackButton`、`RootOptionList`、`RootPreviewSlot`、`RemainingStarterCardPreviewRow`、`UnlockHintLabel`、`StartExplorationButton`。使用 `BoxContainer` 作为 `MainArea`，在 `get_viewport().size_changed` 时执行 `MainArea.vertical = size.x < 980`；`Content` 最大宽度为 1500；窄屏时将 `SafeArea` 放进唯一的 `ScrollContainer`，不为左右栏另建滚动区域。

- [ ] **Step 4: 运行根选择行为与响应式测试**

Run:
```powershell
& $godot --headless --path . --script tests\home_screen_flow_test.gd
& $godot --headless --path . --script tests\responsive_layout_scene_test.gd
```
Expected: PASS；有效根默认选中，锁定根只提示不切换，坏/重复根不以正常选项出现，卡面预览只读，窄屏切换为纵向布局。

- [ ] **Step 5: 提交根选择页**

```powershell
git add scenes/home scripts/home tests/home_screen_flow_test.gd
git commit -m "feat: add root selection screen"
```

### Task 6: 将三个页面接入 Main 路由并保护失败开局

**Files:**
- Modify: `scenes/main.tscn`
- Modify: `scripts/main.gd`
- Modify: `tests/home_screen_flow_test.gd`

**Interfaces:**
- Consumes `MainMenuScreen.start_game_requested`、`RootSelectionScreen.back_requested`、`RootSelectionScreen.exploration_requested(preset)`、`GameManager.configure_run()`、`GameManager.run_initialization_failed`、`GameManager.run_finished`。
- `Main` 保留 `BackgroundLayer`，新增 `ScreenLayer: CanvasLayer`（layer 0），移除静态 `GameManager` 实例。
- Produces纯路由函数 `_show_main_menu()`、`_show_root_selection()`、`_start_exploration(preset)`；任意时刻只有 `_active_screen` 或 `_active_game` 之一非空。

- [ ] **Step 1: 扩展失败集成测试，覆盖完整页面路由和资源隔离**

```gdscript
var main := MainScene.instantiate()
root.add_child(main)
await process_frame
var menu := main.get_node_or_null("ScreenLayer/MainMenuScreen") as MainMenuScreen
_expect(menu != null, "boot shows main menu")
menu.get_node("SafeArea/Layout/ActionBlock/StartGameButton").emit_signal("pressed")
await process_frame
var selector := main.get_node_or_null("ScreenLayer/RootSelectionScreen") as RootSelectionScreen
_expect(selector != null, "start opens selector")
_expect(main.get_node_or_null("GameManager") == null, "selector does not create game manager")
selector.get_node("StartExplorationButton").emit_signal("pressed")
await process_frame
var run_one := main.get_node_or_null("GameManager") as Node
_expect(run_one != null and run_one.starting_deck == RevivalDeck, "exploration injects selected preset")
_expect(main.get_node_or_null("ScreenLayer/RootSelectionScreen") == null, "selector is destroyed on run start")
var first_card := run_one.cards_inst[0]
run_one.queue_free(); await process_frame
main._show_root_selection(); await process_frame
(main.get_node("ScreenLayer/RootSelectionScreen") as RootSelectionScreen).get_node("StartExplorationButton").emit_signal("pressed")
await process_frame
var run_two := main.get_node("GameManager")
_expect(run_two.cards_inst[0] != first_card, "same deck starts with fresh card instances")
```

另加返回测试：选择页 `BackButton` 按下后只重新出现主菜单；树中没有 `GameManager`。

- [ ] **Step 2: 运行失败集成测试**

Run: `& $godot --headless --path . --script tests\home_screen_flow_test.gd`

Expected: FAIL，启动仍有静态 `GameManager`，或 `Main` 不存在页面路由方法。

- [ ] **Step 3: 修改 Main 场景和实现路由**

从 `main.tscn` 删除静态 `GameManager` 节点。保留 `BackgroundLayer/BackgroundFill`，新增：

```text
Main
├── BackgroundLayer (CanvasLayer, layer = -10)
│   └── BackgroundFill (ColorRect, Full Rect, mouse_filter = Ignore)
└── ScreenLayer (CanvasLayer, layer = 0)
```

为 `Main` 导出 `starting_decks: Array[StartingDeckData]`，默认填入 `revival_starting_deck.tres`。脚本按以下模式实现：

```gdscript
var _active_screen: Control
var _active_game: GameManager

func _ready() -> void:
    DisplayServer.window_set_min_size(LayoutConfig.MIN_WINDOW_SIZE)
    _fit_background_to_viewport()
    get_viewport().size_changed.connect(_fit_background_to_viewport)
    _show_main_menu()

func _show_main_menu() -> void:
    _clear_active_content()
    var menu := MainMenuScene.instantiate() as MainMenuScreen
    $ScreenLayer.add_child(menu)
    _active_screen = menu
    menu.start_game_requested.connect(_show_root_selection)

func _show_root_selection() -> void:
    _clear_active_content()
    var screen := RootSelectionScene.instantiate() as RootSelectionScreen
    screen.configure(starting_decks)
    $ScreenLayer.add_child(screen)
    _active_screen = screen
    screen.back_requested.connect(_show_main_menu)
    screen.exploration_requested.connect(_start_exploration)

func _start_exploration(preset: StartingDeckData) -> void:
    if preset == null or not preset.is_unlocked or not preset.validate().is_empty():
        push_error("Main rejected invalid exploration preset")
        _show_main_menu()
        return
    _clear_active_content()
    var game := GameManagerScene.instantiate() as GameManager
    if not game.configure_run(preset):
        game.free(); _show_main_menu(); return
    game.run_initialization_failed.connect(_on_run_initialization_failed.bind(game))
    game.run_finished.connect(_show_main_menu)
    add_child(game)
    _active_game = game
```

`_clear_active_content()` 必须先对 `_active_screen` 调用 `queue_free()` 并置空；若 `_active_game` 有效则 `queue_free()` 并置空。`_on_run_initialization_failed(reason, game)` 只在 `game == _active_game` 时 `push_error(reason)`、释放该局并返回主菜单。背景填充函数继续使用全屏 anchors，绝不把背景挂进或缩放为 `GameplayCanvas` 的子节点。

- [ ] **Step 4: 运行全流程和布局测试**

Run:
```powershell
& $godot --headless --path . --script tests\home_screen_flow_test.gd
& $godot --headless --path . --script tests\layout_config_test.gd
& $godot --headless --path . --script tests\gameplay_canvas_test.gd
```
Expected: PASS；启动先到菜单，开始游戏只到牌根选择，开始探索后才创建一个已配置 `GameManager`，背景/玩法画布现有缩放断言不变。

- [ ] **Step 5: 提交入口路由**

```powershell
git add scenes/main.tscn scripts/main.gd tests/home_screen_flow_test.gd
git commit -m "feat: route menu root selection and exploration"
```

### Task 7: 完整回归、编辑器加载与验收记录

**Files:**
- Modify: `docs/superpowers/specs/2026-08-02-home-screen-design.md`（仅将状态从“等待文档复核”改为“已实现并已验证”，不改已确认规则）
- Optionally modify: `tests/home_screen_flow_test.gd`（仅当下面任一验收项无自动化断言时补齐）

**Interfaces:**
- 不引入新的运行时接口；本任务验证 Tasks 1–6 的公开接口与既有事件/战斗 API 共存。

- [ ] **Step 1: 执行所有独立 headless 测试**

```powershell
$godot = 'D:\InstallPath\godot\Godot_v4.7-stable_win64_console.exe'
Get-ChildItem tests -Filter '*_test.gd' | Sort-Object Name | ForEach-Object {
  Write-Host "=== $($_.Name) ==="
  & $godot --headless --path . --script $_.FullName
  if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}
```

Expected: 每个既有和新增测试以 exit code 0 结束；特别确认 `event_runtime_test.gd`、`event_trigger_test.gd`、`event_ui_scene_test.gd`、`combat_event_ui_scene_test.gd`、`combatv2_*`、`game_manager_combat_routing_test.gd`、`layout_config_test.gd` 都通过。

- [ ] **Step 2: 执行 Godot 编辑器资源加载检查**

```powershell
& $godot --editor --path . --quit
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
```

Expected: exit code 0，控制台没有 `Parse Error`、丢失脚本类、丢失预设资源、失效场景路径或 `CombatServiceRouter` 残留加载错误。

- [ ] **Step 3: 人工验收三段流程和窗口适配**

按此顺序手动启动项目：启动后观察顶部 `MONOCARD`、中部唯一的 `开始游戏`、底部版本号；点击开始游戏，确认棋盘尚未创建；在牌根页确认根牌大预览、其余起始卡、完整数量、说明和标签；点击开始探索，确认手牌正好来自预设且只有一张根牌。随后分别用 1920×1080、超宽窗口和小于 980px 宽度窗口检查：背景始终填满真实窗口、超宽内容保持最大宽度、窄屏选择页转为上下布局并可纵向滚动。

Expected: 所有操作与已确认规格逐项一致；预览卡不能拖拽、右键放大或弹出 hover 信息；探索内卡牌仍可正常拖拽和放大。

- [ ] **Step 4: 更新规格状态并提交验收记录**

```powershell
git add docs/superpowers/specs/2026-08-02-home-screen-design.md tests/home_screen_flow_test.gd
git commit -m "docs: verify home screen flow acceptance"
```

## Self-Review

- **规格覆盖：** Task 1 覆盖完整起始牌组、唯一根牌、静态资源不变和初始实例独立；Task 2 覆盖运行时玩家副本、根牌决定战斗服务与 router 删除；Task 3 覆盖真实卡面只读预览；Task 4 覆盖标准入口页；Task 5 覆盖根选择、锁定/坏配置、重复根、双栏/窄屏；Task 6 覆盖 Main 页面生命周期、失败保护和一局创建；Task 7 覆盖回归、编辑器加载和人工窗口检查。
- **占位符扫描：** 本计划没有未落实的占位符或未定义的“适当处理”步骤；所有新增公共方法、信号和稳定节点路径均在所属任务定义。
- **类型一致性：** 全流程固定使用 `StartingDeckData` → `GameManager.configure_run(preset)`；选择页发射的 `exploration_requested(preset)` 与 Main 接收类型一致；协调器依赖 `CombatService2`，不再经由 router；预览统一调用 `CardEntity.set_display_only(true)`。

