# BoardBackground 棋盘背景实现计划

> 日期：2026-08-12
> 关联设计：`docs/superpowers/specs/2026-08-12-board-background-design.md`

## 目标

将棋盘的视觉绘制从 `Board` 的逻辑脚本中拆出，新增独立的 `BoardBackground` 场景。背景显示略大于逻辑棋盘的半透明灰色底板和像素风虚线网格，同时保持现有棋盘逻辑、拖拽预览、事件占用与碰撞检测不变。

## 约束与现状

- 只修改本任务相关文件，不回滚或清理工作区中其他未提交改动。
- `Board` 仍必须保持 `Node2D` 类型及现有公开接口。
- `BoardBackground` 必须使用 `Node2D` 绘制，不能添加会拦截输入的 `Control` 节点。
- `DropDetector` 的尺寸仍只覆盖逻辑棋盘，不包含视觉 padding。
- 当前 Godot MCP 未连接，因此执行阶段同时提供静态检查；若 Godot 可用，再运行场景测试。

## 任务 1：先写棋盘背景回归测试

**文件：**

- 新增 `tests/board_background_test.gd`

**测试先行：**

1. 预加载并实例化 `res://scenes/game/board.tscn`。
2. 断言 `Board/BoardBackground` 存在，脚本类型为 `BoardBackground`，且背景不是 `Control`。
3. 断言默认背景配置同步到 `Board.width`、`Board.height`、`Board.cell_size`。
4. 修改 Board 的尺寸配置，通过公开同步接口更新背景，断言背景的逻辑尺寸随之更新，而不改变 `DropDetector` 的逻辑尺寸约定。
5. 断言背景拥有虚线参数并默认启用绘制配置；测试不依赖截图，不把具体像素颜色作为逻辑断言。

先运行测试确认其因背景节点/API 尚不存在而失败，再进入任务 2。

## 任务 2：实现 BoardBackground 并接入 Board

**新增文件：**

- `scripts/game/board_background.gd`
- `scenes/game/board_background.tscn`

**修改文件：**

- `scenes/game/board.tscn`
- `scripts/game/board.gd`

**实现要求：**

1. `BoardBackground` 继承 `Node2D`，提供以下可调参数：
   - `board_padding: Vector2 = Vector2(14, 14)`；
   - `board_panel_color` 半透明灰色；
   - `grid_line_color` 灰色半透明；
   - `grid_line_width`；
   - `grid_dash_length`；
   - `grid_gap_length`。
2. 提供明确的同步接口，例如 `configure(board_size: Vector2, cell_size: float, width: int, height: int)`，并保存可供测试读取的 `board_size`、`cell_size`、`grid_width`、`grid_height`。
3. `_draw()` 只绘制：
   - `Rect2(-board_padding, board_size + board_padding * 2)` 的半透明灰色底板；
   - 从 `0` 到逻辑棋盘宽高边界的水平、垂直虚线；
   - 用短线段和间隔实现虚线，不绘制原有连续灰色网格。
4. `Board` 在 `_ready()` 中获取 `BoardBackground` 并同步尺寸；同时保留 `_apply_drop_detector_size()`，且 Board 的 `_draw()` 删除旧的连续网格，只保留放置预览高亮。
5. 当 Board 的导出尺寸配置被运行时改变并调用同步接口时，背景和 DropDetector 都更新；背景 padding 不得影响 DropDetector。
6. 背景 `z_index` 使用 `RenderPriority.BOARD_BACKGROUND`，不改变卡牌、事件和预览层级。
7. 场景中明确挂载 `BoardBackground` 子节点，并让 `BoardBackground` 先于 `DropDetector` 出现。

**实现后验证：**

- 运行新增测试及现有 Board 相关测试；
- 用 `git diff --check` 检查本任务修改；
- 静态搜索确认没有遗留 `Sprite2D` 背景依赖，也没有把背景尺寸用于碰撞盒；
- 若 Godot MCP 恢复连接，打开 `board.tscn` 检查节点树并运行测试场景。

## 任务 3：评审与收尾

1. 对照设计文档逐项检查职责分离、层级、输入与尺寸同步。
2. 检查现有工作区改动没有被覆盖或回滚。
3. 运行能够执行的完整验证命令，并记录 Godot 不可用时的限制。
4. 仅在验证结果支持时汇报完成状态。
