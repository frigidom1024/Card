extends SceneTree

const HAND_ZONE_SCENE := preload("res://scenes/zone/handzone.tscn")
const CARD_SCENE := preload("res://scenes/card/card.tscn")
const TOLERANCE := 0.01

var _failures := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var zone := HAND_ZONE_SCENE.instantiate() as HandZone
	zone.set_anchors_preset(Control.PRESET_TOP_LEFT)
	zone.position = Vector2(300.0, 200.0)
	zone.size = Vector2(500.0, 220.0)
	zone.card_overlap = 20.0
	zone.float_amplitude = 0.0
	root.add_child(zone)

	var first := _make_card()
	var second := _make_card()
	var third := _make_card()
	_expect(zone.add_card(first), "HandZone accepts the first Card")
	_expect(zone.add_card(second), "HandZone accepts the second Card")
	_expect(zone.add_card(third), "HandZone accepts the third Card")
	await process_frame

	_expect(zone.cards.size() == 3, "HandZone registers Cards already present in the scene")
	_expect(first.target_position != Vector2.ZERO or second.target_position != Vector2.ZERO or third.target_position != Vector2.ZERO, "HandZone lays out existing Cards")

	var first_member := zone.cards[0]
	var second_member := zone.cards[1]
	var third_member := zone.cards[2]
	var card_width := first_member.size.x
	var step := card_width - zone.card_overlap
	var total_width := card_width + step * 2.0
	var start_x := (zone.size.x - total_width) * 0.5
	_expect(first_member.target_position.distance_to(Vector2(start_x, zone.card_row_y)) <= TOLERANCE, "first hand member is centered as part of the overlapped layout")
	_expect(absf(second_member.target_position.x - first_member.target_position.x - step) <= TOLERANCE, "second hand member advances by card width minus overlap")
	_expect(absf(third_member.target_position.x - second_member.target_position.x - step) <= TOLERANCE, "third hand member advances by card width minus overlap")
	_expect(first_member.target_position.y == zone.card_row_y and second_member.target_position.y == zone.card_row_y and third_member.target_position.y == zone.card_row_y, "hand members share the configured row")

	zone.free()
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