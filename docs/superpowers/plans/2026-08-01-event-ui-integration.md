# 商店与宝藏事件 UI 接入实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让商店和宝藏事件在棋盘触发后由 `GameManager` 路由至对应模态面板，并完成购买、奖励领取、发卡、事件刷新和交互解锁。

**Architecture:** `ShopEventView` 与 `TreasureEventView` 仅将 `EventInstance` 及其运行时状态渲染为既有场景中的稳定节点，并发出操作请求或关闭请求。`GameManager` 是唯一编排者：按事件类型打开视图、调用已有 resolver、把成功返回的 `CardData` 制作成玩家手牌实体、刷新棋盘事件并管理 `DragLayer` 锁定；视图不直接修改玩家数据或事件状态。

**Tech Stack:** Godot 4.7、GDScript、`.tscn` 场景资源、已有 `ShopEventResolver` / `TreasureEventResolver`、headless Godot 测试。

## Global Constraints

- 保持 `CardPreview` 直接复用 `res://scenes/card_view/card_view.tscn`；展示卡牌使用临时 `CardInstance`，不写入玩家状态。
- 商店与宝藏视图不直接调用 resolver、不直接修改 `PlayerData`、不直接创建玩家卡牌。
- `GameManager` 使用全局 `class_name` 访问新类型，不新增 `const XxxScript = preload()` 加 `.new()` 的脚本构造方式。
- 商店购买成功后保持事件未解决并允许继续购买未售罄商品；关闭面板不解决事件。
- 宝藏成功领取一项奖励后解决事件、刷新棋盘显示并关闭面板。
- 卡牌奖励只有在 `HandArea` 有容量时才可结算；金币奖励不受手牌容量限制。
- 模态面板显示时必须锁定 `DragLayer`，关闭或宝藏结算完成后解锁；探索失败时不解锁。
- 本阶段不修改战斗服务或遭遇战结算语义。

---

## 文件结构

- Create: `scripts/game/event/shop/shop_event_view.gd` — 商店视图控制器，渲染商品、金币、售罄状态和提示，并发出购买/关闭请求。
- Create: `scripts/game/event/treasure/treasure_event_view.gd` — 宝藏视图控制器，渲染两张卡牌/金币奖励和提示，并发出领取/关闭请求。
- Modify: `scenes/game/event_shop.tscn` — 为根节点绑定 `ShopEventView` 脚本，默认隐藏面板。
- Modify: `scenes/game/event_treasure.tscn` — 为根节点绑定 `TreasureEventView` 脚本，默认隐藏面板。
- Modify: `scenes/game/game_manager.tscn` — 添加高层级 `CanvasLayer`，实例化两个事件视图。
- Modify: `scripts/game_manager.gd` — 添加 SHOP / TREASURE 路由、resolver 调用、奖励发放和面板生命周期管理。
- Modify: `tests/game_manager_combat_routing_test.gd` — 将旧“商店不处理”断言替换为 UI 路由、购买、宝藏领取和锁定恢复的集成测试。
- Modify: `data/event/content/event_shop_content.tres` — 配置三个可购买的示例卡牌商品。
- Modify: `data/event/content/event_treasure_content.tres` — 配置两张候选卡牌和固定范围的金币奖励。
- Create: `data/event/events/forest_trader_event.tres` — SHOP 类型事件模板。
- Create: `data/event/events/ancient_cache_treasure_event.tres` — TREASURE 类型事件模板。
- Modify: `data/event/event_lib.tres` — 将示例商店和宝藏事件加入初始事件生成表。

### Task 1: 写入失败的 UI 路由测试

**Files:**
- Modify: `tests/game_manager_combat_routing_test.gd`

**Interfaces:**
- Consumes: `GameManager` 场景、手牌区、棋盘事件、商店/宝藏内容与两个事件视图。
- Produces: 对 SHOP、TREASURE 路由及成功/失败交互锁生命周期的可执行回归覆盖。

- [ ] **Step 1: 替换旧商店忽略测试**

将 `_test_shop_event_is_ignored_by_combat_routing` 替换为：构造包含一件 `ShopItemData`（价格 5）的 SHOP 事件，放置卡牌使其重叠，断言 `ShopEventView.visible == true`、`TreasureEventView.visible == false`、不发出 `combat_resolved`、`DragLayer` 被锁定、`GoldLabel` 显示当前金币。

- [ ] **Step 2: 添加商店购买测试**

