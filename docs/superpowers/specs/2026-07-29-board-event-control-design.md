# 棋盘事件 Control 节点设计

## 目标

将 `scenes/game/event.tscn` 作为可放入 `Board` 的棋盘事件节点。它只负责事件的显示和输入通知，不负责打开战斗、商店或奖励界面。

## 场景结构

- 根节点：`Control`，锚点固定在左上角，不再拉伸至整个窗口。
- 内容：可点击的按钮底板、事件类型图标文字、事件名称与已完成遮罩。
- 节点尺寸根据 `EventInstance` 的 `size` 和棋盘 `cell_size` 设置；位置根据 `origin` 对齐到棋盘的左上格。

## 对外接口

- `setup(instance: EventInstance, cell_size: int)`：绑定运行时事件并同步显示、位置与尺寸。
- `event_selected(instance: EventInstance)` 信号：玩家点击未完成事件时发出，由 `Board` 或游戏管理器决定后续流程。
- 已完成事件保留在棋盘上，以弱化样式显示，并禁止再次触发。

## 显示规则

- 优先使用 `EventData.icon`；没有图标时使用事件类型的简短文字。
- 商店、宝箱、小怪、Boss 使用不同主题颜色。
- 未绑定事件时显示安全的默认预览，不产生输入行为。

## 验证

新增场景级测试，验证节点能从 `EventInstance` 读取位置、尺寸、名称和类型；点击时只发出信号而不处理具体游戏流程。
