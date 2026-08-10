# 棋盘事件 Hover 信息预览实施计划

> 本计划按已确认的 `docs/design/2026-08-10-board-event-hover-preview-design.md` 执行，所有新增文档均放在 `docs/design`，不写入 `superpower` 或 `superpowers` 目录。

**目标：** 为棋盘上的普通残响、Boss、商店与宝藏提供不触发事件的鼠标悬停信息预览。

**架构：** `BoardEvent` 只负责悬停信号，`Board` 负责动态事件的连接通知；独立的格式化器将事件模板与运行时状态转换为预览模型；统一的 CanvasLayer 预览协调器负责显示、隐藏和边界定位。事件接触、事件弹窗、战斗和奖励结算路径保持不变。

**技术栈：** Godot 4.7、GDScript、Control / CanvasLayer、现有 EventContent 多态资源、Godot headless 场景测试。

## 全局约束

- Hover 只读，不得调用事件触发、resolver、战斗开始或奖励发放逻辑。
- 事件仍只能通过卡牌放置接触事件格触发。
- 预览使用运行时状态优先于模板数据。
- 预览根节点和所有子节点使用 `MOUSE_FILTER_IGNORE`，不拦截卡牌拖放。
- 已解决事件不显示预览。
- 普通残响和 Boss 必须显示生命、掉落；能力缺失时显示“无额外效果”。
- 商店必须显示当前未售罄商品与价格；宝藏在随机奖励尚未生成时不得泄露具体结果。
- 每个生产行为先有能证明缺失行为的失败测试，再实现最小代码。
- 不使用 `git add .`，不重置或覆盖工作区中其它未提交修改。

## 文件结构

### 新增

- `scripts/game/event/hover/event_hover_preview_model.gd`：视图专用、无节点引用的预览模型。
- `scripts/game/event/hover/event_hover_preview_formatter.gd`：按事件类型格式化模板和运行时数据。
- `scripts/game/event/hover/event_hover_preview_coordinator.gd`：绑定棋盘事件、切换唯一预览浮层、计算位置。
- `scenes/game/event_hover_preview.tscn`：统一只读预览面板。
- `scripts/game/event/hover/event_hover_preview.gd`：预览面板视图绑定与文本刷新。
- `tests/event_hover_preview_formatter_test.gd`：四类事件的数据格式化测试。
- `tests/event_hover_preview_interaction_test.gd`：悬停信号、动态事件连接和不触发事件测试。
- `tests/event_hover_preview_scene_test.gd`：预览场景字段、鼠标过滤和定位边界测试。

### 修改

- `scripts/game/event.gd`：增加 `hover_started` / `hover_ended`，为事件根节点接收鼠标进入和离开；已解决事件不发出可显示预览。
- `scripts/game/board.gd`：增加事件附着 / 移除通知，使动态生成和 Boss 移动后的事件都能被协调器监听。
- `scripts/game_manager.gd`：配置并持有预览协调器，不让 `GameManager` 解析事件数据。
- `scenes/game/game_manager.tscn`：加入预览 CanvasLayer / 预览面板实例。

## 实施步骤

### Task 1：建立预览模型和怪物 / Boss / 商店 / 宝藏格式化契约

**Files:**
- Create: `scripts/game/event/hover/event_hover_preview_model.gd`
- Create: `scripts/game/event/hover/event_hover_preview_formatter.gd`
- Test: `tests/event_hover_preview_formatter_test.gd`

**接口：**
- `EventHoverPreviewFormatter.build(instance: EventInstance) -> EventHoverPreviewModel`
- `EventHoverPreviewModel.visible: bool`
- `EventHoverPreviewModel.title: String`
- `EventHoverPreviewModel.type_label: String`
- `EventHoverPreviewModel.stat_lines: Array[String]`
- `EventHoverPreviewModel.reward_lines: Array[String]`
- `EventHoverPreviewModel.ability_lines: Array[String]`

步骤：

