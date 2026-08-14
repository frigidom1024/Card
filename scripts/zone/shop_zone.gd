## 商店商品交互区域组件
##
## 负责管理商店商品槽位与购买拖拽事务。
## 包括：
## - 商品卡牌的稳定槽位与所有权查询
## - 购买前验证委托与商品拖拽快照
## - 购买成功后的槽位清空和 product_purchased 通知
## - 商品卡牌的 SHOP 区域状态同步与显示布局
##
## 不负责：
## - 商品价格、金币扣除或替代商品生成
## - 商店刷新随机算法
## - 玩家卡牌实例的持久化注册
## - 跨区域拖拽来源解析与目标提交顺序
##
## 使用方式：
## 由 Shop 注入购买验证器、商品卡牌和 DraggerLayer；拖拽流程由 DraggerLayer
## 调用本区域协议，购买成功后由 Shop 监听 product_purchased。
##
## 依赖：
## CardZone：提供区域基础拖拽协议。
## Card：提供商品卡牌视图。
## CardInstance：保存商品的 SHOP 状态。
## DraggerLayer：协调商品卡牌跨区域拖拽。

class_name ShopZone
extends CardZone

signal product_purchased(card: Card, card_inst: CardInstance, slot_index: int)

@export_range(1, 3, 1) var max_products: int = 3
@export var card_gap: float = 12.0
@export var fallback_card_size := Vector2(84.0, 154.0)

var _products: Array[Card] = []
var _purchase_validator: Callable
var _dragging_product: Card
var _drag_slot := -1
var _drag_original_target := Vector2.ZERO
var _layout_queued := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_collect_initial_products()
	if not resized.is_connected(_schedule_layout):
		resized.connect(_schedule_layout)
	_schedule_layout()


func set_purchase_validator(validator: Callable) -> void:
	_purchase_validator = validator


func set_products(cards: Array[Card]) -> void:
	var accepted: Array[Card] = []
	for card in cards:
		if not _is_valid_bound_card(card) or accepted.has(card):
			continue
		if accepted.size() >= max_products:
			break
		accepted.append(card)

	for current in _products:
		if is_instance_valid(current) and current not in accepted and current.get_card_inst() != null and current.get_card_inst().cur_zone == CardInstance.ZONE.SHOP:
			current.get_card_inst().cur_zone = CardInstance.ZONE.DISCARD
			current.refresh_display()

	_products.clear()
	for index in range(max_products):
		_products.append(accepted[index] if index < accepted.size() else null)

	for card in accepted:
		_adopt_product(card, true)
	_schedule_layout()


func replace_product(slot_index: int, card: Card, keep_global_position: bool = false) -> bool:
	_ensure_slots()
	if slot_index < 0 or slot_index >= max_products or not _is_valid_bound_card(card):
		return false
	var existing := _products[slot_index]
	if is_instance_valid(existing) and existing != card and existing.get_card_inst() != null and existing.get_card_inst().cur_zone == CardInstance.ZONE.SHOP:
		existing.get_card_inst().cur_zone = CardInstance.ZONE.DISCARD
		existing.refresh_display()
	_products[slot_index] = card
	_adopt_product(card, keep_global_position)
	_schedule_layout()
	return true


func clear_products(queue_free_cards: bool = false) -> void:
	for card in _products:
		if not is_instance_valid(card):
			continue
		if card.get_card_inst() != null and card.get_card_inst().cur_zone == CardInstance.ZONE.SHOP:
			card.get_card_inst().cur_zone = CardInstance.ZONE.DISCARD
			card.refresh_display()
		if queue_free_cards:
			card.queue_free()
		else:
			card.hide()
	_products.clear()
	_clear_drag_state()
	_schedule_layout()


func add_card(card: Card, keep_global_position: bool = true) -> bool:
	_ensure_slots()
	if not _is_valid_bound_card(card):
		return false
	var existing_slot := get_product_slot(card)
	if existing_slot != -1:
		_adopt_product(card, keep_global_position)
		return true
	var empty_slot := _products.find(null)
	if empty_slot == -1:
		return false
	return replace_product(empty_slot, card, keep_global_position)


func remove_card(card: Card) -> bool:
	var slot_index := get_product_slot(card)
	if slot_index == -1:
		return false
	_products[slot_index] = null
	if card.get_card_inst() != null and card.get_card_inst().cur_zone == CardInstance.ZONE.SHOP:
		card.get_card_inst().cur_zone = CardInstance.ZONE.DISCARD
		card.refresh_display()
	_schedule_layout()
	return true


func get_cards() -> Array[Card]:
	var cards: Array[Card] = []
	for card in _products:
		if is_instance_valid(card):
			cards.append(card)
	return cards


