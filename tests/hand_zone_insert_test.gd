extends SceneTree

const HAND_ZONE_SCENE := preload("res://scenes/zone/handzone.tscn")
const CARD_SCENE := preload("res://scenes/card/card.tscn")

var _failures := 0

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var zone := HAND_ZONE_SCENE.instantiate() as HandZone
	zone.set_anchors_preset(Control.PRESET_TOP_LEFT)
	zone.size = Vector2(500.0, 220.0)
	zone.float_amplitude = 0.0
	root.add_child(zone)

	var first := CARD_SCENE.instantiate() as Card
	var second := CARD_SCENE.instantiate() as Card
	var third := CARD_SCENE.instantiate() as Card
	zone.add_card(first)
	zone.add_card(second)
	zone.add_card(third)
	await process_frame

	var incoming := CARD_SCENE.instantiate() as Card
	root.add_child(incoming)
	incoming.global_position = zone.global_position + Vector2(20.0, 0.0)
	zone.add_card(incoming)
	_expect(zone.cards[0] == incoming, "a Card dropped on the left is inserted at the beginning")

	var middle := CARD_SCENE.instantiate() as Card
	root.add_child(middle)
	middle.global_position = zone.global_position + Vector2(second.target_position.x + second.size.x * 0.5, 0.0)
	zone.add_card(middle)
	var middle_index := zone.cards.find(middle)
	_expect(middle_index > 0 and middle_index < zone.cards.size() - 1, "a Card dropped in the hand middle is inserted between Cards")

	zone.free()
	quit(1 if _failures > 0 else 0)

func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error(message)