- [ ] 编写普通残响预览失败测试：名称、运行时生命优先、金币 / 卡牌掉落、概率文本、能力文本和无能力回退。
- [ ] 编写 Boss 预览失败测试：Boss 标记、生命、护甲与掉落。
- [ ] 编写商店预览失败测试：未售罄商品显示名称 / 点数 / 护甲 / 价格，售罄商品过滤。
- [ ] 编写宝藏预览失败测试：未生成奖励时只显示类别和选择数量，已生成选项后显示摘要。
- [ ] 运行 `D:\InstallPath\godot\Godot_v4.7-stable_win64_console.exe --headless --path . --script res://tests/event_hover_preview_formatter_test.gd`，确认测试因新类型不存在而失败。
- [ ] 实现模型字段和格式化器，复用现有 `MobData`、`MobInstance`、`EncounterDropEntry`、`ShopRuntimeState` 与 `TreasureRuntimeState`，不创建第二套奖励数据结构。
- [ ] 重新运行格式化器测试，确认通过。
- [ ] 执行 `git diff --check`，提交：`feat(events): add event hover preview formatting`。

### Task 2：让棋盘事件支持悬停且支持动态事件生命周期

**Files:**
- Modify: `scripts/game/event.gd`
- Modify: `scripts/game/board.gd`
- Test: `tests/event_hover_preview_interaction_test.gd`

**接口：**
- `BoardEvent.hover_started(event_node: BoardEvent)`
- `BoardEvent.hover_ended(event_node: BoardEvent)`
- `Board.event_attached(event_node: BoardEvent)`
- `Board.event_removed(event_node: BoardEvent)`

步骤：

- [ ] 编写测试，实例化真实 `BoardEvent`，验证未解决事件可发出 hover 开始 / 结束信号。
- [ ] 编写测试，验证已解决事件不会产生可显示的 hover 请求。
- [ ] 编写测试，动态 `attach_event` 与 `remove_event` 会发出对应通知；事件移动时仍保持同一个事件节点和实例。
- [ ] 编写回归断言：调用 hover 相关方法不会发出 `Board.event_triggered`，不会修改 `EventInstance.is_revealed` / `is_resolved`。
- [ ] 运行该测试，确认在尚无信号和鼠标接收配置时失败。
- [ ] 修改 `BoardEvent`：根 Control 接收鼠标进入 / 离开，子节点继续忽略鼠标；在 `_refresh` 中已解决事件隐藏悬停能力。
- [ ] 修改 `Board`：在事件附着后发出 `event_attached`，移除前后按既有生命周期安全发出 `event_removed`。
- [ ] 重新运行交互测试，确认通过。
- [ ] 执行 `git diff --check`，提交：`feat(events): expose board event hover lifecycle`。

### Task 3：实现统一预览视图

**Files:**
- Create: `scripts/game/event/hover/event_hover_preview.gd`
- Create: `scenes/game/event_hover_preview.tscn`
- Test: `tests/event_hover_preview_scene_test.gd`

**接口：**
- `EventHoverPreview.present(model: EventHoverPreviewModel) -> void`
- `EventHoverPreview.dismiss() -> void`
- `EventHoverPreview.is_presenting() -> bool`

步骤：

- [ ] 编写场景测试，验证预览可加载、包含标题 / 类型 / 属性 / 奖励 / 能力容器，并且根节点鼠标过滤为 `IGNORE`。
- [ ] 编写测试，验证 `present` 会刷新文本，`dismiss` 隐藏面板并清空当前模型。
- [ ] 运行场景测试确认失败。
- [ ] 创建紧凑的 PanelContainer 预览面板：标题、类型徽章、属性区、奖励区、能力区；所有文本可换行但不改变事件圈尺寸。
- [ ] 实现空数组区块隐藏、无奖励 / 无能力的明确回退文本，以及超长名称 / 描述的裁剪策略。
- [ ] 重新运行场景测试，确认通过。
- [ ] 提交：`feat(events): add event hover preview panel`。

