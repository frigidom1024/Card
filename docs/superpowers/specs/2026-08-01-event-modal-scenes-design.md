# 商店与宝藏事件面板设计

**日期：** 2026-08-01  
**状态：** 已确认视觉方向与卡牌视图复用方式，待实现

## 目标

为棋盘上的商店与宝藏事件提供首版 UI 场景资源。场景只负责展示结构与视觉层级，不负责事件触发、选项数据填充、购买、奖励结算或关闭流程。

## 视觉方向

采用 **通用卡牌橱窗** 布局：全屏半透明遮罩之上放置居中的事件面板，面板中横向排列三个选项卡槽。该布局可在小成本下清晰呈现“从多个卡牌/奖励中选择”的玩法，并为后续动画和交互逻辑预留稳定节点。

## 卡牌视图复用

卡牌商品与卡牌奖励**必须直接复用** `scenes/card_view/card_view.tscn`，不在事件 UI 中复制卡牌战斗属性、颜色或标签渲染规则。

- 每个卡牌槽位实例化一个 `CardView`，节点名为 `CardPreview`。
- 后续 UI 脚本为展示用 `CardInstance` 调用 `CardPreview.set_value(...)`。
- 该 `CardInstance` 仅用于显示 `ShopItemData.card_data` 或 `TreasureRewardOption.card_data`，不加入玩家卡组、手牌或棋盘。
- `CardView` 下方保留事件专属信息：商店显示价格与购买按钮；宝藏显示领取按钮。
- 金币奖励不是卡牌，不实例化 `CardView`；使用独立的 `GoldRewardPreview` 占位节点。

## 场景资源

### `scenes/game/event_shop.tscn`

- 全屏 `Control` 根节点与深色遮罩。
- 蓝色主题的居中面板。
- 标题区：事件名称、玩家金币显示、关闭按钮占位。
- 横向三个商品卡槽；每个槽位内以 `CardPreview` 直接呈现现有 `CardView`，下方显示价格与购买按钮占位。
- 底部提示区，作为以后放置购买失败提示、售罄状态或操作说明的稳定位置。

### `scenes/game/event_treasure.tscn`

- 与商店一致的全屏遮罩、面板尺寸和三槽位骨架。
- 琥珀 / 金色主题，顶部可显示宝藏名称与“选择一项奖励”说明。
- 横向三个奖励卡槽；卡牌奖励槽位内使用 `CardPreview` 直接呈现 `CardView`，金币奖励槽位使用 `GoldRewardPreview`。
- 每个槽位下方保留领取按钮占位。
- 底部提示区与商店保持相同职责。

## 节点约定

两个场景将保持以下稳定命名，供后续脚本和事件处理接入：

- `Overlay`
- `Panel`
- `Header`
- `TitleLabel`
- `SubtitleLabel`
- `GoldLabel`（仅商店）
- `CloseButton`
- `OfferContainer`
- `OfferSlot1`、`OfferSlot2`、`OfferSlot3`
- 卡牌槽内：`CardPreview`（`card_view.tscn` 的实例）、`PriceOrRewardLabel`、`ActionButton`
- 金币槽内：`GoldRewardPreview`、`PriceOrRewardLabel`、`ActionButton`
- `HintLabel`

## 交互边界

本阶段所有按钮仅作为场景资源中的视觉占位，不连接业务信号。后续由 `GameManager` 的事件类型路由打开对应面板，再由 UI 脚本创建展示专用 `CardInstance`、填充 `CardView`，并调用商店购买或宝藏领取接口。

## 验收标准

1. 两个场景在 Godot 编辑器中可独立打开，无解析错误。
2. 1920×1080 下居中显示，遮罩覆盖全屏。
3. 面板包含三个清晰的可选槽位，商店与宝藏主题可明显区分。
4. 商店的三个商品槽均直接实例化 `card_view.tscn`；宝藏的卡牌奖励槽直接实例化 `card_view.tscn`。
5. 不新增事件结算逻辑，不修改 `GameManager`。
6. 所有节点名称符合上述稳定命名约定。
