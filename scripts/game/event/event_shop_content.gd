class_name EventShopContent
extends Resource

## 商店商品列表
var items: Array[ShopItem] = []
## 基础刷新价格（每次刷新递增）
var refresh_price: int = 1
## 最大同时上架数
var max_items: int = 3

var _refresh_count: int = 0


func add_item(card: CardData, cost: int) -> void:
	items.append(ShopItem.create(card, cost))


func get_item(index: int) -> ShopItem:
	if index < 0 or index >= items.size():
		return null
	return items[index]


func buy_item(index: int) -> ShopItem:
	var item = get_item(index)
	if item and not item.sold:
		item.sold = true
		return item
	return null


func get_current_refresh_price() -> int:
	return refresh_price * (1 + _refresh_count)


func refresh():
	_refresh_count += 1
	for item in items:
		item.sold = false


func has_available() -> bool:
	for item in items:
		if not item.sold:
			return true
	return false


func available_count() -> int:
	var count := 0
	for item in items:
		if not item.sold:
			count += 1
	return count
