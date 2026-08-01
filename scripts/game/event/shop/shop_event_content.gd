class_name ShopEventContent
extends EventContent

const ShopItemDataScript = preload("res://scripts/game/event/shop/shop_item_data.gd")
const ShopRuntimeStateScript = preload("res://scripts/game/event/shop/shop_runtime_state.gd")

## 商店商品列表。购买和售罄状态保存在 ShopRuntimeState 中。
@export var items: Array[ShopItemDataScript] = []


func create_runtime_state() -> ShopRuntimeStateScript:
	return ShopRuntimeStateScript.new()