# 卡牌尺寸与牌桌自适应布局实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把写死的卡牌/棋盘尺寸收敛为单一基准 `LayoutConfig.CELL_SIZE`，卡牌尺寸由基准派生，棋盘与手牌按视口居中。

**Architecture:** 新增纯常量类 `LayoutConfig`（`scripts/game/layout_config.gd`）作为全局唯一尺寸来源，并提供三个纯静态函数（卡面矩形、棋盘原点、手牌原点）供运行时与测试共用。`Board`、`CardEntity`、`CardView`、`HandArea` 各自在 `_ready` 时从基准派生自己的尺寸；`GameManager` 在 `_ready` 末尾按视口居中棋盘与手牌。场景 `.tscn` 中的写死尺寸保留作为 Godot 初始默认，运行时被覆盖。

**Tech Stack:** Godot 4.7, GDScript, 现有 `extends SceneTree` 测试脚本模式。

## Global Constraints

- 只处理桌面 16:9；非 16:9 的可见区域变化不在本次范围。
- `LayoutConfig.CELL_SIZE := 86`，`CARD_MARGIN := 6`。
- 卡牌占格规则不变：1×2 格（宽 `CELL_SIZE`，高 `CELL_SIZE*2`）。
- 棋盘网格规格不变：10 列 × 8 行。
- `card_view_rect` 返回以卡牌实体原点（两格中心）居中的矩形，宽 `cell_size - CARD_MARGIN`，高 `cell_size*2 - CARD_MARGIN`。
- 棋盘原点：水平居中于视口，垂直固定在 `BOARD_TOP_MARGIN`（16.0）。手牌原点：水平居中，中心距视口底 `HAND_BOTTOM_MARGIN`（96.0）。
- 运行测试只执行 `tests/layout_config_test.gd`。`tests/combat_service_test.gd` 与 `tests/combat_model_test.gd` 引用已删除的旧 `scripts/combat/*`，加载即失败，属于已知遗留问题，本次不修。
- 不修改与本次布局无关的未提交工作区改动（`scripts/combatv2/`、`scripts/card/card_instance.gd` 等）。
- `scripts/card_slot.tscn` 是未被引用的孤立场景，不在本次范围。

---

### Task 1: `LayoutConfig` 常量与纯布局函数

**Files:**
- Create: `scripts/game/layout_config.gd`
- Create: `tests/layout_config_test.gd`

**Interfaces:**
- Produces: 常量 `CELL_SIZE=86`, `CARD_MARGIN=6`, `CARD_W=80`, `CARD_H=166`, `HAND_SPACING=30`, `HAND_STEP=110`, `BOARD_TOP_MARGIN=16.0`, `HAND_BOTTOM_MARGIN=96.0`；函数 `card_view_rect(cell_size: int) -> Rect2`, `board_origin(view_size: Vector2, grid_cols: int, grid_rows: int, cell_size: int) -> Vector2`, `hand_origin(view_size: Vector2) -> Vector2`。后续任务全部消费这些。

- [ ] **Step 1: 写失败测试**

创建 `tests/layout_config_test.gd`：

```gdscript
extends SceneTree

const LayoutConfigScript = preload("res://scripts/game/layout_config.gd")
const BoardScene = preload("res://scenes/game/board.tscn")
const HandAreaScript = preload("res://scripts/game/hand.gd")

var _failure_count := 0

func _init() -> void:
	_expect(LayoutConfigScript.CELL_SIZE == 86, "CELL_SIZE is 86")
	_expect(LayoutConfigScript.CARD_MARGIN == 6, "CARD_MARGIN is 6")
	_expect(LayoutConfigScript.CARD_W == 80, "CARD_W derives from CELL_SIZE minus margin")
	_expect(LayoutConfigScript.CARD_H == 166, "CARD_H covers two cells minus margin")
	_expect(LayoutConfigScript.HAND_SPACING == 30, "HAND_SPACING derives from CELL_SIZE")
	_expect(LayoutConfigScript.HAND_STEP == 110, "HAND_STEP is card width plus spacing")
	_expect(
		LayoutConfigScript.CARD_H + LayoutConfigScript.CARD_MARGIN == LayoutConfigScript.CELL_SIZE * 2,
		"card height plus margin fills exactly two cells"
	)

	var card_rect := LayoutConfigScript.card_view_rect(86)
	_expect(card_rect.size == Vector2(80, 166), "card view rect size follows cell size")
	_expect(card_rect.position == Vector2(-40, -83), "card view rect is centered on the entity")

	var board_pos := LayoutConfigScript.board_origin(Vector2(1600, 900), 10, 8, 86)
	_expect(board_pos == Vector2(370, 16), "board origin centers the 860x688 grid horizontally")

	var hand_pos := LayoutConfigScript.hand_origin(Vector2(1600, 900))
	_expect(hand_pos == Vector2(800, 804), "hand origin centers and hugs the bottom")

	# 棋盘底与手牌顶不重叠（至少留 10px）
	var board_bottom := board_pos.y + 8 * 86
	var hand_top := hand_pos.y - 86
	_expect(board_bottom + 10 <= hand_top, "board bottom clears the hand top")

	call_deferred("_run_deferred_tests")

func _run_deferred_tests() -> void:
	_finish_tests()

func _finish_tests() -> void:
	quit(1 if _failure_count > 0 else 0)

func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failure_count += 1
		push_error(message)
```

