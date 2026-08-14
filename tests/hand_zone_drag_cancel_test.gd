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
	zone.size = Vector2(500.0, 220.0)
	zone.float_amplitude = 0.0
	root.add_child(zone)

	var card_data := CardData.new()
	var card_inst := CardInstance.new(card_data)
	var card := CARD_SCENE.instantiate() as Card
	card.bind_card_inst(card_inst)
	_expect(zone.add_card(card), "fixture adds the Card to HandZone")
	await process_frame

	var original_parent := card.get_parent()
	var original_target := card.target_position
	var original_rotation := card.rotation
	var original_z_index := card.z_index

	card.dragging = true
	zone.start_drag(card)
	_expect(zone.owns_card(card), "starting a drag keeps the Card as a stable HandZone member")
	_expect(zone.get_card_count() == 1, "starting a drag does not change the stable hand count")
	_expect(card.get_parent() == original_parent, "starting a drag does not reparent the Card")
	_expect(
		card_inst.cur_zone == CardInstance.ZONE.HAND,
		"starting a drag does not change CardInstance.cur_zone"
	)

	card.target_position = Vector2(999.0, 777.0)
	card.rotation = 1.25
	card.z_index = 100
	card.dragging = false
	_expect(zone.drag_end_source(card, false), "HandZone handles a cancelled source drag")
	_expect(zone.owns_card(card), "cancelled drag keeps the Card in HandZone")
	_expect(zone.get_card_count() == 1, "cancelled drag preserves the stable hand count")
	_expect(card.get_parent() == original_parent, "cancelled drag preserves the original parent")
	_expect(
		card.target_position.distance_to(original_target) <= TOLERANCE,
		"cancelled drag restores the hand layout target"
	)
	_expect(
		absf(card.rotation - original_rotation) <= TOLERANCE,
		"cancelled drag restores the hand rotation"
	)
	_expect(card.z_index == original_z_index, "cancelled drag restores the hand z-order")
	_expect(
		card_inst.cur_zone == CardInstance.ZONE.HAND,
		"cancelled drag preserves CardInstance.cur_zone"
	)

	zone.free()
	quit(1 if _failures > 0 else 0)


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error(message)
