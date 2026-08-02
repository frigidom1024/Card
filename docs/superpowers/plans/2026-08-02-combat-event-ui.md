# 战斗事件 UI 实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 为怪物与 Boss 遭遇提供自动回放战斗步骤日志、展示结果结算、并在确认后才写入胜负与惩罚的模态 UI。

**Architecture:** `CombatEventView` 是 `EventModalLayer` 内的只读 `Control`，消费现有的 `CombatResult` 和 `CombatStep` 快照。它以 0.7 秒为间隔追加步骤日志、更新双方状态，播放结束后显示与 Outcome 对应的结算信息并发出确认信号；`GameManager` 保存待结算数据，并在接到确认信号后继续调用既有 `_apply_combat_result()`。

**Tech Stack:** Godot 4.7、GDScript、`.tscn` 场景、`SceneTree` headless 测试。

## Global Constraints

- UI 只能读取 `CombatResult`、`CombatStep`、`MobInstance`；不得重新计算战斗、直接改 HP、删除卡牌、标记事件完成或执行惩罚。
- 玩家在日志回放与结算确认之前不能拖拽或继续触发事件；这项锁定继续由 `GameManager` 和 `DragLayer` 管理。
- 自动播放间隔固定为 0.7 秒；底部按钮在播放时立即显示一条下一步骤，在播放完成后改为进入结算页。
- 保持单怪物遭遇的假设；不新增多目标、怪物选择或奖励数据模型。
- 使用 `class_name CombatEventView`，通过类名实例化运行时对象；不要添加 `const _Script = preload(...)` 加 `Script.new()` 的模式。
- `combat_resolved` 仅在玩家确认结算、`CombatResult` 已被 `GameManager` 应用后发出。
- 所有新增行为遵循 TDD：先运行新增测试确认失败，再添加最小实现使其通过。
- 不修改或清理当前工作区中与商店、宝藏事件有关的未提交改动。

---

## 文件结构

- Create: `scenes/game/event_combat.tscn` — 全屏战斗模态场景，提供稳定的日志、状态和结算节点。
- Create: `scripts/game/event/encounter/combat_event_view.gd` — 自动日志播放、快进、结算内容和确认信号的纯展示控制器。
- Create: `tests/combat_event_ui_scene_test.gd` — 场景结构与视图回放行为的无头回归测试。
- Modify: `scenes/game/game_manager.tscn` — 把 `CombatEventView` 加入既有 `EventModalLayer`。
- Modify: `scripts/game_manager.gd` — 缓存待确认战斗结果，连接视图信号，在确认时应用结果。
- Modify: `tests/game_manager_combat_routing_test.gd` — 把遭遇路由断言调整为“确认前不结算，确认后结算”。
- Modify: `tests/event_ui_scene_test.gd` — 将战斗模态加入既有事件 UI 场景结构与运行时布局回归测试。

## 运行命令

所有 Godot 测试使用项目已安装的 Godot 控制台程序：

```powershell
$godot = 'D:\InstallPath\godot\Godot_v4.7-stable_win64_console.exe'
& $godot --headless --path . --script tests\combat_event_ui_scene_test.gd
```

### Task 1: 添加战斗 UI 场景契约测试并实现静态模态场景

**Files:**
- Modify: `tests/event_ui_scene_test.gd:3-151`
- Create: `scenes/game/event_combat.tscn`

**Interfaces:**
- Consumes: 现有商店/宝藏模态测试的全屏根节点、`Overlay`、`CenterContainer`、`Panel` 约定。
- Produces: `EventCombat` 场景，提供 `Overlay`、`Panel`、`TitleLabel`、`ProgressLabel`、`PlayerStatsLabel`、`MonsterStatsLabel`、`CombatLog`、`ProgressButton`、`ResultPanel`、`ResultTitleLabel`、`ResultBodyLabel`、`PenaltyList`、`ConfirmButton`。

- [ ] **Step 1: 扩展失败的场景结构测试**

在 `tests/event_ui_scene_test.gd` 加入：

