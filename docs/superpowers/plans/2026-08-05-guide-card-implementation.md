# 引导牌玩法 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 新增 `GUIDE` 卡牌类型，并让引导牌按普通卡牌规则放置后推动现有牌链前移、继承目标位置朝向、通过 `Board` 信号回到手牌区。

**Architecture:** 保留唯一的 `Board.add_card(card: CardEntity) -> bool` 放牌入口。`Board` 负责通用合法性校验、牌链快照迁移和格子占用表重建；引导牌不进入 `Board.cards`，成功迁移后发出 `card_return_requested(card)`。`GameManager` 连接该信号并调用 `HandArea.add_card(card)`，`DragLayer` 不增加 GUIDE 专用分支。

**Tech Stack:** Godot 4.7、GDScript、现有 SceneTree headless 测试脚本、Git worktree。

## Global Constraints

- 新类型名称必须是 `CardData.CardType.GUIDE`。
- 本次不修改起始牌组、抽牌、商店、奖励或任何牌组配置。
- 不新增公开的 `add_guide_card()` 放牌接口；继续使用 `Board.add_card(card: CardEntity) -> bool`。
- `Board` 不直接依赖 `HandArea`；通过 `card_return_requested(card: CardEntity)` 通知外层。
- 引导牌成功后不进入 `Board.cards`，现有牌链数组顺序保持不变。
- 每张牌必须继承其前方目标位置的旧位置和旋转朝向，以确保牌链连接。
- 非法放置不得触发前移或回手信号；继续使用现有 DragLayer 失败回手流程。
- 工作区已有的其他未提交修改不可覆盖；实现只在 `D:\project\MonoCard\mono-card\.worktrees\codex-guide-card` 进行。

---

## File Structure

- `scripts/card/card_data.gd`：扩展卡牌类型枚举。
- `scripts/game/board.gd`：统一放牌入口、引导牌牌链迁移、信号和格子占用重建。
- `scripts/game_manager.gd`：连接 Board 回手信号并把卡牌交给 HandArea。
- `tests/guide_card_test.gd`：引导牌类型、牌链迁移、信号和失败边界测试。
- `docs/superpowers/plans/2026-08-05-guide-card-implementation.md`：本计划文档。

## Test Command

每个测试脚本使用项目现有模式运行：

```powershell
godot --headless --path . --script tests/guide_card_test.gd
```

完整回归使用项目中所有测试脚本逐个运行；若当前环境未将 Godot 加入 PATH，先定位本机 Godot 4.7 可执行文件，并用该绝对路径替换 `godot`。

---

### Task 1: 新增 GUIDE 类型并建立失败测试夹具

**Files:**
- Modify: `scripts/card/card_data.gd:4-4`
- Create: `tests/guide_card_test.gd`

**Interfaces:**
- Consumes: 现有 `CardData`、`CardInstance`、`CardEntity` 和 `Board` 类型。
- Produces: `CardData.CardType.GUIDE`，以及可复用的 `guide_card_test.gd` 测试夹具和 `_make_card(card_type)` 辅助函数。

- [ ] **Step 1: Write the failing test**

在 `tests/guide_card_test.gd` 建立 SceneTree 测试脚本，先写类型断言和一个最小引导牌实体构造器。测试必须在 `CardData` 尚无 `GUIDE` 枚举时失败，而不是只断言字符串：