func get_products() -> Array[Card]:
	_prune_products()
	return _products.duplicate()


func get_product(slot_index: int) -> Card:
	_prune_products()
	if slot_index < 0 or slot_index >= _products.size():
		return null
	return _products[slot_index]


func get_product_slot(card: Card) -> int:
	if card == null:
		return -1
	_prune_products()
	return _products.find(card)


func has_product(card: Card) -> bool:
	return get_product_slot(card) != -1


func owns_card(card: Card) -> bool:
	return card != null and _products.has(card)


func has_active_product_drag() -> bool:
	return is_instance_valid(_dragging_product)


func get_dragging_product() -> Card:
	return _dragging_product if is_instance_valid(_dragging_product) else null


func can_trans_from_source(card: Card) -> bool:
	var slot_index := get_product_slot(card)
	if slot_index == -1 or card.get_card_inst() == null or not _purchase_validator.is_valid():
		return false
	return bool(_purchase_validator.call(card, card.get_card_inst(), slot_index))


func can_trans_to_target(_card: Card) -> bool:
	return false


func start_drag(card: Card) -> void:
	var slot_index := get_product_slot(card)
	if slot_index == -1:
		return
	_dragging_product = card
	_drag_slot = slot_index
	_drag_original_target = card.target_position
	_products[slot_index] = null
	_schedule_layout()


func drag_end_source(card: Card, ok: bool) -> bool:
	if card == null or card != _dragging_product or _drag_slot < 0:
		return false
	var slot_index := _drag_slot
	var card_inst := card.get_card_inst()
	if ok:
		_clear_drag_state()
		product_purchased.emit(card, card_inst, slot_index)
		return true

	card.target_position = _drag_original_target
	if slot_index < _products.size() and _products[slot_index] == null:
		_products[slot_index] = card
	_set_shop_state(card)
	_clear_drag_state()
	_schedule_layout()
	return true


func _collect_initial_products() -> void:
	_products.clear()
	for child in get_children():
		if child is Card and _products.size() < max_products:
			_products.append(child as Card)
			_set_shop_state(child as Card)
	_ensure_slots()


func _adopt_product(card: Card, keep_global_position: bool) -> void:
	if card.get_parent() == null:
		add_child(card)
	elif card.get_parent() != self:
		card.reparent(self, keep_global_position)
	_set_shop_state(card)
	card.show()


func _is_valid_bound_card(card: Card) -> bool:
	return card != null and is_instance_valid(card) and card.get_card_inst() != null


func _set_shop_state(card: Card) -> void:
	if card == null or card.get_card_inst() == null:
		return
	var card_inst := card.get_card_inst()
	card_inst.cur_zone = CardInstance.ZONE.SHOP
	card_inst.battlefield_pos = Vector2i(-1, -1)
	card_inst.direction = 0
	card.rotation = 0.0
	card.refresh_display()


func _ensure_slots() -> void:
	while _products.size() < max_products:
		_products.append(null)
	while _products.size() > max_products:
		_products.pop_back()


func _prune_products() -> void:
	_ensure_slots()
	for index in range(_products.size()):
		if _products[index] != null and not is_instance_valid(_products[index]):
			_products[index] = null


func _clear_drag_state() -> void:
	_dragging_product = null
	_drag_slot = -1
	_drag_original_target = Vector2.ZERO


func _schedule_layout() -> void:
	if _layout_queued:
		return
	_layout_queued = true
	call_deferred("_layout_products")


func _layout_products() -> void:
	_layout_queued = false
	_prune_products()
	var visible_cards := get_cards()
	if visible_cards.is_empty():
		return

	var widths: Array[float] = []
	var total_width := 0.0
	var max_height := 0.0
	for card in visible_cards:
		var card_size := card.size
		if card_size.x <= 0.0:
			card_size.x = fallback_card_size.x
		if card_size.y <= 0.0:
			card_size.y = fallback_card_size.y
		widths.append(card_size.x)
		total_width += card_size.x
		max_height = maxf(max_height, card_size.y)

	var gap := card_gap
	if visible_cards.size() > 1:
		gap = maxf(0.0, minf(card_gap, (size.x - total_width) / float(visible_cards.size() - 1)))
		total_width += gap * float(visible_cards.size() - 1)
	var cursor_x := (size.x - total_width) * 0.5
	for index in range(visible_cards.size()):
		var card := visible_cards[index]
		var target := Vector2(cursor_x, (size.y - maxf(card.size.y, fallback_card_size.y if card.size.y <= 0.0 else card.size.y)) * 0.5)
		target.y+=20
		card.target_position = target
		cursor_x += widths[index] + gap
