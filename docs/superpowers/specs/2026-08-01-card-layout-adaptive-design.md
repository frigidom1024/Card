# 卡牌尺寸与牌桌自适应布局设计

**日期：** 2026-08-01
**状态：** 已确认，待实施计划
**范围：** 把写死的卡牌/棋盘尺寸收敛为单一基准 `cell_size`，卡牌尺寸由基准派生；棋盘与手牌按视口居中；支持桌面 16:9 不同分辨率。

## 1. 目标与非目标

### 目标

- 消除卡牌尺寸（碰撞盒 80×160、卡面 74×154）与 `Board.cell_size` 之间仅靠"约定"匹配的耦合，改为卡牌尺寸由 `cell_size` 派生。
- 让棋盘在 16:9 窗口下水平居中，不再贴左上角。
- 让棋盘/卡牌在垂直空间允许范围内变大（`cell_size` 由 80 提升至 86）。
- 手牌区水平居中、贴屏幕底部，与棋盘下缘保持合理间隙。
- 布局基于运行时视口尺寸计算，不依赖写死的节点位置。

### 非目标

- 不处理非 16:9 比例（超宽屏、竖屏、平板）。`canvas_items` + `expand` 在非 16:9 下可见区域变化的适配不在本次范围。
- 不改变棋盘网格 10×8 的规格、卡牌占格规则（1×2 格）与放置/吸附逻辑。
- 不重构 `drag_layer` 提示标签、`hand.gd` 调试绘制等次要屏幕空间元素。
- 不改 `event.gd`（已按传入的 `cell_size` 定位，会自动跟随）。

## 2. 术语

| 名称 | 定义 |
| --- | --- |
| cell_size | 棋盘单格边长，全局尺寸唯一来源。 |
| 卡面 | `CardView` 视觉矩形，比占格小 `CARD_MARGIN`（6px）。 |
| 基准分辨率 | 1600×900。`canvas_items` 模式下任意 16:9 窗口等比缩放，运行时 `get_viewport().get_visible_rect().size` 恒为 1600×900。 |

## 3. 当前写死尺寸清单

| 位置 | 现值 | 含义 |
| --- | --- | --- |
| `board.gd` `cell_size` | 80 | 网格/吸附/事件定位基准 |
| `card_entity.tscn` 碰撞盒 | 80×160 | 卡牌碰撞，等于 2 格 |
| `card_entity.tscn` CardView 偏移 | -37/-78/+37/+76（74×154） | 卡面矩形 |
| `card_view.tscn` LabelContainer 偏移 | 131..154 | 底部属性栏，写死高度 |
| `hand.gd` `card_width / card_spacing` | 100 / 30 | 手牌卡位步长 130 |
| `game_manager.tscn` Board 位置 | (47, 44) | 棋盘贴左上角 |
| `game_manager.tscn` HandManager 位置 | (447, 789) | 手牌位置 |

## 4. 设计

### 4.1 新增布局常量 `scripts/game/layout_config.gd`

```gdscript
class_name LayoutConfig
extends RefCounted

const CELL_SIZE    := 86          # 原 80
const CARD_MARGIN  := 6           # 卡面比格子小 6px
const CARD_W       := CELL_SIZE - CARD_MARGIN        # 卡面宽 = 80
const CARD_H       := CELL_SIZE * 2 - CARD_MARGIN    # 卡面高 = 166
const HAND_SPACING := int(CELL_SIZE * 0.35)          # 手牌卡间距 = 30
const HAND_STEP    := CARD_W + HAND_SPACING          # 手牌卡位步长 = 110
const BOARD_TOP_MARGIN := 16.0                       # 棋盘顶部留白
const HAND_BOTTOM_MARGIN := 96.0                     # 手牌中心距屏幕底
```

### 4.2 卡牌尺寸派生

- `board.gd`：`@export var cell_size: int = LayoutConfig.CELL_SIZE`。`Board.width/height` 保持 10×8。
- `card_entity.gd`：`_ready()` 中新增 `_apply_layout()`：
  - `$CollisionShape2D.shape`（`RectangleShape2D`）尺寸设为 `Vector2(CELL_SIZE, CELL_SIZE * 2)`；
  - CardView 按 `CARD_W × CARD_H` 居中设置 `offset_left/top/right/bottom`；
  - `CardInfo` 悬浮位置保持由 `_card_view` 尺寸推算，自动跟随。
- `card_view.gd`：`_ready()` 中把 `LabelContainer` 对齐到卡面底部（`size.y - 23 .. size.y`），替换写死的 131..154。

### 4.3 居中布局（`game_manager.gd`）

`_ready()` 末尾调用新增 `_center_layout()`：

```gdscript
func _center_layout() -> void:
    var view := get_viewport().get_visible_rect().size
    var grid_w := board.width * board.cell_size
    var grid_h := board.height * board.cell_size
    board.position = Vector2((view.x - grid_w) / 2.0, LayoutConfig.BOARD_TOP_MARGIN)
    hand_area.position = Vector2(view.x / 2.0, view.y - LayoutConfig.HAND_BOTTOM_MARGIN)
```

网格原点仍在 Board 局部 (0,0)，仅节点整体移动，`world_to_grid` / `snap_card_position` 等逻辑不变。

### 4.4 手牌参数派生

`hand.gd` 的 `card_width` / `card_spacing` 默认值改为 `LayoutConfig.CARD_W` / `LayoutConfig.HAND_SPACING`（80 / 30，步长 110，卡间距 30，比现状略紧凑）。`max_hand_size` 保持 10。

### 4.5 场景文件

`card_entity.tscn` / `card_view.tscn` 中写死的尺寸保留作为 Godot 初始默认，运行时由上述逻辑覆盖。`game_manager.tscn` 中 Board / HandManager 位置保留但会被 `_center_layout()` 覆盖。

## 5. 数值结果（CELL_SIZE=86）

| 项 | 现状 | 改后 |
| --- | --- | --- |
| 卡面 | 74×154 | 80×166（约 +8%） |
| 棋盘 | 800×640，左上角 (47,44) | 860×688，水平居中（x 370..1230） |
| 棋盘垂直 | 44..684 | 16..704 |
| 手牌中心 | (447, 789) | (800, 804)，卡牌 718..890 |
| 棋盘底 ↔ 手牌顶 | 约 25px | 约 14px |

## 6. 验证

手动运行以下 16:9 窗口尺寸，逐项核对：

- 1280×720 / 1600×900 / 1920×1080 / 2560×1440
- 棋盘水平居中，四边留白对称；不超出屏幕、不压到手牌
- 卡牌吸附格子后与网格对齐（碰撞盒随 `cell_size` 放大后仍精确匹配）
- 手牌横向居中、贴底，卡牌互不重叠
- 拖拽 / 放置 / 旋转 / 悬停放大 / 右键查看、事件圈与棋盘格对齐均正常
- 调整 `LayoutConfig.CELL_SIZE` 一个值，卡牌与网格同步变化

## 7. 限制与风险

- **垂直空间受限**：8 行网格 + 底部手牌将 `CELL_SIZE` 上限锁在约 86，再大会使棋盘顶部越界或与手牌重叠。"变大"幅度有限，主要收益是居中与消除写死耦合。
- **非 16:9 不做适配**：非 16:9 窗口下 `expand` 会改变可见区域，本次不处理，按目标设备范围取舍。
- **手牌更紧凑**：手牌步长由 130 降至 110，若观感过挤可调 `HAND_SPACING`。