- [ ] **Step 2: 运行确认失败**

Run: `godot --headless -s res://tests/layout_config_test.gd`
Expected: FAIL。`preload("res://scripts/game/layout_config.gd")` 找不到文件，脚本解析失败。

- [ ] **Step 3: 实现 `LayoutConfig`**

创建 `scripts/game/layout_config.gd`：

```gdscript
class_name LayoutConfig
extends RefCounted

## 全局布局唯一尺寸基准（桌面 16:9）。改这一个文件即可调整所有比例。

const CELL_SIZE    := 86
const CARD_MARGIN  := 6
const CARD_W       := CELL_SIZE - CARD_MARGIN
const CARD_H       := CELL_SIZE * 2 - CARD_MARGIN
const HAND_SPACING := int(CELL_SIZE * 0.35)
const HAND_STEP    := CARD_W + HAND_SPACING
const BOARD_TOP_MARGIN    := 16.0
const HAND_BOTTOM_MARGIN  := 96.0


## 卡面在卡牌实体局部坐标下的矩形（以两格中心为原点）
static func card_view_rect(cell_size: int) -> Rect2:
	var w := cell_size - CARD_MARGIN
	var h := cell_size * 2 - CARD_MARGIN
	return Rect2(-w / 2.0, -h / 2.0, w, h)


## 棋盘节点原点：水平居中，垂直方向让出底部手牌区
static func board_origin(
	view_size: Vector2, grid_cols: int, grid_rows: int, cell_size: int
) -> Vector2:
	return Vector2((view_size.x - grid_cols * cell_size) / 2.0, BOARD_TOP_MARGIN)


## 手牌节点原点：水平居中，中心距屏幕底部 HAND_BOTTOM_MARGIN
static func hand_origin(view_size: Vector2) -> Vector2:
	return Vector2(view_size.x / 2.0, view_size.y - HAND_BOTTOM_MARGIN)
```

- [ ] **Step 4: 运行确认通过**

Run: `godot --headless -s res://tests/layout_config_test.gd`
Expected: PASS（无 push_error，退出码 0）。

- [ ] **Step 5: Commit**

```bash
git add scripts/game/layout_config.gd tests/layout_config_test.gd
git commit -m "feat: add layout config single source of card sizes"
```

---

### Task 2: `Board` 默认 `cell_size` 与 DropDetector 尺寸派生

**Files:**
- Modify: `scripts/game/board.gd:4`（`cell_size` 默认值）
- Modify: `scripts/game/board.gd`（新增 `_ready` + 派生 DropDetector）
- Test: `tests/layout_config_test.gd`

**Interfaces:**
- Consumes: `LayoutConfig.CELL_SIZE`。
- Produces: `Board.cell_size` 默认值 86；`Board._ready` 后 `DropDetector/CollisionShape2D` 的 shape 尺寸为 `(width*cell_size, height*cell_size)`、位置为网格中心。`width`/`height` 仍为 10/8。

- [ ] **Step 1: 追加失败测试**

在 `tests/layout_config_test.gd` 的 `_init()` 末尾（`call_deferred` 之前）追加：

```gdscript
	var board := BoardScene.instantiate() as Board
	_expect(board.cell_size == LayoutConfigScript.CELL_SIZE, "board defaults to the configured cell size")
	board.free()
```

在 `_run_deferred_tests()` 中追加 `_test_board_drop_detector()`：

```gdscript
func _test_board_drop_detector() -> void:
	var board := BoardScene.instantiate() as Board
	root.add_child(board)
	var shape_node := board.get_node_or_null("DropDetector/CollisionShape2D") as CollisionShape2D
	var shape := shape_node.shape as RectangleShape2D
	_expect(shape != null and shape.size == Vector2(860, 688), "drop detector matches the resized grid")
	_expect(shape_node.position == Vector2(430, 344), "drop detector centers on the resized grid")
	board.queue_free()
```

