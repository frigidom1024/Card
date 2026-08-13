# ShopZone 三列商品卡展示设计

**日期：** 2026-08-13  
**状态：** 待用户审阅  
**范围：** `scenes/zone/shop_zone.tscn` 使用 `scenes/card/card.tscn` 展示最多三张商品卡。

## 目标

让 `ShopZone` 自行管理一行最多三张商品卡，而不是使用 `HBoxContainer`。每张卡继续使用 `Card` 场景自身的尺寸、悬停动画与 `gui_input`；商品区仅计算并写入卡牌位置。

## 不在范围内

- 不接入正式事件商店的 `ShopEventView` / `CardEntity` 系统。
- 不改变卡牌的拖拽规则、购买流程或货币逻辑。
- 不让 `ShopZone` 继承 `CardZone` 的跨区域拖拽协议。

## 场景结构

```text
ShopZone (Control, shop_zone.gd)
├── Card3 (Card)
├── Card (Card)
└── Card2 (Card)
```

移除旧的 `HBoxContainer`。三个商品卡改为 `ShopZone` 的直接子节点，作为编辑器默认展示内容。

## 布局规则

- 最多显示三张 `Card`。
- `ShopZone` 只管理其直接 `Card` 子节点。
- 布局时仅改写 `Card.position`；不改写 `Card.size`、缩放、鼠标过滤或卡牌自身脚本状态。
- 卡牌的真实尺寸来自 `card.size`；若尚未完成布局且尺寸为零，则使用可配置的默认尺寸 `Vector2(84, 154)` 计算位置。
- `card_gap` 为可配置的期望水平间距，默认 `12.0` 像素。
- 整组卡牌在 `ShopZone` 内水平居中，并在可用高度内垂直居中。
- 如果可用宽度无法容纳期望间距，间距可收缩至 `0`；卡牌不缩放。若连卡牌总宽度也无法容纳，仍以整体居中方式保留原尺寸，允许两端超出容器。
- 卡牌顺序由场景树顺序或 `set_products()` 传入数组的顺序决定，从左至右展示。

## 脚本 API

新增 `scripts/zone/shop_zone.gd`：

```gdscript
class_name ShopZone
extends Control

@export var max_products := 3
@export var card_gap := 12.0
@export var fallback_card_size := Vector2(84, 154)

func set_products(cards: Array[Card]) -> void
func set_product(slot_index: int, card: Card) -> void
func clear_products() -> void
func get_products() -> Array[Card]
```

### API 语义

- `set_products(cards)`：接受最多三张卡，按数组顺序成为本节点直接子节点，保留全局位置 reparent 后立即重新布局。当前不在数组中的直接 `Card` 子节点隐藏。
- `set_product(slot_index, card)`：替换指定逻辑槽位的商品卡；无效索引报错并不改动布局。
- `clear_products()`：隐藏全部现有商品卡并清空展示顺序，不释放卡牌实例。
- `get_products()`：按展示顺序返回当前可见商品卡的副本。

脚本在 `_ready()`、`resized`、`child_entered_tree` 与 `child_exiting_tree` 后延迟一次重排，避免尚未获得最终 `size` 时布局错误。

## 输入保证

`ShopZone.mouse_filter` 设为 `MOUSE_FILTER_IGNORE`，不拦截商品卡的 GUI 输入。商品卡根节点 `Card` 是 `Button`，它保留自己的 `gui_input`、悬停与拖拽行为。

## 验收标准

1. 打开 `shop_zone.tscn` 后，场景不再包含 `HBoxContainer`。
2. 三张默认 `Card` 均有非零大小、排列为一行且水平居中。
3. 每张默认商品卡都有可命中的 GUI 区域，并能收到自身的 `gui_input`。
4. `set_products()` 将一至三张卡以输入顺序横向展示，不改写它们的大小。
5. 调整 `ShopZone.size` 后，商品卡自动重新居中；间距只会缩小到零，不会拉伸/压缩卡牌。
6. 在无头 Godot 中加载场景不会产生脚本或场景解析错误。