```gdscript
const COMBAT_SCENE_PATH := "res://scenes/game/event_combat.tscn"
const COMBAT_NODE_NAMES := [
    "Overlay", "Panel", "TitleLabel", "ProgressLabel",
    "PlayerStatsLabel", "MonsterStatsLabel", "CombatLog",
    "ProgressButton", "ResultPanel", "ResultTitleLabel",
    "ResultBodyLabel", "PenaltyList", "ConfirmButton",
]

func _test_combat_scene_structure() -> void:
    var scene_root := _instantiate_scene(COMBAT_SCENE_PATH)
    if scene_root == null:
        return
    _expect(scene_root.name == "EventCombat", "combat root is named EventCombat")
    _expect(scene_root.anchors_preset == Control.PRESET_FULL_RECT, "combat root covers the viewport")
    for node_name in COMBAT_NODE_NAMES:
        _expect(scene_root.find_child(node_name, true, false) != null, "combat exposes %s" % node_name)
    scene_root.free()
```

并在 `_run_tests()` 中，在商店与宝藏断言后调用 `_test_combat_scene_structure()` 和 `_assert_runtime_modal_layout(COMBAT_SCENE_PATH, "combat")`。

- [ ] **Step 2: 运行场景测试，确认失败**

Run:

```powershell
$godot = 'D:\InstallPath\godot\Godot_v4.7-stable_win64_console.exe'
& $godot --headless --path . --script tests\event_ui_scene_test.gd
```

Expected: FAIL；`res://scenes/game/event_combat.tscn` 尚不存在，加载断言失败。

- [ ] **Step 3: 创建最小战斗模态场景**

创建 `event_combat.tscn`：根节点为 `Control`，名称为 `EventCombat`，anchors preset 为 `Control.PRESET_FULL_RECT`。场景结构采用现有 `event_shop.tscn` 的 `Overlay → CenterContainer → Panel` 模式：

```text
EventCombat
├── Overlay: ColorRect
└── CenterContainer
    └── Panel: PanelContainer
        └── Content: VBoxContainer
            ├── Header: VBoxContainer
            │   ├── TitleLabel: Label
            │   └── ProgressLabel: Label
            ├── StatusRow: HBoxContainer
            │   ├── PlayerStatsLabel: Label
            │   └── MonsterStatsLabel: Label
            ├── CombatLog: RichTextLabel
            ├── ProgressButton: Button
            └── ResultPanel: VBoxContainer
                ├── ResultTitleLabel: Label
                ├── ResultBodyLabel: Label
                ├── PenaltyList: VBoxContainer
                └── ConfirmButton: Button
```

`Panel` 最小尺寸为 `Vector2(960, 610)`；`Overlay.mouse_filter = Control.MOUSE_FILTER_STOP`；`CombatLog` 启用滚动并获得垂直扩展；`ResultPanel.visible = false`，`ConfirmButton.visible = false`；默认标题为“遭遇战斗”，默认按钮文本为“加速”。

- [ ] **Step 4: 运行场景测试，确认通过**

Run:

```powershell
$godot = 'D:\InstallPath\godot\Godot_v4.7-stable_win64_console.exe'
& $godot --headless --path . --script tests\event_ui_scene_test.gd
```

Expected: PASS，商店、宝藏、战斗三个模态均可实例化并保持居中布局。

- [ ] **Step 5: 提交静态场景与结构测试**

```powershell
git add scenes/game/event_combat.tscn tests/event_ui_scene_test.gd
git commit -m "feat: add combat event modal scene"
```

### Task 2: 以测试驱动实现战斗日志回放与结算展示

**Files:**
- Create: `tests/combat_event_ui_scene_test.gd`
- Create: `scripts/game/event/encounter/combat_event_view.gd`
- Modify: `scenes/game/event_combat.tscn`

**Interfaces:**
- Consumes: `CombatResult`, `CombatStep`, `CombatStats`, `CombatEffect`, `CombatPenalty` 和 `MobInstance` 的运行时快照。
- Produces:

```gdscript
class_name CombatEventView
extends Control

signal settlement_confirmed()

func show_combat(instance: EventInstance, monster: MobInstance, result: CombatResult) -> void
func hide_combat() -> void
```

- [ ] **Step 1: 写入失败的播放与结算测试**

创建 `tests/combat_event_ui_scene_test.gd`。测试脚本 `extends SceneTree`，预加载 `event_combat.tscn`，使用如下真实运行时对象构造结果：

```gdscript
func _stats(hp: int, defense: int = 0) -> CombatStats:
    var value := CombatStats.new()
    value.max_hp = 20
    value.hp = hp
    value.attack = 0
    value.defense = defense
    return value

func _step(kind: CombatStep.Kind, source_name: String, player_hp: int, monster_hp: int) -> CombatStep:
    return CombatStep.new(
        kind,
        source_name,
        [],
        _stats(player_hp + 1),
        _stats(player_hp),
        _stats(monster_hp + 1),
        _stats(monster_hp)
    )

func _result(outcome: CombatResult.Outcome, steps: Array[CombatStep], penalties: Array[CombatPenalty] = []) -> CombatResult:
    return CombatResult.new(outcome, _stats(8, 2), _stats(3, 0), steps, 2, penalties)
```