```gdscript
extends SceneTree

const CardEntityScene := preload("res://scenes/card_view/card_entity.tscn")

var _failure_count := 0

func _init() -> void:
    call_deferred("_run_tests")

func _run_tests() -> void:
    _expect(CardData.CardType.GUIDE != CardData.CardType.NORMAL, "GUIDE must be a distinct CardType")
    var guide := _make_card(CardData.CardType.GUIDE)
    _expect(guide.card_instance.card_data.card_type == CardData.CardType.GUIDE, "guide card keeps GUIDE type")
    guide.queue_free()
    quit(1 if _failure_count > 0 else 0)

func _make_card(card_type: CardData.CardType) -> CardEntity:
    var card := CardEntityScene.instantiate() as CardEntity
    var data := CardData.new()
    data.card_type = card_type
    data.card_name = "Test Card"
    card.bind_instance(CardInstance.new(data))
    root.add_child(card)
    return card

func _expect(condition: bool, message: String) -> void:
    if not condition:
        _failure_count += 1
        push_error(message)
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```powershell
godot --headless --path . --script tests/guide_card_test.gd
```

Expected: FAIL while parsing/evaluating `CardData.CardType.GUIDE`, proving the test exercises the missing enum rather than passing vacuously.

- [ ] **Step 3: Write minimal implementation**

在 `scripts/card/card_data.gd` 将枚举从：

```gdscript
enum CardType { ROOT, NORMAL }
```

改为：

```gdscript
enum CardType { ROOT, NORMAL, GUIDE }
```

不要修改任何 `.tres` 牌组资源。

- [ ] **Step 4: Run test to verify it passes**

重新运行同一命令，预期输出为退出码 0，且没有 `GUIDE` 类型断言失败。

- [ ] **Step 5: Commit**

```powershell
git add scripts/card/card_data.gd tests/guide_card_test.gd
git commit -m "feat: add guide card type"
```

---

### Task 2: 在 Board.add_card 中实现牌链前移和回手信号

**Files:**
- Modify: `scripts/game/board.gd:4-5,479-517`
- Modify: `tests/guide_card_test.gd`

**Interfaces:**
- Consumes: `CardData.CardType.GUIDE`，现有 `Board.add_card(card: CardEntity) -> bool`、`get_card_cells()`、`snap_card_position()`、`_grid_owner`。
- Produces: `signal card_return_requested(card: CardEntity)`；引导牌通过 `Board.add_card()` 完成校验与前移，不出现在 `Board.cards`。

- [ ] **Step 1: Write the failing tests**

扩展测试脚本，使用真实的 `Board` 与 `CardEntity` 场景建立一条至少两张卡的牌链。通过 `board.add_card()` 放置 ROOT 起点，再根据 `board.get_placement_cell(board.cards.back())` 计算下一张卡的合法位置。测试至少覆盖：

```gdscript
func _test_guide_advances_chain_and_preserves_target_pose() -> void:
    var board := BoardScene.instantiate() as Board
    root.add_child(board)

    var first := _make_card(CardData.CardType.ROOT)
    first.position = Vector2(156, 260)
    _expect(board.add_card(first), "root card can start chain")
    var second := _make_card(CardData.CardType.NORMAL)
    second.position = board.grid_to_world_center(board.get_placement_cell(first))
    _expect(board.add_card(second), "normal card can extend chain")

    var first_position := first.global_position
    var first_rotation := first.rotation_degrees
    var second_position := second.global_position
    var second_rotation := second.rotation_degrees

    var guide := _make_card(CardData.CardType.GUIDE)
    guide.position = board.grid_to_world_center(board.get_placement_cell(second))
    guide.rotation_degrees = 90.0
    guide.card_instance.direction = 1
    var returned: Array[CardEntity] = []
    board.card_return_requested.connect(func(card: CardEntity): returned.append(card))

    _expect(board.add_card(guide), "guide card uses normal placement validation")
    _expect(board.cards == [first, second], "guide card is not added to board chain")
    _expect(returned.size() == 1 and returned[0] == guide, "guide requests return exactly once")
    _expect(second.global_position == guide.global_position, "tail inherits guide position")
    _expect(is_equal_approx(second.rotation_degrees, guide.rotation_degrees), "tail inherits guide rotation")
    _expect(first.global_position == second_position, "first card moves to second old position")
    _expect(is_equal_approx(first.rotation_degrees, second_rotation), "first card inherits second old rotation")
    _expect(board.get_card_cells(first.global_position, first.rotation_degrees).all(func(cell): return board._grid_owner.get(cell) == first), "first occupancy is rebuilt")

    board.queue_free()
```

Also add tests for a single-card chain, an empty board, and an invalid occupied target. For each invalid case assert `board.cards`, card transforms, `_grid_owner`, and signal count remain unchanged.

Because the project tests are SceneTree scripts rather than a unit-test framework, keep assertions in `_expect()` and run all subtests from `_run_tests()` before `quit()`.

- [ ] **Step 2: Run test to verify it fails**

Run:

```powershell
godot --headless --path . --script tests/guide_card_test.gd
```

Expected: FAIL because `Board` has no `card_return_requested` signal and currently adds every valid card to `Board.cards` without moving the chain.

- [ ] **Step 3: Write minimal implementation**

在 `scripts/game/board.gd`：

1. 在现有 `event_triggered` 信号附近新增：

```gdscript
signal card_return_requested(card: CardEntity)
```

2. 在 `add_card()` 完成边界、相邻、冲突校验和吸附后，先判断 GUIDE 类型。
3. 对 GUIDE 牌保存目标位置/旋转，并复制当前 `cards` 的 `global_position`、`rotation_degrees` 和 `card_instance.direction` 快照。
4. 将旧链按从尾到头的映射写回：
   - `cards[i]` 接收旧快照 `i + 1`；
   - 最后一张卡接收引导牌的目标快照。
5. 通过一个内部辅助函数清空并按最终卡牌状态重建 `_grid_owner`。该函数只处理现有 `cards`，不能把 GUIDE 写入占用表。
6. 将 GUIDE 的 `set_on_board(false)`、父节点和 z-index 状态保持为待回手状态，清理预览，并发出 `card_return_requested`。
7. 保持普通牌原有的 `reparent(self)`、`set_on_board(true)`、`cards.append(card)`、事件触发和返回值行为。

位置/旋转写回必须同步 `card.card_instance.direction`，方向值使用与现有旋转逻辑一致的：

```gdscript
card.card_instance.direction = _get_rotation_direction(card.rotation_degrees)
```

不要通过逐张 `remove_card()` / `add_card()` 实现迁移，因为那会破坏 `Board.cards` 顺序并触发中间态冲突。

- [ ] **Step 4: Run test to verify it passes**

重新运行 `tests/guide_card_test.gd`，预期所有前移、朝向、占用表和失败边界断言通过。

- [ ] **Step 5: Commit**

```powershell
git add scripts/game/board.gd tests/guide_card_test.gd
git commit -m "feat: advance board chain with guide cards"
```

---

### Task 3: 接入 GameManager 回手信号并验证拖拽路径

**Files:**
- Modify: `scripts/game_manager.gd:63-80`
- Modify: `tests/guide_card_test.gd`
- Optionally modify: `scripts/game/drag_layer.gd` only if the implementation exposes a lock/recovery hook required by the existing interaction flow; do not add GUIDE-specific placement branching there.

**Interfaces:**
- Consumes: `Board.card_return_requested(card: CardEntity)` and `HandArea.add_card(card: CardEntity, animate: bool = true) -> bool`.
- Produces: `GameManager._on_board_card_return_requested(card: CardEntity) -> void` and a scene-ready signal connection.

- [ ] **Step 1: Write the failing test**

在测试脚本中创建一个最小 `GameManager` 测试替身或直接使用现有 GameManager 场景连接的真实 `HandArea`，验证收到信号后：

```gdscript
func _on_card_return_requested(card: CardEntity) -> void:
    _returned_cards.append(card)