并将 `_run_deferred_tests()` 改为调用 `_test_board_drop_detector()` 后再 `_finish_tests()`：

```gdscript
func _run_deferred_tests() -> void:
	_test_board_drop_detector()
	_finish_tests()
```

- [ ] **Step 2: 运行确认失败**

Run: `godot --headless -s res://tests/layout_config_test.gd`
Expected: FAIL。`cell_size` 仍是 80；DropDetector shape 仍是 800×640。

- [ ] **Step 3: 实现**

修改 `scripts/game/board.gd` 第 4 行：

```gdscript
@export var cell_size: int = LayoutConfig.CELL_SIZE
```

在 `scripts/game/board.gd` 中新增（放在 `func _draw()` 之前）：

```gdscript
func _ready() -> void:
	_apply_drop_detector_size()


## DropDetector 碰撞盒跟随 cell_size（当前未被拖拽逻辑调用，仅保持一致）
func _apply_drop_detector_size() -> void:
	var shape_node := get_node_or_null("DropDetector/CollisionShape2D") as CollisionShape2D
	if shape_node == null:
		return
	var grid_size := Vector2(width * cell_size, height * cell_size)
	var shape := RectangleShape2D.new()
	shape.size = grid_size
	shape_node.shape = shape
	shape_node.position = grid_size / 2.0
```

- [ ] **Step 4: 运行确认通过**

Run: `godot --headless -s res://tests/layout_config_test.gd`
Expected: PASS。

- [ ] **Step 5: Commit**

```bash
git add scripts/game/board.gd tests/layout_config_test.gd
git commit -m "feat: derive board cell size and drop detector from layout config"
```

---

### Task 3: `CardEntity` 尺寸派生（碰撞盒 + 卡面矩形）

**Files:**
- Modify: `scripts/card/card_entity.gd`（`_ready` 末尾调用 `_apply_layout()`，新增 `_apply_layout()`）
- Test: `tests/layout_config_test.gd`

**Interfaces:**
- Consumes: `LayoutConfig.CELL_SIZE`, `LayoutConfig.card_view_rect(cell_size) -> Rect2`。
- Produces: `CardEntity._ready` 后 `$CollisionShape2D.shape.size == (86, 172)`；`$CardView` 尺寸 `(80, 166)` 且居中。`_card_view` 为 `@onready` 的 `$CardView`。

- [ ] **Step 1: 追加失败测试**

在 `tests/layout_config_test.gd` 顶部追加 preload：

```gdscript
const CardEntityScene = preload("res://scenes/card_view/card_entity.tscn")
```

在 `_run_deferred_tests()` 中追加 `_test_card_entity_sizing()`：

```gdscript
func _test_card_entity_sizing() -> void:
	var card := CardEntityScene.instantiate() as CardEntity
	root.add_child(card)
	var shape := (card.get_node("CollisionShape2D") as CollisionShape2D).shape as RectangleShape2D
	_expect(shape != null and shape.size == Vector2(86, 172), "card collision box covers two resized cells")
	var card_view := card.get_node("CardView") as Control
	_expect(card_view.size == Vector2(80, 166), "card view derives from the configured cell size")
	card.queue_free()
```

`_run_deferred_tests()` 更新为依次调用 `_test_board_drop_detector()`、`_test_card_entity_sizing()` 后 `_finish_tests()`。

- [ ] **Step 2: 运行确认失败**

Run: `godot --headless -s res://tests/layout_config_test.gd`
Expected: FAIL。碰撞盒仍是 80×160，卡面 74×154。

- [ ] **Step 3: 实现**

修改 `scripts/card/card_entity.gd` 的 `_ready()`（追加 `_apply_layout()` 调用）：

```gdscript
func _ready() -> void:
	input_pickable = true
	if not card_instance:
		card_instance = CardInstance.create_debug_card()
	_card_view.set_value(card_instance)
	_apply_layout()
```

新增（放在 `_ready()` 之后）：