实现三项测试：

```gdscript
func _test_steps_render_in_order_and_update_after_snapshots() -> void:
    # show_combat with ROOT_CARD("火种") then PLAYER_CARD("短剑").
    # Trigger ProgressButton twice.\n    # Then emit CombatLog.gui_input with a left-button press while one step remains\n    # in a second two-step run; expect the next step to be appended immediately.
    # Expect CombatLog text contains "根牌效果：火种" before "玩家结算：短剑".
    # Expect PlayerStatsLabel text contains "8" and MonsterStatsLabel text contains "3".

func _test_result_panel_stays_hidden_until_all_steps_finish_then_formats_retreat_penalty() -> void:
    # Show RETREAT with one step and CombatPenaltyRemoveTailCard.new().
    # Before ProgressButton press: ResultPanel.visible is false.
    # First press reveals the completed log but not ResultPanel; ProgressButton text is "查看结算".
    # Second press makes ResultPanel.visible true, ResultTitleLabel.text is "撤离",
    # ResultBodyLabel contains "未能击败", PenaltyList contains the penalty description,
    # and ConfirmButton.text is "接受惩罚并继续".

func _test_victory_and_defeat_settlement_copy_and_confirmation_signal() -> void:
    # Verify VICTORY uses "遭遇胜利" / "确认继续" and DEFEAT uses "远征失败" / "确认".
    # Connect settlement_confirmed to increment a local counter.
    # Press ConfirmButton and expect counter == 1; do not assert any model mutation.
```

在每个测试中 `root.add_child(view)`，等待 `process_frame` 后调用 `show_combat`，并使用 `queue_free()` 清理。

- [ ] **Step 2: 运行行为测试，确认失败**

Run:

```powershell
$godot = 'D:\InstallPath\godot\Godot_v4.7-stable_win64_console.exe'
& $godot --headless --path . --script tests\combat_event_ui_scene_test.gd
```

Expected: FAIL；场景没有挂载 `CombatEventView`，`show_combat()` 和 `settlement_confirmed` 不存在。

- [ ] **Step 3: 实现 `CombatEventView` 的展示状态机**

为 `event_combat.tscn` 挂载 `res://scripts/game/event/encounter/combat_event_view.gd`。脚本保存 `_result: CombatResult`、`_monster: MobInstance`、`_next_step_index: int` 和 `_is_settlement_visible: bool`。

实现 `show_combat()`：清空 `CombatLog` 和 `PenaltyList`，显示弹窗和日志区，隐藏 `ResultPanel`/`ConfirmButton`，设置 `TitleLabel.text = "遭遇战斗"`，以第一步的 `player_before` / `monster_before` 初始化状态栏；若 `steps` 为空，直接将 `ProgressButton.text = "查看结算"`。

实现一个子节点 `AutoAdvanceTimer: Timer`，`wait_time = 0.7`、`one_shot = false`。在 `show_combat()` 启动计时器；每次 `timeout` 调用 `_append_next_step()`；全部步骤展示后停止计时器并把 `ProgressButton.text` 改为“查看结算”。

`_append_next_step()` 必须：

```gdscript
var step := _result.steps[_next_step_index]
CombatLog.append_text(_format_step(step) + "\n")
_update_stats(step.player_after, step.monster_after)
_next_step_index += 1
ProgressLabel.text = "%d / %d" % [_next_step_index, _result.steps.size()]
```

`_format_step()` 必须按 `CombatStep.Kind` 生成“根牌效果：<source>”、“玩家结算：<source>”和“<source> 行动”；追加每个有效 `CombatEffect` 的简短文本，格式为“造成 N 点伤害”、“获得 N 点护甲”或“恢复 N 点生命”。

`ProgressButton.pressed` 的行为为：仍有步骤时立刻 `_append_next_step()`；步骤已完毕时调用 `_show_settlement()`。连接 `CombatLog.gui_input`：当收到左键按下的 `InputEventMouseButton` 且尚有步骤时，调用与 `ProgressButton` 相同的推进函数；日志区域点击不得在结算页重复显示结果。

`_show_settlement()` 停止计时器，显示 `ResultPanel` 和 `ConfirmButton`，设置以下内容：

