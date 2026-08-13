class_name CardZone
extends Control


func contains_global_point(global_point: Vector2) -> bool:
	return get_global_rect().has_point(global_point)


func in_zone(global_point: Vector2) -> bool:
	return contains_global_point(global_point)


func add_card(card: Card, keep_global_position: bool = true) -> bool:
	return false


func remove_card(card: Card) -> bool:
	return false


func get_cards() -> Array[Card]:
	return []


## Notification to the source zone that a card has started dragging.
func start_drag(card: Card) -> void:
	pass


## Updates this zone's temporary preview while a card is dragged over it.
func update_drag(card: Card) -> void:
	pass


## Whether this zone accepts the dragged card as a target.
func can_trans_to_target(card: Card) -> bool:
	return false


## Whether this zone allows the dragged card to leave as a source.
func can_trans_from_source(card: Card) -> bool:
	return false


## Called on the source zone when the drag ends.
func drag_end_source(card: Card, ok: bool) -> bool:
	return true


## Called on the target zone when the drag ends.
## Returns whether the target accepted and committed the card.
func drag_end_target(card: Card, ok: bool) -> bool:
	return false
