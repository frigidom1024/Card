# 商店与宝藏事件面板场景实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 创建可独立加载的商店与宝藏事件模态场景，采用三槽卡牌橱窗布局并直接复用既有 `CardView` 场景。

**Architecture:** 两个场景都以全屏 `Control` 为根节点，提供遮罩层、居中面板、标题区、三槽选项区和底部提示区。商店的三个槽均实例化 `card_view.tscn`；宝藏的前两个槽实例化该场景，第三个槽使用独立金币奖励预览，以便后续 UI 控制器只通过稳定节点名填充展示数据和接入事件结算。

**Tech Stack:** Godot 4.7、GDScript、`.tscn` 场景资源、headless Godot 测试。

## Global Constraints

- 必须直接复用 `res://scenes/card_view/card_view.tscn`，不复制卡牌的属性、标签、颜色等渲染逻辑。
- 展示用 `CardInstance` 仅在后续 UI 脚本中调用 `CardPreview.set_value(...)`，不加入玩家卡组、手牌或棋盘。
- 本阶段不修改 `scripts/game_manager.gd`、事件触发、购买、奖励结算或关闭流程。
- 所有按钮仅作为视觉占位，不连接业务信号。
- 商店为蓝色主题；宝藏为琥珀 / 金色主题；两个场景均应在 1920×1080 下覆盖全屏并居中显示。
- 保留规格中约定的稳定节点名，供后续事件路由与 UI 脚本使用。

---

## 文件结构

- Create: `tests/event_ui_scene_test.gd` — 无界面加载、实例化并检查两个事件面板稳定结构的回归测试。
- Modify: `scenes/game/event_shop.tscn` — 蓝色商店模态场景，包含三个复用 `CardView` 的商品槽。
- Create: `scenes/game/event_treasure.tscn` — 琥珀色宝藏模态场景，包含两个 `CardView` 奖励槽和一个金币奖励槽。
- Create: `docs/superpowers/plans/2026-08-01-event-modal-scenes.md` — 本实施计划。

### Task 1: 事件面板场景结构回归测试

**Files:**
- Create: `tests/event_ui_scene_test.gd`

**Interfaces:**
- Consumes: `res://scenes/game/event_shop.tscn`、`res://scenes/game/event_treasure.tscn`、`res://scenes/card_view/card_view.tscn`
- Produces: 一个以非零退出码报告缺失节点或错误场景嵌套的 headless 测试入口。

- [ ] **Step 1: 写入失败测试**

创建一个 `extends SceneTree` 测试脚本，加载并实例化两个场景。对两个根节点递归检查 `Overlay`、`Panel`、`Header`、`TitleLabel`、`SubtitleLabel`、`CloseButton`、`OfferContainer`、三个 `OfferSlot` 和 `HintLabel`；额外检查商店存在 `GoldLabel` 和三个 `CardPreview`，宝藏存在两个 `CardPreview` 与一个 `GoldRewardPreview`。对所有 `CardPreview` 检查其脚本资源路径为 `res://scripts/card/card_view.gd`。

- [ ] **Step 2: 运行测试，确认当前资源尚不满足约定**

Run:

```powershell
& 'D:\InstallPath\godot\Godot_v4.7-stable_win64_console.exe' --headless --path . --script tests/event_ui_scene_test.gd
```

Expected: FAIL，因为 `event_shop.tscn` 仍是占位场景且 `event_treasure.tscn` 尚不存在。

- [ ] **Step 3: 保留失败断言的信息性输出**

每个断言通过 `_expect(condition, message)` 累积失败数量，最后执行 `quit(1 if _failure_count > 0 else 0)`，使 CI 和本地命令得到确定的退出码。

- [ ] **Step 4: 提交测试骨架（与场景实现一起提交）**

```powershell
git add tests/event_ui_scene_test.gd
git commit -m "test: cover event modal scene structure"
```

### Task 2: 实现商店事件模态场景

**Files:**
- Modify: `scenes/game/event_shop.tscn`
- Test: `tests/event_ui_scene_test.gd`

**Interfaces:**
- Consumes: `res://scenes/card_view/card_view.tscn` 作为每个商品槽中的 `CardPreview`。
- Produces: `EventShop` 场景，提供 `Overlay`、`Panel`、`Header`、`TitleLabel`、`SubtitleLabel`、`GoldLabel`、`CloseButton`、`OfferContainer`、`OfferSlot1..3`、各槽 `CardPreview`、`PriceOrRewardLabel`、`ActionButton` 和 `HintLabel`。

- [ ] **Step 1: 以全屏根节点和遮罩替换占位场景**

根节点使用 anchors preset 15 覆盖 viewport；添加 `Overlay: ColorRect`，颜色为半透明深蓝黑，`mouse_filter = 0`，阻止棋盘在模态开启时接收点击。

- [ ] **Step 2: 创建蓝色居中面板与标题区**

