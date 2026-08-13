class_name DraggerLayer
extends Node

## Detection-only helper for the new Card model.
## Card owns drag state and movement; the scene decides how to transfer a Card.
var _registered_zones: Array[CardZone] = []
var dragging_card:Card

func register_zone(zone: CardZone) -> void:
	if zone != null and zone not in _registered_zones:
		_registered_zones.append(zone)


func unregister_zone(zone: CardZone) -> void:
	_registered_zones.erase(zone)


func get_zone_at(global_point: Vector2) -> CardZone:
	for zone in _registered_zones:
		if is_instance_valid(zone) and zone.contains_global_point(global_point):
			return zone
	return null


func get_registered_zones() -> Array[CardZone]:
	var valid_zones: Array[CardZone] = []
	for zone in _registered_zones:
		if is_instance_valid(zone):
			valid_zones.append(zone)
	return valid_zones
	
	
func start_drag(card:Card)->void:
	dragging_card = card
	
func end_drag(card:Card)->void:
	var zone = get_zone_at(card.global_position)
	if zone!= null:
		if dragging_card.cur_zone:
			dragging_card.cur_zone.remove_card(dragging_card)
		zone.add_card(dragging_card)
	dragging_card = null