```

测试应验证 GameManager 的回调调用 `hand_area.add_card(card)`，并且引导牌最终存在于手牌数组、不存在于棋盘数组。不要测试私有连接实现细节；测试真实的 `Board -> GameManager callback -> HandArea` 行为。

同时保留/补充一个 DragLayer 行为断言：`on_card_drag_end()` 只调用 `board.add_card()` 后返回，不添加 `card_type == GUIDE` 的第二个分支，避免信号回收后重复加入手牌。

- [ ] **Step 2: Run test to verify it fails**

Run:

```powershell
godot --headless --path . --script tests/guide_card_test.gd
```

Expected: FAIL because GameManager 尚未连接 `Board.card_return_requested`，引导牌只会从 DragLayer 脱离而不会被加入 `HandArea.cards`。

- [ ] **Step 3: Write minimal implementation**

在 `GameManager._ready()` 的 Board 信号连接区域加入：

```gdscript
if not board.card_return_requested.is_connected(_on_board_card_return_requested):
    board.card_return_requested.connect(_on_board_card_return_requested)
```

新增回调：

```gdscript
func _on_board_card_return_requested(card: CardEntity) -> void:
    if card == null or not is_instance_valid(card):
        return
    if not hand_area.add_card(card):
        push_error("Failed to return guide card to hand")
```

回调不修改牌组数据，不直接操作 `board.cards`，也不重置现有普通牌的方向。

如果 `Board` 发信号时卡牌仍是 DragLayer 的子节点，`HandArea.add_card()` 负责将其重新 parent 到手牌区并触发现有手牌排列逻辑。

- [ ] **Step 4: Run focused and regression tests**

先运行：

```powershell
godot --headless --path . --script tests/guide_card_test.gd
godot --headless --path . --script tests/board_direction_test.gd
godot --headless --path . --script tests/game_manager_run_setup_test.gd
```

预期三个脚本均退出码 0。再逐个运行 `tests/` 下所有 `*_test.gd`，确认没有普通放置、战斗链、事件触发或手牌布局回归。

- [ ] **Step 5: Commit**

```powershell
git add scripts/game_manager.gd tests/guide_card_test.gd
git commit -m "feat: return guide cards through game manager"
```

---

### Task 4: 最终验证与变更审查

**Files:**
- Inspect: `scripts/card/card_data.gd`
- Inspect: `scripts/game/board.gd`
- Inspect: `scripts/game_manager.gd`
- Inspect: `scripts/game/drag_layer.gd`
- Inspect: `tests/guide_card_test.gd`

**Interfaces:**
- Consumes: Tasks 1-3 的已提交实现。
- Produces: 干净的 worktree、通过的测试结果和可审查的最终 diff。

- [ ] **Step 1: Run focused tests again**

```powershell
godot --headless --path . --script tests/guide_card_test.gd
godot --headless --path . --script tests/board_direction_test.gd
```

- [ ] **Step 2: Run the complete test suite**

```powershell
Get-ChildItem tests -Filter '*_test.gd' | ForEach-Object {
    godot --headless --path . --script $_.FullName
    if ($LASTEXITCODE -ne 0) { throw "Test failed: $($_.Name)" }
}
```

Expected: every test script exits with code 0。

- [ ] **Step 3: Inspect the final diff for scope**

```powershell
git diff master...HEAD --stat
git diff master...HEAD --check
git status --short
```

确认 diff 只包含引导牌玩法、对应测试和计划文档，不包含任何起始牌组或其他工作区改动。

- [ ] **Step 4: Commit any only-if-needed cleanup**

如果前面的任务提交后仍有必要的格式修正，只提交明确属于引导牌功能的文件：

```powershell
git add scripts/card/card_data.gd scripts/game/board.gd scripts/game_manager.gd tests/guide_card_test.gd
git commit -m "test: verify guide card integration"
```

如果没有未提交修正，不创建空提交。
