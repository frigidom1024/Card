class_name ShopZone
extends Control

## Displays up to three Card-scene product previews without taking ownership of card size or input.
@export_range(1, 3, 1) var max_products: int = 3
@export var card_gap: float = 12.0
@export var fallback_card_size := Vector2(84.0, 154.0)

var _products: Array[Card] = []
var _layout_queued := false
var _updating_products := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_collect_initial_products()
	if not resized.is_connected(_schedule_layout):
		resized.connect(_schedule_layout)
	if not child_entered_tree.is_connected(_on_child_entered_tree):
		child_entered_tree.connect(_on_child_entered_tree)
	if not child_exiting_tree.is_connected(_on_child_exiting_tree):
		child_exiting_tree.connect(_on_child_exiting_tree)
	_schedule_layout()


func set_products(cards: Array[Card]) -> void:
	var accepted: Array[Card] = []
	for card in cards:
		if card == null or not is_instance_valid(card) or accepted.has(card):
			continue
		if accepted.size() >= max_products:
			push_warning("ShopZone only displays %d product cards." % max_products)
			break
		accepted.append(card)

	_updating_products = true
	for child in get_children():
		if child is Card and child not in accepted:
			(child as Card).hide()

	for card in accepted:
		if card.get_parent() != self:
			card.reparent(self, true)
		card.show()
		move_child(card, get_child_count() - 1)

	_products = accepted
	_updating_products = false
	_schedule_layout()


func set_product(slot_index: int, card: Card) -> void:
	if slot_index < 0 or slot_index >= max_products:
		push_error("ShopZone product slot index %d is outside 0..%d." % [slot_index, max_products - 1])
		return
	if card == null or not is_instance_valid(card):
		push_error("ShopZone requires a valid Card product.")
		return
	if slot_index > _products.size():
		push_error("ShopZone product slots must be filled from left to right.")
		return

	var updated := _products.duplicate()
	if slot_index == updated.size():
		updated.append(card)
	else:
		updated[slot_index] = card
	set_products(updated)


func clear_products() -> void:
	for card in _products:
		if is_instance_valid(card):
			card.hide()
	_products.clear()
	_schedule_layout()


func get_products() -> Array[Card]:
	_prune_products()
	return _products.duplicate()


func _collect_initial_products() -> void:
	_products.clear()
	for child in get_children():
		if child is Card and child.visible and _products.size() < max_products:
			_products.append(child as Card)


func _on_child_entered_tree(child: Node) -> void:
	if not _updating_products and child is Card and child.visible and _products.size() < max_products and not _products.has(child):
		_products.append(child as Card)
	_schedule_layout()


func _on_child_exiting_tree(child: Node) -> void:
	if child is Card:
		_products.erase(child as Card)
	_schedule_layout()


func _schedule_layout() -> void:
	if _layout_queued:
		return
	_layout_queued = true
	call_deferred("_layout_products")


func _layout_products() -> void:
	_layout_queued = false
	_prune_products()
	if _products.is_empty():
		return

	var product_sizes: Array[Vector2] = []
	var cards_width := 0.0
	for card in _products:
		var card_size := _layout_size_for(card)
		product_sizes.append(card_size)
		cards_width += card_size.x

	var gap := 0.0
	if _products.size() > 1:
		gap = minf(card_gap, maxf(0.0, (size.x - cards_width) / float(_products.size() - 1)))

	var total_width := cards_width + gap * float(_products.size() - 1)
	var x := (size.x - total_width) * 0.5
	for index in _products.size():
		var card := _products[index]
		var card_size := product_sizes[index]
		card.position = Vector2(x, (size.y - card_size.y) * 0.5)
		x += card_size.x + gap


func _layout_size_for(card: Card) -> Vector2:
	if card.size.x > 0.0 and card.size.y > 0.0:
		return card.size
	return fallback_card_size


func _prune_products() -> void:
	var valid_products: Array[Card] = []
	for card in _products:
		if is_instance_valid(card) and card.get_parent() == self and card.visible:
			valid_products.append(card)
	_products = valid_products