### Task 4：实现悬停协调器和边界定位

**Files:**
- Create: `scripts/game/event/hover/event_hover_preview_coordinator.gd`
- Modify: `scripts/game/board.gd`（如需暴露当前事件列表的只读同步接口）
- Test: `tests/event_hover_preview_scene_test.gd`
- Test: `tests/event_hover_preview_interaction_test.gd`

**接口：**
- `EventHoverPreviewCoordinator.configure(board: Board, preview: EventHoverPreview, viewport: Viewport) -> bool`
- `EventHoverPreviewCoordinator.show_for(event_node: BoardEvent) -> void`
- `EventHoverPreviewCoordinator.hide() -> void`
- `EventHoverPreviewCoordinator.calculate_position(event_rect: Rect2, panel_size: Vector2, viewport_size: Vector2) -> Vector2`

步骤：

- [ ] 先补充定位失败测试：右侧空间足够时右侧显示，右侧不足时左侧显示，垂直坐标始终钳制在视口内。
- [ ] 补充测试：同时 hover 不同事件时只显示一个面板，离开当前事件后隐藏；动态附着事件自动接入。
- [ ] 运行测试，确认定位和订阅行为失败。
- [ ] 实现协调器：订阅 `Board.event_attached` / `event_removed`，连接每个 `BoardEvent` 的 hover 信号；事件移除时清理当前预览。
- [ ] 用 `EventHoverPreviewFormatter` 创建模型，仅对 `visible == true` 的未解决事件调用 `present`。
- [ ] 实现右侧优先、左侧回退、视口内钳制；不要修改事件节点坐标。
- [ ] 重新运行两项交互 / 场景测试，确认通过。
- [ ] 提交：`feat(events): coordinate board event hover previews`。

### Task 5：接入 GameManager 场景并完成回归

**Files:**
- Modify: `scripts/game_manager.gd`
- Modify: `scenes/game/game_manager.tscn`
- Modify: `tests/game_manager_architecture_test.gd`（只增加预览协调器接入契约）
- Test: `tests/home_screen_flow_test.gd`（仅在现有场景测试需要时，不改变首页行为）

步骤：

- [ ] 先增加 GameManager 配置测试：游戏场景加载后存在预览面板，运行初始化不会因为预览配置失败。
- [ ] 运行测试确认 GameManager 尚未暴露该组件而失败。
- [ ] 在 `game_manager.tscn` 增加独立的预览 CanvasLayer 与面板实例；面板置于事件和卡牌上方，但低于事件 Modal Layer。
- [ ] 在 `game_manager.gd` 增加最小配置方法，向协调器注入 `board`、预览面板和 viewport；GameManager 不解析事件内容。
- [ ] 运行 GameManager 配置测试、事件交互测试和预览测试。
- [ ] 手动运行游戏，验证悬停四类事件和移开隐藏；验证拖卡接触事件仍打开原事件弹窗。
- [ ] 运行全部 `tests/*_test.gd`。
- [ ] 执行 `git diff --check`，检查 `git status --short`，确认不包含其它未提交工作的文件。
- [ ] 提交：`feat(events): show hover previews for board events`。

## 验证命令

单项：

```powershell
$godot='D:\InstallPath\godot\Godot_v4.7-stable_win64_console.exe'
& $godot --headless --path . --script res://tests/event_hover_preview_formatter_test.gd
& $godot --headless --path . --script res://tests/event_hover_preview_interaction_test.gd
& $godot --headless --path . --script res://tests/event_hover_preview_scene_test.gd
```

全量：

```powershell
$godot='D:\InstallPath\godot\Godot_v4.7-stable_win64_console.exe'
Get-ChildItem tests -Filter '*_test.gd' -File | ForEach-Object {
    & $godot --headless --path . --script ("res://tests/" + $_.Name)
    if ($LASTEXITCODE -ne 0) { throw "Test failed: $($_.Name)" }
}
```
