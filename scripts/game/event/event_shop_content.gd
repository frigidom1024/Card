class_name EventShopContent
extends EventContent

const ShopItemDataScript = preload("res://scripts/game/event/shop_item_data.gd")

## 商店商品列表。购买和售罄状态保存在 EventInstance 中。
@export var items: Array[ShopItemDataScript] = []