在已打开商店中触发第一个 `ActionButton` 的 `pressed` 信号，断言玩家金币减少 5、商品 `sold_flags[0]` 为真、手牌和 `cards_inst` 各增加 1、按钮不可用且文本为“已售罄”、商店保持显示与锁定。随后触发 `CloseButton`，断言事件未解决、面板隐藏且探索解锁。

- [ ] **Step 3: 添加宝藏领取测试**

构造奖励池包含两张卡且金币范围固定为 7 的 TREASURE 事件，触发后断言 `TreasureEventView` 显示且生成三个选项。触发第一个领取按钮，断言事件解决、手牌和 `cards_inst` 各增加 1、面板隐藏、棋盘事件显示刷新且探索解锁。

- [ ] **Step 4: 运行测试确认失败**

Run:

```powershell
& 'D:\InstallPath\godot\Godot_v4.7-stable_win64_console.exe' --headless --path . --script tests/game_manager_combat_routing_test.gd
```

Expected: FAIL，因为 `GameManager` 还没有两个事件视图和相应路由。

### Task 2: 实现无业务副作用的事件视图控制器

**Files:**
- Create: `scripts/game/event/shop/shop_event_view.gd`
- Create: `scripts/game/event/treasure/treasure_event_view.gd`
- Modify: `scenes/game/event_shop.tscn`
- Modify: `scenes/game/event_treasure.tscn`

**Interfaces:**
- `ShopEventView.show_event(instance: EventInstance, player: PlayerData) -> void`
- `ShopEventView.show_message(message: String, is_error: bool = false) -> void`
- `ShopEventView` signals: `purchase_requested(item_index: int)`、`close_requested()`。
- `TreasureEventView.show_event(instance: EventInstance, options: Array[TreasureRewardOption]) -> void`
- `TreasureEventView.show_message(message: String, is_error: bool = false) -> void`
- `TreasureEventView` signals: `reward_requested(option_index: int)`、`close_requested()`。

- [ ] **Step 1: 为两张场景绑定脚本并默认隐藏**

给根节点增加 `script`，并设置 `visible = false`；保留现有稳定节点和按钮名称。

- [ ] **Step 2: 实现商店渲染**

`show_event` 读取 `ShopEventContent.items` 与 `ShopRuntimeState.sold_flags`。每个有效商品槽调用 `CardPreview.set_value(CardInstance.new(item.card_data))`，显示“卡牌名 · 价格：N 金币”，售罄时禁用按钮并显示“已售罄”；无效/缺失商品槽隐藏。更新 `GoldLabel`，并由根节点显示面板。

- [ ] **Step 3: 实现宝藏渲染**

`show_event` 按 `TreasureRewardOption.Kind` 显示 `CardPreview` 或 `GoldRewardPreview`，卡牌使用临时 `CardInstance`，金币显示“+N 金币”。隐藏未使用槽，按钮文案为“领取”。

- [ ] **Step 4: 连接本地按钮为意图信号**

每个槽的 `ActionButton` 只发射包含索引的请求信号，关闭按钮只发射关闭信号；不触及 resolver 或玩家数据。

### Task 3: 在 GameManager 中编排事件操作

**Files:**
- Modify: `scenes/game/game_manager.tscn`
- Modify: `scripts/game_manager.gd`

**Interfaces:**
- Consumes: `ShopEventView`、`TreasureEventView`、`ShopEventResolver.purchase_item`、`TreasureEventResolver.ensure_options` / `claim_reward`、`HandArea.add_card`。
- Produces: 在同一 `_on_board_event_triggered` 入口中处理 SHOP、TREASURE、MONSTER、BOSS 的显式路由。

- [ ] **Step 1: 将两个视图加入 CanvasLayer**

在 `GameManager` 场景中加入 `EventModalLayer: CanvasLayer`（高于棋盘），在其下实例化 `ShopEventView` 和 `TreasureEventView` 场景。`GameManager` 添加强类型 `@onready` 引用。

- [ ] **Step 2: 连接视图意图**

在 `_ready` 防重复连接 `purchase_requested`、`reward_requested` 和两个 `close_requested`，并初始化一个 `RandomNumberGenerator` 用于宝藏选项生成。

- [ ] **Step 3: 扩展触发入口为显式事件路由**

