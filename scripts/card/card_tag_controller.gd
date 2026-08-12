class_name CardTagController
extends Node

## Owns combat stat badge construction and placement. The anchor stays top-level
## so badges remain upright while the card itself rotates.

const STAT_TAG_SCENES := {
	"damage": preload("res://scenes/card_view/stat_tags/card_stat_tag_damage.tscn"),
	"guard": preload("res://scenes/card_view/stat_tags/card_stat_tag_guard.tscn"),
}

var _card
var _anchor: Control
var _container: HBoxContainer


func configure(card, anchor: Control, container: HBoxContainer) -> void:
	_card = card
	_anchor = anchor
	_container = container
	if _anchor != null:
		_anchor.z_index = RenderPriority.CARD_COMBAT_TAG


func refresh(instance: CardInstance) -> void:
	if _container == null:
		return

	for child in _container.get_children():
		child.queue_free()

	if instance == null or instance.card_data == null:
		return

	var stat_entries := [
		{"scene": STAT_TAG_SCENES["damage"], "value": instance.current_points},
		{"scene": STAT_TAG_SCENES["guard"], "value": instance.current_armor},
	]
	for entry in stat_entries:
		var value: int = entry["value"]
		if value <= 0:
			continue
		var tag := (entry["scene"] as PackedScene).instantiate() as Control
		(tag.get_node("ValueLabel") as Label).text = str(value)
		_container.add_child(tag)

	position()


func position() -> void:
	if _card == null or _anchor == null or _container == null:
		return

	var tag_size := _container.get_combined_minimum_size()
	_anchor.size = tag_size
	_container.size = tag_size
	var card_rect := LayoutConfig.card_view_rect(LayoutConfig.CELL_SIZE)
	var global_bottom_center: Vector2 = _global_bottom_edge_center(card_rect) + Vector2(0.0, 2.0)
	_anchor.rotation = 0.0
	_anchor.global_position = global_bottom_center - tag_size * 0.5


func _global_bottom_edge_center(card_rect: Rect2) -> Vector2:
	var global_corners: Array[Vector2] = [
		_card.to_global(card_rect.position),
		_card.to_global(card_rect.position + Vector2(card_rect.size.x, 0.0)),
		_card.to_global(card_rect.position + card_rect.size),
		_card.to_global(card_rect.position + Vector2(0.0, card_rect.size.y)),
	]
	var global_bottom_center: Vector2 = (global_corners[0] + global_corners[1]) * 0.5
	for corner_index in range(global_corners.size()):
		var next_corner_index := (corner_index + 1) % global_corners.size()
		var candidate_center: Vector2 = (global_corners[corner_index] + global_corners[next_corner_index]) * 0.5
		if candidate_center.y > global_bottom_center.y:
			global_bottom_center = candidate_center
	return global_bottom_center