```gdscript
## 卡牌尺寸由 LayoutConfig.CELL_SIZE 派生（碰撞盒 1×2 格，卡面居中）
func _apply_layout() -> void:
	var shape := RectangleShape2D.new()
	shape.size = Vector2(LayoutConfig.CELL_SIZE, LayoutConfig.CELL_SIZE * 2)
	$CollisionShape2D.shape = shape

	var rect := LayoutConfig.card_view_rect(LayoutConfig.CELL_SIZE)
	_card_view.offset_left = rect.position.x
	_card_view.offset_top = rect.position.y
	_card_view.offset_right = rect.position.x + rect.size.x
	_card_view.offset_bottom = rect.position.y + rect.size.y
```

- [ ] **Step 4: 运行确认通过**

Run: `godot --headless -s res://tests/layout_config_test.gd`
Expected: PASS。

- [ ] **Step 5: Commit**

```bash
git add scripts/card/card_entity.gd tests/layout_config_test.gd
git commit -m "feat: derive card entity collision and view size from layout config"
```

---

### Task 4: `CardView` 底部标签栏钉底

**Files:**
- Modify: `scripts/card/card_view.gd`
- Test: `tests/layout_config_test.gd`

**Interfaces:**
- Consumes: 自身 `size`（由 Task 3 的 `CardEntity._apply_layout` 触发变化）。
- Produces: `CardView._ready` 连接 `resized` 信号 → `_pin_label_container()`；`LabelContainer` 高度固定 23，底部对齐 `size.y`。

- [ ] **Step 1: 追加失败测试**

在 `tests/layout_config_test.gd` 顶部追加 preload：

```gdscript
const CardViewScene = preload("res://scenes/card_view/card_view.tscn")
```

在 `_run_deferred_tests()` 中追加 `_test_card_view_label_container()`：

```gdscript
func _test_card_view_label_container() -> void:
	var view := CardViewScene.instantiate() as Control
	root.add_child(view)
	view.size = Vector2(80, 166)
	var label := view.get_node("LabelContainer") as Control
	_expect(label.offset_bottom == 166.0, "label container pins to the resized card bottom")
	_expect(label.offset_top == 143.0, "label container bar height stays 23")
	view.queue_free()
```

`_run_deferred_tests()` 更新为依次调用 `_test_board_drop_detector()`、`_test_card_entity_sizing()`、`_test_card_view_label_container()` 后 `_finish_tests()`。

- [ ] **Step 2: 运行确认失败**

Run: `godot --headless -s res://tests/layout_config_test.gd`
Expected: FAIL。设置 `view.size = (80, 166)` 后 LabelContainer 仍是 131..154。

- [ ] **Step 3: 实现**

修改 `scripts/card/card_view.gd` 的 `_ready()` 并新增 `_pin_label_container()`：

```gdscript
func _ready() -> void:
	if not card_inst:
		card_inst = CardInstance.create_debug_card()
	resized.connect(_pin_label_container)
	_pin_label_container()
	refresh_display()


func _pin_label_container() -> void:
	var h := size.y
	labelcontainer.offset_left = 0.5
	labelcontainer.offset_top = h - 23.0
	labelcontainer.offset_right = size.x - 0.5
	labelcontainer.offset_bottom = h
```

- [ ] **Step 4: 运行确认通过**

Run: `godot --headless -s res://tests/layout_config_test.gd`
Expected: PASS。

- [ ] **Step 5: Commit**

```bash
git add scripts/card/card_view.gd tests/layout_config_test.gd
git commit -m "feat: pin card label bar to the card view bottom"
```

---

### Task 5: `GameManager` 棋盘与手牌居中

**Files:**
- Modify: `scripts/game_manager.gd`（`_ready` 末尾调用 `_center_layout()`，新增 `_center_layout()`）
- Test: `tests/layout_config_test.gd`

**Interfaces:**
- Consumes: `LayoutConfig.board_origin(view_size, cols, rows, cell_size)`, `LayoutConfig.hand_origin(view_size)`, `board.width/height/cell_size`。
- Produces: `GameManager._ready` 后 `board.position` 与 `hand_area.position` 按视口居中。`board` 为 `@onready var board: Board = $Board`，`hand_area` 为 `@onready var hand_area: HandArea = $HandManager`。

- [ ] **Step 1: 追加失败测试**

在 `tests/layout_config_test.gd` 顶部追加 preload：

```gdscript
const GameManagerScene = preload("res://scenes/game/game_manager.tscn")
```

在 `_run_deferred_tests()` 中追加 `_test_game_manager_centering()`：

```gdscript
func _test_game_manager_centering() -> void:
	var gm := GameManagerScene.instantiate()
	root.add_child(gm)
	var view := gm.get_viewport().get_visible_rect().size
	var expected_board := LayoutConfigScript.board_origin(
		view, gm.board.width, gm.board.height, gm.board.cell_size
	)
	var expected_hand := LayoutConfigScript.hand_origin(view)
	_expect(gm.board.position == expected_board, "game manager centers the board")
	_expect(gm.hand_area.position == expected_hand, "game manager centers the hand")
	gm.queue_free()
```

