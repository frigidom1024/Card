class_name ShopEventContent
extends EventContent


## 商店商品列表。购买和售罄状态保存在 ShopRuntimeState 中。
@export var items: Array[ShopItemData] = []


func create_runtime_state() -> ShopRuntimeState:
	return ShopRuntimeState.new()