| Outcome | `ResultTitleLabel` | `ResultBodyLabel` | `ConfirmButton` |
| --- | --- | --- | --- |
| `VICTORY` | `遭遇胜利` | `已击败 <monster.data.mob_name>`；追加“本次遭遇已解决” | `确认继续` |
| `RETREAT` | `撤离` | `牌链已结算完毕，但未能击败 <monster.data.mob_name>` | `接受惩罚并继续` |
| `DEFEAT` | `远征失败` | `生命降至 0，探索结束。` | `确认` |

`_populate_penalties()` 为每个有效 penalty 在 `PenaltyList` 创建一个 `Label`，文本为 `penalty.description`。`ConfirmButton.pressed` 仅执行 `settlement_confirmed.emit()`；`hide_combat()` 停止 Timer、隐藏视图并清空保存的引用与索引。

- [ ] **Step 4: 运行视图行为测试，确认通过**

Run:

```powershell
$godot = 'D:\InstallPath\godot\Godot_v4.7-stable_win64_console.exe'
& $godot --headless --path . --script tests\combat_event_ui_scene_test.gd
```

Expected: PASS；日志顺序、状态快照、撤退惩罚、三种结算文案和确认信号全部通过。

- [ ] **Step 5: 提交视图逻辑与行为测试**

```powershell
git add scenes/game/event_combat.tscn scripts/game/event/encounter/combat_event_view.gd scripts/game/event/encounter/combat_event_view.gd.uid tests/combat_event_ui_scene_test.gd
git commit -m "feat: play combat result logs and settlement"
```

### Task 3: 将 CombatEventView 接入 GameManager 的延后结算流程

**Files:**
- Modify: `scenes/game/game_manager.tscn:12-39`
- Modify: `scripts/game_manager.gd:3-48,105-124,247-334`
- Modify: `tests/game_manager_combat_routing_test.gd:14-120`

**Interfaces:**
- Consumes: `CombatEventView.show_combat(instance, monster, result)` 和 `settlement_confirmed`。
- Produces: 只有确认操作后才调用 `_apply_combat_result()` 的遭遇战路由；对外保持 `combat_started`、`combat_resolved`、`exploration_failed` 信号。

- [ ] **Step 1: 将现有路由测试改为失败的“待确认结算”断言**

在 `game_manager_combat_routing_test.gd` 中，对三种遭遇测试统一完成以下改动：

1. 触发战斗后，断言 `manager.get_node("EventModalLayer/CombatEventView").visible` 为真；
2. 在点击确认前，胜利事件仍未 `is_resolved`，撤退没有移除尾卡，战败没有发出 `exploration_failed`，且 `combat_resolved` 的收集数组为空；
3. 使用 helper 把 `ProgressButton` 点击到“查看结算”，再点击一次显示结算，最后点击 `ConfirmButton`；
4. 把原本的胜利解决、撤退移除尾卡、战败锁定和信号断言放到确认之后；
5. 增加以下测试辅助方法：

```gdscript
func _confirm_combat_settlement(manager: Node) -> void:
    var view := manager.get_node("EventModalLayer/CombatEventView") as CombatEventView
    var progress_button := view.find_child("ProgressButton", true, false) as Button
    while progress_button.text != "查看结算":
        progress_button.pressed.emit()
    progress_button.pressed.emit()
    var confirm_button := view.find_child("ConfirmButton", true, false) as Button
    confirm_button.pressed.emit()
```

- [ ] **Step 2: 运行路由测试，确认失败**

Run:

```powershell
$godot = 'D:\InstallPath\godot\Godot_v4.7-stable_win64_console.exe'
& $godot --headless --path . --script tests\game_manager_combat_routing_test.gd
```

Expected: FAIL；`CombatEventView` 尚未存在于 `GameManager` 场景，且当前 `_begin_encounter()` 会立即应用战斗结果。

- [ ] **Step 3: 在场景中实例化战斗 UI 并连接信号**

在 `scenes/game/game_manager.tscn` 添加：

```text
[ext_resource type="PackedScene" path="res://scenes/game/event_combat.tscn" id="12_combat_event"]

[node name="CombatEventView" parent="EventModalLayer" instance=ExtResource("12_combat_event")]
visible = false
```

在 `game_manager.gd` 添加：

```gdscript
@onready var combat_event_view: CombatEventView = $EventModalLayer/CombatEventView
var _pending_combat_instance: EventInstance
var _pending_combat_result: CombatResult
```

