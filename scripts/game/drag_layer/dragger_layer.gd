class_name DraggerLayer
extends Node

## Detection and drag-flow coordinator for the new Card model.
## Card still owns dragging and movement; zones own preview and commit behavior.
var _registered_zones: Array[CardZone] = []
var dragging_card: Card
var _preview_target: CardZone


func register_zone(zone: CardZone) -> void:
	if zone != null and zone not in _registered_zones:
		_registered_zones.append(zone)


func unregister_zone(zone: CardZone) -> void:
	_registered_zones.erase(zone)
	if _preview_target == zone:
		_preview_target = null


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
	_registered_zones = valid_zones
	return valid_zones


func start_drag(card: Card) -> void:
	if card == null:
		return

	dragging_card = card
	_preview_target = null

	var source := card.cur_zone
	if source != null and not source.can_trans_from_source(card):
		dragging_card = null
		return

	if source != null:
		source.start_drag(card)


func update_drag(card: Card) -> void:
	if card == null or card != dragging_card:
		return

	var target := get_zone_at(_get_card_center(card))
	if target != null and not target.can_trans_to_target(card):
		target = null

	if _preview_target != null and _preview_target != target:
		_preview_target.drag_end_target(card, false)
		_preview_target = null

	if target != null:
		target.update_drag(card)
		_preview_target = target
	# The source zone keeps its removal preview while the card is outside a target.


func end_drag(card: Card) -> void:
	if card == null or card != dragging_card:
		return

	# Make sure a release without a final mouse-motion event still gets a preview.
	update_drag(card)

	var source := card.cur_zone
	var target := _preview_target
	var can_trans := (
		target != null
		and target.can_trans_to_target(card)
		and (source == null or source.can_trans_from_source(card))
	)

	var committed := false
	if can_trans:
		# 目标区先提交。BoardZone 等目标可能在释放时发现预览格不可用，
		# 此时必须阻止源区删除卡牌。
		committed = target.drag_end_target(card, true)

	if committed:
		if source != null and source != target:
			source.drag_end_source(card, true)
	else:
		if target != null:
			target.drag_end_target(card, false)
		if source != null:
			source.drag_end_source(card, false)

	dragging_card = null
	_preview_target = null


func _get_card_center(card: Card) -> Vector2:
	return card.global_position + card.size * 0.5