保留早期防卫条件后，先将 `_active_event` 设为当前实例并锁定交互；`match instance.get_event_type()`：SHOP 打开商店、TREASURE 调用 `ensure_options` 后打开宝藏、MONSTER/BOSS 执行既有遭遇战，未知类型则关闭本次交互。避免 SHOP / TREASURE 进入战斗流程。

- [ ] **Step 4: 实现安全发卡与购买回调**

在调用 shop resolver 前检查当前手牌容量及可创建性；成功后用 `CardManager.create_card_entity(CardInstance.new(card_data))` 创建实体，设置 `drag_layer`、加入 `HandArea`、同步 `cards_inst` 与 `card_entities`。成功购买后刷新商店视图；失败时用 `EventResolutionResult.Failure` 映射为中文提示，不关闭面板。

- [ ] **Step 5: 实现宝藏领取回调与关闭**

调用 treasure resolver，成功后若存在 `granted_card` 则按同一发卡流程加入手牌；刷新事件节点、隐藏视图并解锁。金币奖励跳过手牌容量且不创建卡牌。失败时显示提示并保持面板开启。

- [ ] **Step 6: 实现关闭回调**

关闭当前 SHOP / TREASURE 面板但不解决事件，清空 `_active_event` 并恢复 `DragLayer`，除非探索已失败。

### Task 4: 提供可在实际棋盘生成的示例事件

**Files:**
- Modify: `data/event/content/event_shop_content.tres`
- Modify: `data/event/content/event_treasure_content.tres`
- Create: `data/event/events/forest_trader_event.tres`
- Create: `data/event/events/ancient_cache_treasure_event.tres`
- Modify: `data/event/event_lib.tres`

**Interfaces:**
- Consumes: 已有卡牌资源 `ThornHeavyBlade.tres`、`LayeredWoodenRoundShield.tres`、`ClearSpringWoodVial.tres`。
- Produces: 初始棋盘可生成一个 SHOP 和一个 TREASURE 事件，且两个事件提供可渲染和可结算的选项。

- [ ] **Step 1: 配置商店内容**

`event_shop_content.tres` 配置三项商品：圆盾（8 金币）、清泉木瓶（12 金币）、荆棘重刃（16 金币）。

- [ ] **Step 2: 配置宝藏内容**

`event_treasure_content.tres` 设置候选卡为圆盾与荆棘重刃，金币范围为 `Vector2i(20, 20)`，保证首版宝藏稳定显示两张卡和一项金币。

- [ ] **Step 3: 新建事件模板并注册**

创建 `forest_trader_event.tres`（`event_type = SHOP`）和 `ancient_cache_treasure_event.tres`（`event_type = TREASURE`），在 `event_lib.tres` 中各注册一个 `EventEntry`，`max_count = 1`。

### Task 5: 验证与提交

**Files:**
- Verify: 所有上述文件。

- [ ] **Step 1: 运行定向 GameManager 路由测试**

```powershell
& 'D:\InstallPath\godot\Godot_v4.7-stable_win64_console.exe' --headless --path . --script tests/game_manager_combat_routing_test.gd
```

Expected: PASS，退出码 0。

- [ ] **Step 2: 运行事件模型与事件 UI 场景测试**

```powershell
& 'D:\InstallPath\godot\Godot_v4.7-stable_win64_console.exe' --headless --path . --script tests/event_runtime_test.gd
& 'D:\InstallPath\godot\Godot_v4.7-stable_win64_console.exe' --headless --path . --script tests/event_ui_scene_test.gd
```

Expected: PASS，退出码 0。

- [ ] **Step 3: 运行 Godot 编辑器解析检查**

```powershell
& 'D:\InstallPath\godot\Godot_v4.7-stable_win64_console.exe' --headless --path . --editor --quit
```

Expected: 退出码 0，且不包含新增场景、脚本或资源的解析错误。

- [ ] **Step 4: 审查并提交**

```powershell
git diff --check
git status --short
git add scripts/game_manager.gd scenes/game/game_manager.tscn scenes/game/event_shop.tscn scenes/game/event_treasure.tscn scripts/game/event/shop/shop_event_view.gd scripts/game/event/treasure/treasure_event_view.gd tests/game_manager_combat_routing_test.gd data/event/content/event_shop_content.tres data/event/content/event_treasure_content.tres data/event/events/forest_trader_event.tres data/event/events/ancient_cache_treasure_event.tres data/event/event_lib.tres docs/superpowers/plans/2026-08-01-event-ui-integration.md
git commit -m "feat: integrate shop and treasure event UI"
```
