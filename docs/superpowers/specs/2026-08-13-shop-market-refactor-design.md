# Shop / ShopZone 市场重构设计

**日期：** 2026-08-13  
**状态：** 已批准，执行中

## 目标

把新卡牌架构下的商店职责从 `persistent_market` 迁移到 `shop.tscn` 与 `shop_zone.tscn`：

- `Shop` 负责商店库存、价格、购买结算、补货、刷新以及拖拽层接线。
- `ShopZone` 负责固定商品槽位、布局和拖拽购买事务。
- 每张可见商品 `Card` 必须绑定并始终携带同一个 `CardInstance`。
- 成功购买后，目标区域接收的正是商品展示使用的 `Card` 和 `CardInstance`，不得重新创建实例。

本阶段不替换旧 `GameManager` 中的 `persistent_market`，也不迁移旧 `CardEntity`/`HandArea` 体系。

## 移除内容

- 删除/不再提供 `purchase_requested`、`refresh_requested`、`reclaim_requested` 等外部协调信号。
- 删除全部 reclaim（回收）逻辑和 UI 职责。
- 刷新、购买和补货均由 `Shop` 内部闭环完成。

## Card 精确实例绑定

`Card` 新增：

```gdscript
var card_inst: CardInstance
func bind_card_inst(value: CardInstance) -> void
func get_card_inst() -> CardInstance
```

`CardInstance.card_data` 是商品数据的唯一来源。购买过程中不调用会新建实例的 `grant_to_hand(card_data)`。

## ShopZone

### 职责

- 按固定槽位持有商品卡牌并负责居中布局。
- 作为拖拽源进行购买预校验。
- 失败时恢复原商品和槽位。
- 目标区域提交成功后，才从自身槽位删除商品并通知 `Shop`。
- 不接受任何卡牌拖入。

### 对外 API

```gdscript
signal product_purchased(card: Card, card_inst: CardInstance, slot_index: int)

func set_purchase_validator(validator: Callable) -> void
func set_products(cards: Array[Card]) -> void
func replace_product(slot_index: int, card: Card, keep_global_position: bool = false) -> bool
func clear_products(queue_free_cards: bool = false) -> void

func add_card(card: Card, keep_global_position: bool = true) -> bool
func remove_card(card: Card) -> bool
func get_cards() -> Array[Card]

func get_products() -> Array[Card]
func get_product(slot_index: int) -> Card
func get_product_slot(card: Card) -> int
func has_product(card: Card) -> bool
func has_active_product_drag() -> bool
func get_dragging_product() -> Card
```

购买校验器签名：

```gdscript
func validator(card: Card, card_inst: CardInstance, slot_index: int) -> bool
```

### 事务顺序

`DraggerLayer.end_drag()` 先调用目标 `drag_end_target(card, true)`，目标提交成功后再调用源 `drag_end_source(card, true)`。因此：

- `product_purchased` 只能从成功的 `drag_end_source` 发出。
- 成功时只删除 ShopZone 内部槽位引用，不能释放、重新父子化或清空目标区域已经设置的 `cur_zone`。
- 失败时保留槽位并恢复原吸附位置。

## Shop

### 依赖与状态

`Shop` 持有：

- `CardLibrary`
- `PlayerData`
- `RunCardService`
- `MarketPricingService`
- `RandomNumberGenerator`
- 可选 `RunProgressionService`
- `Array[CardInstance]` 商品库存
- 当前 `DraggerLayer`

### 对外 API

```gdscript
func configure(
    card_library: CardLibrary,
    player: PlayerData,
    card_service: RunCardService,
    pricing: MarketPricingService,
    rng: RandomNumberGenerator,
    progression: RunProgressionService = null
) -> bool

func set_drag_layer(value: DraggerLayer) -> void
func refresh_shop() -> bool
func refresh_display() -> void
func get_offer(slot_index: int) -> CardInstance
func get_offers() -> Array[CardInstance]
func get_offer_data(slot_index: int) -> CardData
func get_offer_slot_for_card(card: Card) -> int
```

`Shop` 不需要对外业务信号。

### 初始化与刷新

- `configure()` 清理 `shop_zone.tscn` 中的占位卡牌，建立验证器和内部信号连接，并免费生成首批商品。
- 抽取商品时排除 ROOT 卡；有进度服务时遵守可用性和稀有度权重；尽可能避免同批重复。
- 刷新前检查配置状态、活动拖拽和金币。
- 只有成功构造完整新库存后才扣除刷新费用并替换旧库存。
- `CostCoin` 显示当前刷新费用，刷新按钮根据金币与拖拽状态启用/禁用。

### 购买与补货

- 预校验确认槽位、可见 `Card`、绑定实例和库存实例均为同一对象，并检查金币。
- 目标区域提交成功后扣款，将精确 `CardInstance` 注册到 `RunCardService`，然后只补充被购买槽位。
- 新补货卡牌也立即绑定当前 `DraggerLayer`。
- 若注册异常，不再复制实例；该异常作为内部一致性错误报告。

## DraggerLayer 接线

`set_drag_layer()`：

1. 从旧层注销 `ShopZone`。
2. 在新层注册 `ShopZone`。
3. 把所有当前商品 `Card` 绑定到新层。
4. 后续补货卡也自动绑定该层。

`Card` 在拖动更新位置时必须调用 `drag_layer.update_drag(self)`，否则目标预览/命中不会更新。

## RunCardService 兼容边界

增加一个精确实例注册 API，直接登记已存在的 `CardInstance`，不创建副本。新 `Card` 视图不塞入旧的 `Array[CardEntity]`。旧 `CardEntity` 流程保持不变。

## 错误处理与所有权

- Shop 拥有尚未购买的商品卡牌生命周期。
- 购买成功后，目标 Zone 拥有可见 Card 的生命周期；Shop 不释放它。
- ShopZone 只持有槽位引用，不拥有已成功迁移的卡牌。
- 空依赖、空实例、身份不匹配和槽位越界都返回 `false`/`null`，不执行部分结算。
