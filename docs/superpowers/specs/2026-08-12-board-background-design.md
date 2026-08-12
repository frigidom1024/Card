# BoardBackground 白色简洁棋盘视觉设计

日期：2026-08-12

## 目标

将棋盘视觉改为白色简洁像素风，同时不改变现有 Board 的逻辑坐标、卡牌放置、事件占用、拖拽预览和碰撞检测。

## 结构

新增独立场景：

- `scenes/game/board_background.tscn`
- `scripts/game/board_background.gd`

`BoardBackground` 作为 `Board` 的视觉子节点，负责：

1. 绘制比逻辑棋盘稍大的半透明灰色区域；
2. 绘制逻辑棋盘范围内的虚线网格；
3. 根据 `Board.width`、`Board.height`、`Board.cell_size` 同步尺寸；
4. 只承担绘制，不参与鼠标输入和游戏逻辑。

`Board` 继续负责：

- 卡牌与事件的逻辑占用；
- 放置检测和吸附；
- 卡牌预览高亮；
- DropDetector 碰撞区域；
- 事件触发和牌链行为。

## 场景层级

```text
Board (Node2D)
├── BoardBackground (Node2D)
└── DropDetector (Area2D)
    └── CollisionShape2D
```

`BoardBackground` 的绘制层级低于卡牌、事件和预览。它不新增 Control 节点，因此不会阻塞 CardEntity 的 Area2D 输入。

## 可配置参数

```gdscript
@export var board_padding := Vector2(14.0, 14.0)
@export var board_panel_color := Color(0.35, 0.39, 0.44, 0.14)
@export var grid_line_color := Color(0.35, 0.39, 0.44, 0.36)
@export var grid_line_width := 2.0
@export var grid_dash_length := 6.0
@export var grid_gap_length := 5.0
```

其中：

- `board_padding` 是逻辑棋盘四周的视觉外扩距离；
- `board_panel_color` 是半透明灰色底板；
- `grid_line_color` 是虚线网格颜色；
- `grid_line_width` 控制像素线宽；
- `grid_dash_length` 与 `grid_gap_length` 控制虚线节奏。

## 绘制规则

底板矩形：

```text
Rect2(-board_padding, board_size + board_padding * 2)
```

网格线只覆盖逻辑棋盘区域：

- 竖线：`x = 0 ... width * cell_size`；
- 横线：`y = 0 ... height * cell_size`；
- 每条线使用等距短线段绘制，不使用连续实线；
- 外边框可使用同一套虚线，不额外引入深色边框。

背景节点通过公开的 `configure(board_size, cell_size, width, height)` 或等价属性同步尺寸，避免复制 Board 的逻辑配置。Board 在 `_ready()` 和尺寸变化时调用同步方法。

## 输入与层级

`BoardBackground` 不处理输入。因为它是 `Node2D` 绘制节点而不是 `Control`，不会截获 GUI 输入；同时将其 `z_index` 设置为棋盘背景层级，确保它位于卡牌和事件之下。

## 预览层顺序

```text
BoardBackground
→ Board 的放置预览高亮
→ BoardEvent / CardEntity
→ 拖拽层与战斗标签
```

预览高亮仍由 `Board._draw()` 绘制，因此不会破坏现有预览颜色和放置校验逻辑。

## 验收标准

1. 逻辑棋盘的坐标转换结果不变；
2. 逻辑棋盘外可见一圈均匀的半透明灰色区域；
3. 网格为清晰的像素虚线，不出现连续实线；
4. 背景尺寸随 `width`、`height`、`cell_size` 改变；
5. 背景不会挡住卡牌拖拽、悬浮、点击或事件交互；
6. 不改变 DropDetector 的逻辑碰撞范围；
7. Board 场景可以在测试中独立实例化，不依赖运行时 HUD。
