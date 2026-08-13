extends SceneTree

const CARD_SCENE := preload("res://scenes/card/card.tscn")

var _failures := 0


class AcceptingZone:
	extends CardZone

	var updated_card: Card

	func can_trans_to_target(_card: Card) -> bool:
		return true

	func update_drag(card: Card) -> void:
		updated_card = card


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var dragger := DraggerLayer.new()
	root.add_child(dragger)

	var card := CARD_SCENE.instantiate() as Card
	card.set_anchors_preset(Control.PRESET_TOP_LEFT)
	card.position = Vector2(240.0, 180.0)
	root.add_child(card)
	await process_frame

	card.pivot_offset = card.size * 0.5
	card.rotation = PI * 0.5
	var transformed_center := card.get_global_transform_with_canvas() * (card.size * 0.5)
	var legacy_center := card.global_position + card.size * 0.5

	var target := AcceptingZone.new()
	target.set_anchors_preset(Control.PRESET_TOP_LEFT)
	target.position = transformed_center - Vector2(4.0, 4.0)
	target.size = Vector2(8.0, 8.0)
	root.add_child(target)
	dragger.register_zone(target)
	await process_frame

	_expect(transformed_center.distance_to(legacy_center) > 1.0, "the rotated-card fixture separates the transformed center from the legacy center")
	_expect(target.contains_global_point(transformed_center), "the target covers the rotated card's transformed center")
	_expect(not target.contains_global_point(legacy_center), "the target excludes the legacy untransformed center")

	dragger.start_drag(card)
	dragger.update_drag(card)
	_expect(target.updated_card == card, "DraggerLayer detects a target under the transformed center of a rotated card")

	card.free()
	target.free()
	dragger.free()
	quit(1 if _failures > 0 else 0)


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error(message)