并在 `_ready()` 中连接 `combat_event_view.settlement_confirmed` 到 `_on_combat_settlement_confirmed`，使用与商店、宝藏相同的 `is_connected` 防重连接模式。

- [ ] **Step 4: 将立即应用改为缓存、展示、确认后应用**

将 `_begin_encounter()` 的结果处理替换为：

```gdscript
_print_combat_result_detail(result)
_pending_combat_instance = instance
_pending_combat_result = result
combat_event_view.show_combat(instance, monster, result)
```

添加：

```gdscript
func _on_combat_settlement_confirmed() -> void:
    if _pending_combat_instance == null or _pending_combat_result == null:
        return
    var instance := _pending_combat_instance
    var result := _pending_combat_result
    combat_event_view.hide_combat()
    _pending_combat_instance = null
    _pending_combat_result = null
    _apply_combat_result(instance, result)
    combat_resolved.emit(instance, result)
```

保持 `_apply_combat_result()` 的胜利、撤退与战败业务逻辑不变。若 `begin()` 或 `resolve()` 返回 `null`，调用既有 `_finish_encounter()`；不要打开 UI。确认前 `drag_layer` 一直锁定；胜利和撤退由 `_finish_event_interaction()` 解锁，战败继续保持 `_is_exploration_failed` 锁定。

- [ ] **Step 5: 运行路由测试，确认通过**

Run:

```powershell
$godot = 'D:\InstallPath\godot\Godot_v4.7-stable_win64_console.exe'
& $godot --headless --path . --script tests\game_manager_combat_routing_test.gd
```

Expected: PASS；确认前没有任何战斗业务写入，确认后才出现既有胜利、撤退、战败结果与 `combat_resolved` 信号。

- [ ] **Step 6: 提交完整路由接入**

```powershell
git add scenes/game/game_manager.tscn scripts/game_manager.gd tests/game_manager_combat_routing_test.gd
git commit -m "feat: route encounters through combat result view"
```

### Task 4: 执行完整回归与资源解析验证

**Files:**
- Verify: `scenes/game/event_combat.tscn`
- Verify: `scripts/game/event/encounter/combat_event_view.gd`
- Verify: `scripts/game_manager.gd`
- Verify: `tests/combat_event_ui_scene_test.gd`
- Verify: `tests/event_ui_scene_test.gd`
- Verify: `tests/game_manager_combat_routing_test.gd`

**Interfaces:**
- Consumes: 完整的战斗 UI 与延迟结算集成。
- Produces: 可复现的回归通过结果和无 Godot 解析错误的场景资源。

- [ ] **Step 1: 运行战斗 UI 行为测试**

```powershell
$godot = 'D:\InstallPath\godot\Godot_v4.7-stable_win64_console.exe'
& $godot --headless --path . --script tests\combat_event_ui_scene_test.gd
```

Expected: PASS，退出码为 0。

- [ ] **Step 2: 运行事件 UI 场景和战斗路由回归测试**

```powershell
$godot = 'D:\InstallPath\godot\Godot_v4.7-stable_win64_console.exe'
& $godot --headless --path . --script tests\event_ui_scene_test.gd
& $godot --headless --path . --script tests\game_manager_combat_routing_test.gd
```

Expected: 两个命令均 PASS，退出码为 0；商店、宝藏与战斗 UI 互不破坏。

- [ ] **Step 3: 执行 Godot 编辑器解析检查**

```powershell
$godot = 'D:\InstallPath\godot\Godot_v4.7-stable_win64_console.exe'
& $godot --headless --path . --editor --quit
```

Expected: 退出码为 0，输出不包含 `event_combat.tscn`、`combat_event_view.gd`、`game_manager.tscn`、`game_manager.gd` 的解析错误。

- [ ] **Step 4: 检查变更质量与工作树边界**

```powershell
git diff --check
git diff -- scenes/game/event_combat.tscn scenes/game/game_manager.tscn scripts/game/event/encounter/combat_event_view.gd scripts/game_manager.gd tests/combat_event_ui_scene_test.gd tests/event_ui_scene_test.gd tests/game_manager_combat_routing_test.gd
git status --short
```

Expected: `git diff --check` 无输出；战斗 UI 文件改动清晰可审查；当前已有的商店/宝藏未提交文件仍保留且不被回退。

- [ ] **Step 5: 提交验证文档（若本计划尚未提交）**

```powershell
git add docs/superpowers/plans/2026-08-02-combat-event-ui.md
git commit -m "docs: plan combat event ui implementation"
```
