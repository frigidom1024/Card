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

	var first := _make_card()
	var second := _make_card()
	var third := _make_card()
	first.global_position = zone.global_position + Vector2(100.0, 0.0)
	second.global_position = zone.global_position + Vector2(200.0, 0.0)
	third.global_position = zone.global_position + Vector2(300.0, 0.0)
	_expect(zone.add_card(first), "HandZone accepts the first bound Card")
	_expect(zone.add_card(second), "HandZone accepts the second bound Card")
	_expect(zone.add_card(third), "HandZone accepts the third bound Card")
	await process_frame

	var incoming := _make_card()
	root.add_child(incoming)
	incoming.global_position = zone.global_position + Vector2(20.0, 0.0)
	_expect(zone.add_card(incoming), "HandZone accepts a Card dropped on the left")
	_expect(zone.cards[0] == incoming, "a Card dropped on the left is inserted at the beginning")

	var middle := _make_card()
	root.add_child(middle)
	middle.global_position = zone.get_global_rect().get_center() - middle.size * 0.5
	_expect(zone.add_card(middle), "HandZone accepts a Card dropped in the middle")
	var middle_index := zone.cards.find(middle)
	_expect(
		middle_index > 0 and middle_index < zone.cards.size() - 1,
		"a Card dropped in the hand middle is inserted between Cards"
	)

	zone.queue_free()
	await process_frame
	quit(1 if _failures > 0 else 0)


func _make_card() -> Card:
	var data := CardData.new()
	var card := CARD_SCENE.instantiate() as Card
	card.bind_card_inst(CardInstance.new(data))
	return card


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error(message)