添加 `CenterContainer` 和 `Panel: PanelContainer`；`Panel` 最小尺寸约 `960×600`。使用 `StyleBoxFlat` 提供深蓝背景、淡蓝描边和圆角。标题区 `Header` 包含 `TitleLabel`（“流浪商店”）、`SubtitleLabel`（“挑选一张卡牌加入你的旅途”）、`GoldLabel`（“金币：0”）和 `CloseButton`（“×”）。

- [ ] **Step 3: 创建三个复用 CardView 的商品槽**

在 `OfferContainer: HBoxContainer` 内放置 `OfferSlot1`、`OfferSlot2`、`OfferSlot3`。每个槽使用 `PanelContainer` 加 `VBoxContainer`，其中 `CardPreview` 必须是 `card_view.tscn` 实例，且在容器中设置合适的最小尺寸；下方依次为 `PriceOrRewardLabel`（例如“价格：12 金币”）和 `ActionButton`（“购买”）。

- [ ] **Step 4: 添加底部提示区**

为 `HintLabel` 配置可读的默认引导文本“选择商品后，后续将由事件流程结算。”，其容器与面板风格协调。

- [ ] **Step 5: 运行单场景结构测试**

Run:

```powershell
& 'D:\InstallPath\godot\Godot_v4.7-stable_win64_console.exe' --headless --path . --script tests/event_ui_scene_test.gd
```

Expected: 宝藏场景仍缺失时失败；商店相关断言全部通过。

### Task 3: 实现宝藏事件模态场景

**Files:**
- Create: `scenes/game/event_treasure.tscn`
- Test: `tests/event_ui_scene_test.gd`

**Interfaces:**
- Consumes: `res://scenes/card_view/card_view.tscn` 作为卡牌奖励槽中的 `CardPreview`。
- Produces: `EventTreasure` 场景，提供与商店对应的通用稳定节点，以及两个 `CardPreview` 奖励与一个 `GoldRewardPreview`。

- [ ] **Step 1: 创建与商店一致的模态骨架**

根节点、`Overlay`、`CenterContainer`、`Panel`、`Header`、`OfferContainer` 与底部提示区的层级和布局职责保持一致；主题换为深琥珀背景与金色描边。

- [ ] **Step 2: 创建标题和三项奖励**

设置 `TitleLabel` 为“遗失宝藏”、`SubtitleLabel` 为“选择一项奖励”、`CloseButton` 为“×”。`OfferSlot1` 与 `OfferSlot2` 分别包含 `CardPreview`、`PriceOrRewardLabel`（“卡牌奖励”）和 `ActionButton`（“领取”）。

- [ ] **Step 3: 创建金币奖励预览槽**

`OfferSlot3` 使用 `GoldRewardPreview: PanelContainer` 而不是 `CardView`；其子节点显示金币符号和“+20 金币”。下方保留 `PriceOrRewardLabel`（“金币奖励”）和 `ActionButton`（“领取”）。

- [ ] **Step 4: 添加底部提示区**

为 `HintLabel` 配置“只能带走一项奖励。”，明确首版选择语义。

- [ ] **Step 5: 运行场景结构回归测试**

Run:

```powershell
& 'D:\InstallPath\godot\Godot_v4.7-stable_win64_console.exe' --headless --path . --script tests/event_ui_scene_test.gd
```

Expected: PASS，退出码 0。

### Task 4: 编辑器资源解析与完整验证

**Files:**
- Verify: `tests/event_ui_scene_test.gd`
- Verify: `scenes/game/event_shop.tscn`
- Verify: `scenes/game/event_treasure.tscn`

**Interfaces:**
- Consumes: 已实现的场景和结构测试。
- Produces: 可复现的解析和结构验证结果。

- [ ] **Step 1: 执行场景结构测试**

Run:

```powershell
& 'D:\InstallPath\godot\Godot_v4.7-stable_win64_console.exe' --headless --path . --script tests/event_ui_scene_test.gd
```

Expected: PASS，退出码 0。

- [ ] **Step 2: 执行编辑器导入与解析检查**

Run:

```powershell
& 'D:\InstallPath\godot\Godot_v4.7-stable_win64_console.exe' --headless --path . --editor --quit
```

Expected: 退出码 0，输出不包含新场景或新测试的解析错误。

- [ ] **Step 3: 审查工作区变更**

Run:

```powershell
git diff --check
git status --short
git diff -- scenes/game/event_shop.tscn scenes/game/event_treasure.tscn tests/event_ui_scene_test.gd docs/superpowers/plans/2026-08-01-event-modal-scenes.md
```

Expected: 无空白错误；仅包含计划、场景和测试相关改动。

- [ ] **Step 4: 提交已验证实现**

```powershell
git add docs/superpowers/plans/2026-08-01-event-modal-scenes.md scenes/game/event_shop.tscn scenes/game/event_treasure.tscn tests/event_ui_scene_test.gd
git commit -m "feat: add shop and treasure event scenes"
```