`_run_deferred_tests()` 更新为依次调用四个 `_test_*` 后 `_finish_tests()`。

- [ ] **Step 2: 运行确认失败**

Run: `godot --headless -s res://tests/layout_config_test.gd`
Expected: FAIL。`board.position` 仍是 (47, 44)，`hand_area.position` 仍是 (447, 789)。

- [ ] **Step 3: 实现**

修改 `scripts/game_manager.gd` 的 `_ready()` 末尾，追加 `_center_layout()`：

```gdscript
	init_player_cards()
	init_events()
	_center_layout()
```

新增（放在 `init_events()` 之后）：

```gdscript
## 棋盘水平居中（垂直让出底部手牌区），手牌居中贴底
func _center_layout() -> void:
	var view := get_viewport().get_visible_rect().size
	board.position = LayoutConfig.board_origin(view, board.width, board.height, board.cell_size)
	hand_area.position = LayoutConfig.hand_origin(view)
```

- [ ] **Step 4: 运行确认通过**

Run: `godot --headless -s res://tests/layout_config_test.gd`
Expected: PASS。

- [ ] **Step 5: Commit**

```bash
git add scripts/game_manager.gd tests/layout_config_test.gd
git commit -m "feat: center board and hand based on viewport"
```

---

### Task 6: `HandArea` 手牌参数派生

**Files:**
- Modify: `scripts/game/hand.gd:14-15`（`card_width`/`card_spacing` 默认值）
- Test: `tests/layout_config_test.gd`

**Interfaces:**
- Consumes: `LayoutConfig.CARD_W`, `LayoutConfig.HAND_SPACING`。
- Produces: `HandArea.card_width == 80`, `card_spacing == 30`（默认值）。

- [ ] **Step 1: 追加失败测试**

在 `tests/layout_config_test.gd` 的 `_init()` 末尾（`call_deferred` 之前，Task 2 的 board 断言之后）追加：

```gdscript
	var hand := HandAreaScript.new()
	_expect(hand.card_width == LayoutConfigScript.CARD_W, "hand card slot width derives from config")
	_expect(hand.card_spacing == LayoutConfigScript.HAND_SPACING, "hand card spacing derives from config")
```

- [ ] **Step 2: 运行确认失败**

Run: `godot --headless -s res://tests/layout_config_test.gd`
Expected: FAIL。`hand.card_width` 仍是 100，`card_spacing` 仍是 30（与 110/30 不符）。

- [ ] **Step 3: 实现**

修改 `scripts/game/hand.gd` 第 14-15 行：

```gdscript
@export var card_width: float = LayoutConfig.CARD_W
@export var card_spacing: float = LayoutConfig.HAND_SPACING
```

- [ ] **Step 4: 运行确认通过**

Run: `godot --headless -s res://tests/layout_config_test.gd`
Expected: PASS。

- [ ] **Step 5: Commit**

```bash
git add scripts/game/hand.gd tests/layout_config_test.gd
git commit -m "feat: derive hand layout spacing from layout config"
```

---

### Task 7: 手动验证（4 种分辨率）

**Files:**
- 无代码改动。

- [ ] **Step 1: 运行游戏并检查**

用 Godot 以如下 16:9 窗口尺寸各运行一次，逐项核对（可用 `window/size/viewport_width` 与 `viewport_height` 或窗口缩放临时调整）：

- 1280×720 / 1600×900 / 1920×1080 / 2560×1440

核对清单：

- 棋盘水平居中，四边留白对称，不超出屏幕、不压到手牌
- 卡牌吸附格子后与网格精确对齐（碰撞盒随 `cell_size` 放大后仍匹配）
- 手牌横向居中、贴底，卡牌互不重叠，悬停放大正常
- 拖拽 / 放置 / 旋转 / 右键放大、事件圈与棋盘格对齐均正常
- 修改 `LayoutConfig.CELL_SIZE` 为 90（临时），确认卡牌与网格同步变化后再改回 86

- [ ] **Step 2: 异常时回退**

若发现棋盘与手牌重叠或卡牌脱离网格：先检查 `_center_layout()` 是否在 `_ready` 末尾被调用、`card_entity.tscn` 是否被其他流程实例化且未走 `_apply_layout()`。修复后重跑 Step 1。
