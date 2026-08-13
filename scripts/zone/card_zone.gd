class_name CardZone
extends Control




func contains_global_point(global_point: Vector2) -> bool:
	return get_global_rect().has_point(global_point)


func in_zone(global_point: Vector2) -> bool:
	return contains_global_point(global_point)


func add_card(card: Card) -> bool:
	return false


func remove_card(card: Card) -> bool:
	return false


func get_cards() -> Array[Card]:
	return []

func get_projected_card() -> Card:
	return null
		
	
